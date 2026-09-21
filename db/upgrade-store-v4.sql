-- ============================================================
--  LibanApps Store — v4  (استيراد من WooCommerce + تحسينات)
--   • عدة تصنيفات للمنتج (category_ids) + ext_id لإعادة الاستيراد بدون تكرار
--   • سعر خاص لكل خيار/مقاس (sizes[].p) بالطلب
--   • store_public بيرجّع المنتجات بدون الوصف الطويل (أخف بكتير) + store_product_detail لجلب الوصف عند فتح المنتج
--  شغّله بعد upgrade-store-v3.sql — آمن للتشغيل أكثر من مرة.
-- ============================================================
alter table public.store_products add column if not exists category_ids uuid[] not null default '{}';
alter table public.store_products add column if not exists ext_id text;
create unique index if not exists store_products_ext_uq on public.store_products (store_id, ext_id);
create index if not exists store_products_cats_gin on public.store_products using gin (category_ids);
update public.store_products set category_ids = array[category_id] where category_id is not null and category_ids = '{}';

create or replace function public.store_product_detail(p_slug text, p_id uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('desc_ar', p.desc_ar, 'desc_en', p.desc_en)
  from public.store_products p join public.stores s on s.id = p.store_id
  where s.slug = lower(trim(p_slug)) and p.id = p_id and p.is_active;
$$;

create or replace function public.store_public(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st public.stores%rowtype; lic jsonb; gws jsonb; pop jsonb;
begin
  select * into st from public.stores where slug = lower(trim(coalesce(p_slug,'')));
  if not found then
    if exists (select 1 from public.subscriptions
               where product_code = 'store' and ref_slug = lower(trim(coalesce(p_slug,'')))) then
      return jsonb_build_object('ok', false, 'reason', 'not_ready');
    end if;
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  lic := public.store_license(st.id);
  if not st.is_active or not (lic->>'ok')::boolean then
    return jsonb_build_object('ok', false,
      'reason', case when not st.is_active then 'inactive' else coalesce(lic->>'reason','expired') end,
      'store', jsonb_build_object('name', st.name, 'logo_url', st.logo_url, 'logo_height', st.logo_height,
                                   'whatsapp', st.whatsapp, 'theme', st.theme));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('p', g.provider, 'label', coalesce(g.config->>'label',''),
                                               'note', case when g.provider = 'manual' then g.config->>'instructions' else '' end)
                            order by g.provider), '[]'::jsonb)
    into gws
  from public.store_gateways g
  where g.store_id = st.id and g.enabled
    and public._gw_ready(g.provider, g.config) and public._gw_supports(g.provider, st.currency_code);

  select to_jsonb(p) into pop from public.store_popups p
   where p.store_id = st.id and p.is_active
     and (p.starts_at is null or p.starts_at <= now())
     and (p.ends_at   is null or p.ends_at   >= now());

  return jsonb_build_object(
    'ok', true,
    'store', (to_jsonb(st) - 'client_id' - 'order_seq') || jsonb_build_object('gateways', gws),
    'categories', coalesce((select jsonb_agg(to_jsonb(c) order by c.sort, c.name_ar)
                            from public.store_categories c
                            where c.store_id = st.id and c.is_active), '[]'::jsonb),
    'products', coalesce((
        select jsonb_agg((to_jsonb(p) - 'store_id' - 'desc_ar' - 'desc_en') || jsonb_build_object(
                 'price', public._eff_price(p.price, p.compare_price, p.sale_ends_at), 'compare_price', public._eff_compare(p.price, p.compare_price, p.sale_ends_at),
                 'rating_avg', r.avg, 'rating_count', coalesce(r.n, 0)) order by p.sort, p.created_at)
        from (select * from public.store_products
              where store_id = st.id and is_active order by sort, created_at limit 2000) p
        left join lateral (select round(avg(rating)::numeric,1) as avg, count(*)::int as n
                           from public.store_reviews rv
                           where rv.product_id = p.id and rv.is_approved) r on true), '[]'::jsonb),
    'slides', coalesce((select jsonb_agg(to_jsonb(s) order by s.sort)
                        from public.store_slides s where s.store_id = st.id and s.is_active), '[]'::jsonb),
    'pages', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'title', g.title, 'body', g.body) order by g.sort)
                       from public.store_pages g where g.store_id = st.id and g.is_active), '[]'::jsonb),
    'banners', coalesce((select jsonb_agg(to_jsonb(b) order by b.sort)
                         from public.store_banners b where b.store_id = st.id and b.is_active), '[]'::jsonb),
    'popup', pop
  );
end $$;


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


select 'category_ids' as item, exists (select 1 from information_schema.columns where table_name='store_products' and column_name='category_ids') as ok
union all select 'ext_id', exists (select 1 from information_schema.columns where table_name='store_products' and column_name='ext_id')
union all select 'store_product_detail', exists (select 1 from pg_proc where proname='store_product_detail');
