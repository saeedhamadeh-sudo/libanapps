-- ============================================================
--  LibanApps Store — v9
--   • تأكيد رقم واتساب الزبون بكود (اختياري لكل متجر) قبل تثبيت الطلب
--     - stores.phone_verify_enabled: يفعّله التاجر من إعدادات متجره
--     - store_place_order: لو مفعّل، بيرفض الطلب إلا إذا الرقم انأكّد
--       فعليًا (phone_otps.used_at خلال آخر ٣٠ دقيقة) — نفس جدول أكواد
--       تسجيل الدخول بواتساب (upgrade-whatsapp-login.sql)، بس بدون
--       إنشاء أي حساب دخول.
--  شغّله بعد upgrade-store-v8.sql و upgrade-whatsapp-login.sql —
--  آمن للتشغيل أكثر من مرة.
-- ============================================================
alter table public.stores add column if not exists phone_verify_enabled boolean not null default false;

create or replace function public.store_place_order(
  p_slug text, p_name text, p_phone text, p_email text, p_method text,
  p_zone text, p_city text, p_address text, p_note text, p_payment text, p_coupon text, p_lines jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  st public.stores%rowtype; pr public.store_products%rowtype; gw public.store_gateways%rowtype;
  v_sub numeric := 0; v_disc numeric := 0; v_fee numeric := 0; v_tot numeric;
  v_no text; v_id bigint; v_tok text; v_cp jsonb; v_code text := '';
  ln record; v_qty integer; v_items jsonb := '[]'::jsonb; v_price numeric; sz jsonb; cl jsonb;
  z jsonb; v_zone text := ''; v_online boolean := false; v_note text := '';
begin
  select * into st from public.stores where slug = lower(trim(coalesce(p_slug,''))) for update;
  if not found or not st.is_active or not (public.store_license(st.id)->>'ok')::boolean then
    raise exception 'store unavailable'; end if;

  if length(trim(coalesce(p_name,''))) < 2 or length(regexp_replace(coalesce(p_phone,''),'\D','','g')) < 7 then
    raise exception 'invalid customer details'; end if;

  if st.phone_verify_enabled and not exists (
    select 1 from public.phone_otps
    where phone = public.norm_phone_lb(p_phone) and used_at is not null and used_at > now() - interval '30 minutes'
  ) then
    raise exception 'phone not verified';
  end if;

  if p_method not in ('delivery','pickup') then raise exception 'bad method'; end if;
  if p_method = 'delivery' and not st.delivery_enabled then raise exception 'delivery disabled'; end if;
  if p_method = 'pickup'   and not st.pickup_enabled   then raise exception 'pickup disabled'; end if;
  if p_method = 'delivery' and length(trim(coalesce(p_address,''))) < 3 then raise exception 'address required'; end if;

  -- الدفع
  if p_payment = 'cod' then
    if not st.cod_enabled then raise exception 'cod disabled'; end if;
  else
    select * into gw from public.store_gateways where store_id = st.id and provider = p_payment and enabled;
    if not found or not public._gw_ready(gw.provider, gw.config) or not public._gw_supports(gw.provider, st.currency_code) then
      raise exception 'payment method disabled'; end if;
    v_online := p_payment <> 'manual';
  end if;

  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'empty cart'; end if;

  for ln in
    select x.id, coalesce(x.size,'') as size, coalesce(x.color,'') as color,
           sum(greatest(1, least(99, coalesce(x.qty,1))))::int as qty
    from jsonb_to_recordset(p_lines) as x(id uuid, qty int, size text, color text)
    group by x.id, coalesce(x.size,''), coalesce(x.color,'')
  loop
    v_qty := ln.qty;
    select * into pr from public.store_products where id = ln.id and store_id = st.id and is_active for update;
    if not found then raise exception 'product unavailable'; end if;

    if jsonb_array_length(pr.sizes) > 0 then
      select e into sz from jsonb_array_elements(pr.sizes) e where e->>'n' = ln.size limit 1;
      if sz is null or coalesce((sz->>'on')::boolean, true) = false then
        raise exception 'insufficient stock: %', coalesce(nullif(pr.name_ar,''), pr.name_en) || ' ' || ln.size; end if;
      if jsonb_typeof(sz->'s') = 'number' and (sz->>'s')::int < v_qty then
        raise exception 'insufficient stock: %', coalesce(nullif(pr.name_ar,''), pr.name_en) || ' ' || ln.size; end if;
    elsif pr.stock is not null and pr.stock < v_qty then
      raise exception 'insufficient stock: %', coalesce(nullif(pr.name_ar,''), pr.name_en);
    end if;

    if jsonb_array_length(pr.colors) > 0 then
      select e into cl from jsonb_array_elements(pr.colors) e where e->>'n' = ln.color limit 1;
      if cl is null or coalesce((cl->>'on')::boolean, true) = false then
        raise exception 'insufficient stock: %', coalesce(nullif(pr.name_ar,''), pr.name_en) || ' ' || ln.color; end if;
    end if;

    v_price := public._eff_price(pr.price, pr.compare_price, pr.sale_ends_at);
    if sz is not null and jsonb_array_length(pr.sizes) > 0 and coalesce(sz->>'p','') ~ '^[0-9]+(\.[0-9]+)?$' then
      v_price := (sz->>'p')::numeric;                                    -- سعر خاص للخيار/المقاس
    end if;
    v_sub := v_sub + v_price * v_qty;
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'id', pr.id, 'name', coalesce(nullif(pr.name_ar,''), pr.name_en), 'price', v_price,
      'qty', v_qty, 'size', ln.size, 'color', ln.color, 'hassz', jsonb_array_length(pr.sizes) > 0));
  end loop;

  if v_sub < st.min_order then raise exception 'min order'; end if;

  if coalesce(trim(p_coupon),'') <> '' then
    v_cp := public._store_coupon_calc(st.id, p_coupon, v_sub);
    if not (v_cp->>'ok')::boolean then raise exception 'coupon: %', v_cp->>'reason'; end if;
    v_disc := (v_cp->>'discount')::numeric; v_code := v_cp->>'code';
  end if;

  if p_method = 'delivery' then
    if jsonb_array_length(st.shipping_zones) > 0 then
      select e into z from jsonb_array_elements(st.shipping_zones) e where e->>'n' = p_zone limit 1;
      if z is null then raise exception 'zone required'; end if;
      v_fee := coalesce((z->>'f')::numeric, 0); v_zone := z->>'n';
    else
      v_fee := st.delivery_fee;
    end if;
    if st.free_delivery_over is not null and (v_sub - v_disc) >= st.free_delivery_over then v_fee := 0; end if;
  end if;

  v_sub := round(v_sub, st.currency_decimals);
  v_tot := round(v_sub - v_disc + v_fee, st.currency_decimals);

  update public.stores set order_seq = order_seq + 1 where id = st.id returning order_seq into v_id;
  v_no := 'S' || lpad(v_id::text, 4, '0');

  insert into public.store_orders (store_id, order_no, customer_name, customer_phone, customer_email,
      delivery_method, city, address_text, customer_note, subtotal, discount, coupon_code,
      delivery_fee, total, currency_code, payment_method, shipping_zone, status)
  values (st.id, v_no, trim(p_name), trim(p_phone), coalesce(trim(p_email),''),
      p_method, coalesce(nullif(trim(p_city),''), v_zone), coalesce(trim(p_address),''), coalesce(trim(p_note),''),
      v_sub, v_disc, v_code, v_fee, v_tot, st.currency_code, p_payment, v_zone,
      case when v_online then 'awaiting_payment' else 'pending' end)
  returning id, token into v_id, v_tok;

  insert into public.store_order_items (order_id, product_id, name, unit_price, qty, line_total, size, color)
  select v_id, (i->>'id')::uuid, i->>'name', (i->>'price')::numeric, (i->>'qty')::int,
         round((i->>'price')::numeric * (i->>'qty')::int, st.currency_decimals), i->>'size', i->>'color'
  from jsonb_array_elements(v_items) i;

  -- المخزون: بالمقاس إذا فيه مقاسات، وإلا بالمنتج
  for ln in select (i->>'id')::uuid as id, i->>'size' as size, (i->>'qty')::int as qty, (i->>'hassz')::boolean as hassz
            from jsonb_array_elements(v_items) i loop
    if ln.hassz then perform public._size_stock_add(ln.id, ln.size, -ln.qty);
    else update public.store_products set stock = stock - ln.qty where id = ln.id and stock is not null; end if;
  end loop;

  if v_code <> '' then
    update public.store_coupons set used_count = used_count + 1 where store_id = st.id and code = v_code;
  end if;

  if p_payment = 'manual' then v_note := coalesce(gw.config->>'instructions',''); end if;

  return jsonb_build_object(
    'order_id', v_id, 'order_no', v_no, 'token', v_tok, 'subtotal', v_sub, 'discount', v_disc,
    'delivery_fee', v_fee, 'total', v_tot, 'currency_code', st.currency_code,
    'currency_symbol', st.currency_symbol, 'currency_decimals', st.currency_decimals,
    'whatsapp', st.whatsapp, 'online', v_online, 'note', v_note);
end $$;

select 'stores.phone_verify_enabled' as item,
       exists (select 1 from information_schema.columns where table_name='stores' and column_name='phone_verify_enabled') as ok
union all
select 'store_place_order', exists (select 1 from pg_proc where proname='store_place_order')
union all
select 'norm_phone_lb', exists (select 1 from pg_proc where proname='norm_phone_lb')
union all
select 'phone_otps', exists (select 1 from information_schema.tables where table_name='phone_otps');
