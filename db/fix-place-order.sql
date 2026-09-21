-- ============================================================
--  إصلاح تعارض اسم العمود token في place_order
--  شغّله لحاله بـ SQL Editor، أو شغّل db/schema.sql كامل
--  الاثنان يعطيان نفس النتيجة، ولا يحذفان أي بيانات
-- ============================================================

create or replace function public.place_order(
  p_slug text, p_type text, p_name text, p_phone text, p_table text,
  p_address text, p_lat double precision, p_lng double precision,
  p_note text, p_payment text, p_lines jsonb
) returns table (order_id bigint, order_no text, token text, total_usd numeric, total_lbp numeric)
language plpgsql security definer set search_path = public as $$
declare
  r public.restaurants%rowtype;
  v_sub numeric(10,2) := 0; v_del numeric(10,2) := 0;
  v_tot numeric(10,2); v_lbp numeric(14,0);
  v_no text; v_id bigint; v_tok text;
  ln jsonb; it public.items%rowtype; v_qty integer;
begin
  select * into r from public.restaurants where slug = p_slug;
  if not found or not public.menu_live(r.id) then raise exception 'restaurant unavailable'; end if;
  if p_type = 'dine_in'  and not r.dinein_enabled   then raise exception 'dine-in disabled'; end if;
  if p_type = 'delivery' and not r.delivery_enabled then raise exception 'delivery disabled'; end if;
  if length(trim(p_name)) < 2 or length(regexp_replace(p_phone,'\D','','g')) < 7 then
    raise exception 'invalid customer details'; end if;
  if p_type = 'delivery' and r.require_location and (p_lat is null or p_lng is null) then
    raise exception 'location required'; end if;
  if jsonb_array_length(p_lines) = 0 or jsonb_array_length(p_lines) > 60 then
    raise exception 'invalid cart'; end if;

  r.order_seq := r.order_seq + 1;
  update public.restaurants set order_seq = r.order_seq where id = r.id;
  v_no := upper(left(r.slug, 2)) || '-' || (1000 + r.order_seq);

  insert into public.orders (restaurant_id, order_no, order_type, customer_name, customer_phone,
                             table_no, address_text, lat, lng, customer_note,
                             subtotal_usd, delivery_usd, total_usd, exchange_rate, total_lbp,
                             payment_method, status)
  values (r.id, v_no, p_type, trim(p_name), trim(p_phone),
          coalesce(p_table,''), coalesce(p_address,''), p_lat, p_lng, coalesce(p_note,''),
          0, 0, 0, r.exchange_rate, 0, p_payment,
          case when p_payment = 'whish' then 'awaiting_payment' else 'pending' end)
  returning orders.id, orders.token into v_id, v_tok;

  for ln in select * from jsonb_array_elements(p_lines) loop
    v_qty := greatest(1, least(50, (ln->>'qty')::int));
    select * into it from public.items
      where id = (ln->>'item_id')::uuid and restaurant_id = r.id and is_available;
    if found then
      insert into public.order_items (order_id, item_id, name_ar, name_en, price_usd, qty, line_usd)
      values (v_id, it.id, it.name_ar, it.name_en, it.price_usd, v_qty, it.price_usd * v_qty);
      v_sub := v_sub + it.price_usd * v_qty;
    end if;
  end loop;

  if v_sub = 0 then delete from public.orders where id = v_id; raise exception 'empty cart'; end if;
  if p_type = 'delivery' then
    if v_sub < r.min_order_usd then
      delete from public.orders where id = v_id; raise exception 'below minimum order'; end if;
    v_del := r.delivery_fee_usd;
  end if;

  v_tot := v_sub + v_del;
  v_lbp := round(v_tot * r.exchange_rate / r.lbp_rounding) * r.lbp_rounding;
  update public.orders set subtotal_usd = v_sub, delivery_usd = v_del,
         total_usd = v_tot, total_lbp = v_lbp where id = v_id;

  return query select v_id, v_no, v_tok, v_tot, v_lbp;
end $$;
