-- ============================================================
--  LibanApps — صلاحيات المطاعم/المحلات + أسعار التوصيل (مناطق / مسافة / ثابت)
--             + وصول الطلب للشوفير إذا المطعم مش فاتح لوحتو
--  آمن للتشغيل أكثر من مرة
-- ============================================================

-- ---------- 0) القوالب: لوغو وقسم المطعم/المحل ----------
update public.menu_templates set data = jsonb_set(data, '{vendor}', (data->'vendor') || '{"group_ar":"مطاعم","group_en":"Restaurants"}'::jsonb)
 where code = 'route66' and coalesce(data->'vendor'->>'group_ar','') = '';

create or replace function public.super_apply_menu_template(p_rid uuid, p_code text, p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t public.menu_templates%rowtype; r public.restaurants%rowtype; c jsonb; i jsonb; v jsonb;
        v_sort integer; v_cid uuid; v_bid uuid := null; v_new_vendor boolean := false;
        n_c integer := 0; n_i integer := 0; v_isort integer;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  select * into t from public.menu_templates where code = p_code;
  if not found then raise exception 'template not found'; end if;
  select * into r from public.restaurants where id = p_rid;
  if not found then raise exception 'restaurant not found'; end if;

  if coalesce(r.vendors_mode,false) then
    v := coalesce(t.data->'vendor', jsonb_build_object('name_ar', t.name, 'name_en', t.name));
    select id into v_bid from public.restaurant_branches
     where restaurant_id = p_rid
       and (lower(name_en) = lower(coalesce(v->>'name_en','')) or name_ar = v->>'name_ar')
     order by sort limit 1;
    if v_bid is null then
      insert into public.restaurant_branches (restaurant_id, name_ar, name_en, phone, address_ar, address_en,
                                              image_url, group_ar, group_en, work_hours, is_active, sort)
      values (p_rid, v->>'name_ar', coalesce(v->>'name_en', v->>'name_ar'), coalesce(v->>'phone',''),
              coalesce(v->>'address_ar',''), coalesce(v->>'address_en',''),
              coalesce(v->>'image_url',''), coalesce(v->>'group_ar',''), coalesce(v->>'group_en',''),
              coalesce(v->'work_hours', '{"sun":[{"open":"00:00","close":"23:59"}],"mon":[{"open":"00:00","close":"23:59"}],"tue":[{"open":"00:00","close":"23:59"}],"wed":[{"open":"00:00","close":"23:59"}],"thu":[{"open":"00:00","close":"23:59"}],"fri":[{"open":"00:00","close":"23:59"}],"sat":[{"open":"00:00","close":"23:59"}]}'::jsonb),
              true, coalesce((select max(sort) from public.restaurant_branches where restaurant_id = p_rid),0) + 1)
      returning id into v_bid;
      v_new_vendor := true;
    else
      update public.restaurant_branches set is_active = true,
             image_url = case when coalesce(image_url,'') = '' then coalesce(v->>'image_url','') else image_url end,
             group_ar  = case when coalesce(group_ar,'') = '' then coalesce(v->>'group_ar','') else group_ar end,
             group_en  = case when coalesce(group_en,'') = '' then coalesce(v->>'group_en','') else group_en end
       where id = v_bid;
      if p_replace then
        delete from public.items where category_id in (select id from public.categories where vendor_id = v_bid);
        delete from public.categories where vendor_id = v_bid;
      end if;
    end if;
  elsif p_replace then
    delete from public.items where restaurant_id = p_rid;
    delete from public.categories where restaurant_id = p_rid;
  end if;

  select coalesce(max(sort),0) into v_sort from public.categories where restaurant_id = p_rid;
  for c in select * from jsonb_array_elements(t.data->'categories') loop
    v_sort := v_sort + 1; n_c := n_c + 1;
    insert into public.categories (restaurant_id, name_ar, name_en, sort, is_active, builder, vendor_id)
    values (p_rid, c->>'name_ar', coalesce(c->>'name_en', c->>'name_ar'), v_sort, true, c->'builder', v_bid)
    returning id into v_cid;
    v_isort := 0;
    for i in select * from jsonb_array_elements(coalesce(c->'items','[]'::jsonb)) loop
      v_isort := v_isort + 1; n_i := n_i + 1;
      insert into public.items (restaurant_id, category_id, name_ar, name_en, desc_ar, desc_en,
                                price_usd, image_url, is_available, is_featured, sort)
      values (p_rid, v_cid, i->>'name_ar', coalesce(i->>'name_en', i->>'name_ar'),
              coalesce(i->>'desc_ar',''), coalesce(i->>'desc_en',''),
              coalesce((i->>'price_usd')::numeric,0), coalesce(i->>'image_url',''), true,
              coalesce((i->>'is_featured')::boolean,false), v_isort);
    end loop;
  end loop;
  return jsonb_build_object('ok', true, 'categories', n_c, 'items', n_i,
    'vendor', case when v_bid is null then null else jsonb_build_object('id', v_bid, 'new', v_new_vendor,
               'name', (select name_ar from public.restaurant_branches where id = v_bid)) end);
end $$;

-- ---------- 1) صلاحيات المطعم/المحل من رابطو ----------
alter table public.restaurant_branches
  add column if not exists can_edit_prices boolean not null default false,  -- يعدّل الأسعار ويوقف/يرجّع صنف
  add column if not exists can_add_items   boolean not null default false,  -- يزيد منتجات
  add column if not exists panel_seen_at   timestamptz,                     -- آخر مرة كانت لوحتو مفتوحة
  add column if not exists lat double precision,
  add column if not exists lng double precision;

-- طلبات المحل اللي بدها موافقة الأدمن (حذف منتج)
create table if not exists public.vendor_requests (
  id            bigint generated always as identity primary key,
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  branch_id     uuid not null references public.restaurant_branches(id) on delete cascade,
  kind          text not null default 'delete_item' check (kind in ('delete_item')),
  item_id       uuid references public.items(id) on delete cascade,
  item_name     text not null default '',
  reason        text not null default '',
  status        text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at    timestamptz not null default now(),
  decided_at    timestamptz
);
create index if not exists vendor_requests_rest_idx on public.vendor_requests (restaurant_id, status, created_at desc);
alter table public.vendor_requests enable row level security;
drop policy if exists "vendor_requests_member" on public.vendor_requests;
create policy "vendor_requests_member" on public.vendor_requests
  for all using (public.is_member(restaurant_id)) with check (public.is_member(restaurant_id));

create or replace function public._vendor(p_token text)
returns public.restaurant_branches language plpgsql stable security definer set search_path = public as $$
declare b public.restaurant_branches;
begin
  select rb.* into b from public.vendor_links l join public.restaurant_branches rb on rb.id = l.branch_id where l.token = p_token;
  if not found then raise exception 'invalid link'; end if;
  return b;
end $$;

-- منتجات هالمطعم/المحل (أقسامه وأقسامها الفرعية)
create or replace function public._vendor_item(p_bid uuid, p_item uuid)
returns public.items language plpgsql stable security definer set search_path = public as $$
declare it public.items;
begin
  select i.* into it from public.items i join public.categories c on c.id = i.category_id
   left join public.categories p on p.id = c.parent_id
   where i.id = p_item and (c.vendor_id = p_bid or p.vendor_id = p_bid);
  if not found then raise exception 'item not found'; end if;
  return it;
end $$;

create or replace function public.vendor_menu(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.restaurant_branches;
begin
  b := public._vendor(p_token);
  return jsonb_build_object(
    'perms', jsonb_build_object('edit', b.can_edit_prices, 'add', b.can_add_items),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name_ar',c.name_ar,'name_en',c.name_en,
                     'parent_id',c.parent_id,'builder',c.builder is not null) order by c.sort)
                   from public.categories c left join public.categories p on p.id = c.parent_id
                   where c.vendor_id = b.id or p.vendor_id = b.id), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'category_id',i.category_id,'name_ar',i.name_ar,
                     'name_en',i.name_en,'desc_ar',i.desc_ar,'price_usd',i.price_usd,'is_available',i.is_available,
                     'image_url',i.image_url) order by i.sort)
                   from public.items i join public.categories c on c.id = i.category_id
                   left join public.categories p on p.id = c.parent_id
                   where c.vendor_id = b.id or p.vendor_id = b.id), '[]'::jsonb),
    'requests', coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'item_id',q.item_id,'item_name',q.item_name,
                     'status',q.status,'created_at',q.created_at) order by q.created_at desc)
                   from public.vendor_requests q where q.branch_id = b.id and q.created_at > now() - interval '30 days'), '[]'::jsonb));
end $$;

create or replace function public.vendor_update_item(p_token text, p_item uuid, p_price numeric default null, p_available boolean default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.restaurant_branches; it public.items;
begin
  b := public._vendor(p_token);
  if not b.can_edit_prices then raise exception 'not allowed'; end if;
  it := public._vendor_item(b.id, p_item);
  if p_price is not null and (p_price < 0 or p_price > 100000) then raise exception 'bad price'; end if;
  update public.items set price_usd = coalesce(p_price, price_usd), is_available = coalesce(p_available, is_available)
   where id = it.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.vendor_add_item(p_token text, p_category uuid, p_name_ar text, p_name_en text,
                                                  p_desc_ar text, p_price numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.restaurant_branches; c public.categories; v_id uuid;
begin
  b := public._vendor(p_token);
  if not b.can_add_items then raise exception 'not allowed'; end if;
  select cc.* into c from public.categories cc left join public.categories p on p.id = cc.parent_id
   where cc.id = p_category and (cc.vendor_id = b.id or p.vendor_id = b.id);
  if not found then raise exception 'category not found'; end if;
  if length(trim(coalesce(p_name_ar,''))) < 2 then raise exception 'name required'; end if;
  if p_price is null or p_price < 0 or p_price > 100000 then raise exception 'bad price'; end if;
  insert into public.items (restaurant_id, category_id, name_ar, name_en, desc_ar, price_usd, is_available, sort)
  values (b.restaurant_id, c.id, trim(p_name_ar), coalesce(nullif(trim(p_name_en),''), trim(p_name_ar)),
          coalesce(trim(p_desc_ar),''), p_price, true,
          coalesce((select max(sort) from public.items where category_id = c.id),0) + 1)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.vendor_request_delete(p_token text, p_item uuid, p_reason text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare b public.restaurant_branches; it public.items;
begin
  b := public._vendor(p_token);
  if not (b.can_edit_prices or b.can_add_items) then raise exception 'not allowed'; end if;
  it := public._vendor_item(b.id, p_item);
  if exists (select 1 from public.vendor_requests where item_id = it.id and status = 'pending') then
    return jsonb_build_object('ok', true, 'already', true); end if;
  insert into public.vendor_requests (restaurant_id, branch_id, item_id, item_name, reason)
  values (b.restaurant_id, b.id, it.id, it.name_ar, coalesce(p_reason,''));
  return jsonb_build_object('ok', true);
end $$;

-- الأدمن بيوافق أو بيرفض
create or replace function public.admin_vendor_request(p_id bigint, p_approve boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare q public.vendor_requests;
begin
  select * into q from public.vendor_requests where id = p_id;
  if not found or not public.is_member(q.restaurant_id) then raise exception 'not allowed'; end if;
  if q.status <> 'pending' then return jsonb_build_object('ok', false); end if;
  update public.vendor_requests set status = case when p_approve then 'approved' else 'rejected' end, decided_at = now()
   where id = q.id;
  if p_approve and q.item_id is not null then delete from public.items where id = q.item_id; end if;
  return jsonb_build_object('ok', true);
end $$;

grant execute on function public.vendor_menu(text) to anon, authenticated;
grant execute on function public.vendor_update_item(text, uuid, numeric, boolean) to anon, authenticated;
grant execute on function public.vendor_add_item(text, uuid, text, text, text, numeric) to anon, authenticated;
grant execute on function public.vendor_request_delete(text, uuid, text) to anon, authenticated;
grant execute on function public.admin_vendor_request(bigint, boolean) to authenticated;
revoke execute on function public._vendor(text) from public, anon, authenticated;
revoke execute on function public._vendor_item(uuid, uuid) from public, anon, authenticated;

-- لوحة المحل: بتسجّل إنها مفتوحة + بترجّع الصلاحيات
create or replace function public.vendor_panel(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_bid uuid; b public.restaurant_branches%rowtype; r public.restaurants%rowtype; v_orders jsonb;
begin
  select branch_id into v_bid from public.vendor_links where token = p_token;
  if v_bid is null then raise exception 'invalid link'; end if;
  update public.restaurant_branches set panel_seen_at = now() where id = v_bid;
  select * into b from public.restaurant_branches where id = v_bid;
  select * into r from public.restaurants where id = b.restaurant_id;
  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb) into v_orders from (
    select jsonb_build_object(
      'id', o.id, 'order_no', o.order_no, 'order_type', o.order_type,
      'customer_name', o.customer_name, 'customer_note', o.customer_note,
      'subtotal_usd', o.subtotal_usd, 'payment_method', o.payment_method,
      'status', o.status, 'branch_status', o.branch_status, 'dispatch', coalesce(o.dispatch,''),
      'reason', coalesce(nullif(o.rejection_reason,''), o.reject_reason, ''),
      'created_at', o.created_at,
      'driver', (select jsonb_build_object('name', d.name, 'phone', d.phone) from public.drivers d where d.id = o.driver_id),
      'items', (select coalesce(jsonb_agg(jsonb_build_object('name_ar', oi.name_ar, 'name_en', oi.name_en, 'qty', oi.qty, 'line_usd', oi.line_usd)), '[]'::jsonb)
                from public.order_items oi where oi.order_id = o.id)
    ) as x
    from public.orders o
    where o.branch_id = v_bid and o.created_at > now() - interval '36 hours' and o.status <> 'awaiting_payment'
    order by o.created_at desc limit 80
  ) s;
  return jsonb_build_object(
    'vendor', jsonb_build_object('name_ar', b.name_ar, 'name_en', b.name_en, 'image_url', b.image_url,
                                 'force_closed', b.force_closed, 'is_active', b.is_active,
                                 'can_edit', b.can_edit_prices, 'can_add', b.can_add_items),
    'company', jsonb_build_object('name_ar', r.name_ar, 'name_en', r.name_en, 'logo_url', r.logo_url,
                                  'phone', r.phone, 'whatsapp', r.whatsapp, 'theme', r.theme),
    'orders', v_orders);
end $$;

-- ---------- 2) أسعار التوصيل: ثابت / مناطق / مسافة ----------
alter table public.restaurants
  add column if not exists delivery_pricing text not null default 'fixed',
  add column if not exists dlv_base_usd   numeric(8,2) not null default 0,
  add column if not exists dlv_per_km_usd numeric(8,2) not null default 0,
  add column if not exists dlv_max_km     numeric(6,1),
  add column if not exists origin_lat double precision,
  add column if not exists origin_lng double precision;
alter table public.restaurants drop constraint if exists restaurants_delivery_pricing_chk;
alter table public.restaurants add constraint restaurants_delivery_pricing_chk
  check (delivery_pricing in ('fixed','zones','distance'));

create table if not exists public.delivery_zones (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  name_ar       text not null,
  name_en       text not null default '',
  fee_usd       numeric(8,2) not null default 0,
  sort          integer not null default 0,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);
create index if not exists delivery_zones_rest_idx on public.delivery_zones (restaurant_id, sort);
alter table public.delivery_zones enable row level security;
drop policy if exists "delivery_zones_read" on public.delivery_zones;
drop policy if exists "delivery_zones_member" on public.delivery_zones;
create policy "delivery_zones_read" on public.delivery_zones for select using (is_active or public.is_member(restaurant_id));
create policy "delivery_zones_member" on public.delivery_zones
  for all using (public.is_member(restaurant_id)) with check (public.is_member(restaurant_id));

alter table public.orders
  add column if not exists zone_id uuid references public.delivery_zones(id) on delete set null,
  add column if not exists distance_km numeric(6,2);

-- المسافة بالطريق تقريباً = الخط المستقيم × 1.3
create or replace function public.road_km(a_lat double precision, a_lng double precision, b_lat double precision, b_lng double precision)
returns numeric language sql immutable as $$
  select round((2 * 6371 * asin(sqrt(
           power(sin(radians(b_lat - a_lat) / 2), 2) +
           cos(radians(a_lat)) * cos(radians(b_lat)) * power(sin(radians(b_lng - a_lng) / 2), 2))) * 1.3)::numeric, 1)
$$;

-- رسم التوصيل: {fee, km, zone}
create or replace function public.calc_delivery(p_rid uuid, p_branch uuid, p_zone uuid,
                                                p_lat double precision, p_lng double precision)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r public.restaurants; b public.restaurant_branches; z public.delivery_zones;
        o_lat double precision; o_lng double precision; km numeric; fee numeric;
begin
  select * into r from public.restaurants where id = p_rid;
  if p_branch is not null then select * into b from public.restaurant_branches where id = p_branch; end if;
  -- المحل إلو رسم خاص فيه؟
  if b.id is not null and b.delivery_enabled then
    return jsonb_build_object('fee', b.delivery_fee_usd, 'km', null, 'zone', null); end if;

  if r.delivery_pricing = 'zones' then
    select * into z from public.delivery_zones where id = p_zone and restaurant_id = p_rid and is_active;
    if not found then raise exception 'zone required'; end if;
    return jsonb_build_object('fee', z.fee_usd, 'km', null, 'zone', z.id);
  elsif r.delivery_pricing = 'distance' then
    o_lat := coalesce(b.lat, r.origin_lat); o_lng := coalesce(b.lng, r.origin_lng);
    if o_lat is null or p_lat is null then
      return jsonb_build_object('fee', r.delivery_fee_usd, 'km', null, 'zone', null); end if;
    km := public.road_km(o_lat, o_lng, p_lat, p_lng);
    if r.dlv_max_km is not null and km > r.dlv_max_km then raise exception 'out of delivery range'; end if;
    fee := ceil((r.dlv_base_usd + r.dlv_per_km_usd * km) * 4) / 4;   -- لأقرب ربع دولار لفوق
    return jsonb_build_object('fee', fee, 'km', km, 'zone', null);
  end if;
  return jsonb_build_object('fee', r.delivery_fee_usd, 'km', null, 'zone', null);
end $$;
grant execute on function public.calc_delivery(uuid, uuid, uuid, double precision, double precision) to anon, authenticated;

-- place_order: + p_zone
drop function if exists public.place_order(text,text,text,text,text,text,double precision,double precision,text,text,jsonb);
create or replace function public.place_order(
  p_slug text, p_type text, p_name text, p_phone text, p_table text,
  p_address text, p_lat double precision, p_lng double precision,
  p_note text, p_payment text, p_lines jsonb, p_zone uuid default null
) returns table (order_id bigint, order_no text, token text, total_usd numeric, total_lbp numeric)
language plpgsql security definer set search_path = public as $$
declare
  r public.restaurants%rowtype;
  v_sub numeric(10,2) := 0; v_del numeric(10,2) := 0;
  v_tot numeric(10,2); v_lbp numeric(14,0);
  v_no text; v_id bigint; v_tok text;
  ln jsonb; it public.items%rowtype; v_qty integer;
  v_builder jsonb; g jsonb; v_sel jsonb;
  v_unit numeric(10,2); v_opts jsonb; v_lab_ar text; v_lab_en text;
  v_cnt integer; v_add numeric(10,2); v_gar text; v_gen text; v_gjs jsonb; v_bad integer;
  v_dl jsonb;
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
  -- بوضع المحلات رسم التوصيل بيتحدد لاحقاً حسب المحل (set_order_vendor)
  if p_type = 'delivery' and not coalesce(r.vendors_mode,false) then
    v_dl := public.calc_delivery(r.id, null, p_zone, p_lat, p_lng);
  elsif p_type = 'delivery' and r.delivery_pricing = 'zones' then
    v_dl := public.calc_delivery(r.id, null, p_zone, p_lat, p_lng);
  end if;

  r.order_seq := r.order_seq + 1;
  update public.restaurants set order_seq = r.order_seq where id = r.id;
  v_no := upper(left(r.slug, 2)) || '-' || (1000 + r.order_seq);

  insert into public.orders (restaurant_id, order_no, order_type, customer_name, customer_phone,
                             table_no, address_text, lat, lng, customer_note,
                             subtotal_usd, delivery_usd, total_usd, exchange_rate, total_lbp,
                             payment_method, status, zone_id, distance_km)
  values (r.id, v_no, p_type, trim(p_name), trim(p_phone),
          coalesce(p_table,''), coalesce(p_address,''), p_lat, p_lng, coalesce(p_note,''),
          0, 0, 0, r.exchange_rate, 0, p_payment,
          case when p_payment = 'whish' then 'awaiting_payment' else 'pending' end,
          case when p_type = 'delivery' then p_zone end, (v_dl->>'km')::numeric)
  returning orders.id, orders.token into v_id, v_tok;

  for ln in select * from jsonb_array_elements(p_lines) loop
    v_qty := greatest(1, least(50, (ln->>'qty')::int));
    select * into it from public.items
      where id = (ln->>'item_id')::uuid and restaurant_id = r.id and is_available;
    if not found then continue; end if;

    v_unit := it.price_usd; v_opts := null; v_lab_ar := ''; v_lab_en := '';
    select c.builder into v_builder from public.categories c where c.id = it.category_id;

    if v_builder is not null and jsonb_typeof(v_builder->'groups') = 'array' then
      v_opts := '[]'::jsonb;
      for g in select * from jsonb_array_elements(v_builder->'groups') loop
        continue when g->>'key' = '__item';
        v_sel := ln->'opts'->(g->>'key');
        if v_sel is null or jsonb_typeof(v_sel) <> 'array' then v_sel := '[]'::jsonb; end if;
        select count(*) into v_bad from jsonb_array_elements_text(v_sel) s(id)
         where not exists (select 1 from jsonb_array_elements(coalesce(g->'choices','[]'::jsonb)) ch
                            where ch->>'id' = s.id and not coalesce((ch->>'off')::boolean,false));
        if v_bad > 0 then raise exception 'invalid option'; end if;
        select count(*), coalesce(sum((ch->>'price')::numeric),0),
               string_agg(ch->>'name_ar', '، '), string_agg(ch->>'name_en', ', '),
               coalesce(jsonb_agg(jsonb_build_object('id',ch->>'id','name_ar',ch->>'name_ar',
                          'name_en',ch->>'name_en','price',(ch->>'price')::numeric)),'[]'::jsonb)
          into v_cnt, v_add, v_gar, v_gen, v_gjs
          from jsonb_array_elements(coalesce(g->'choices','[]'::jsonb)) ch
         where ch->>'id' in (select distinct x from jsonb_array_elements_text(v_sel) t(x));
        if v_cnt < coalesce((g->>'min')::int,0) then raise exception 'missing option: %', g->>'name_en'; end if;
        if (g->>'max') is not null and v_cnt > (g->>'max')::int then raise exception 'too many options: %', g->>'name_en'; end if;
        if v_cnt > 0 then
          v_unit := v_unit + v_add;
          v_opts := v_opts || jsonb_build_array(jsonb_build_object('key',g->>'key',
                      'name_ar',g->>'name_ar','name_en',g->>'name_en','choices',v_gjs));
          v_lab_ar := v_lab_ar || case when v_lab_ar = '' then '' else ' · ' end || v_gar;
          v_lab_en := v_lab_en || case when v_lab_en = '' then '' else ' · ' end || v_gen;
        end if;
      end loop;
    end if;

    insert into public.order_items (order_id, item_id, name_ar, name_en, price_usd, qty, line_usd, options)
    values (v_id, it.id,
            it.name_ar || case when v_lab_ar <> '' then ' — ' || v_lab_ar else '' end,
            it.name_en || case when v_lab_en <> '' then ' — ' || v_lab_en else '' end,
            v_unit, v_qty, v_unit * v_qty, v_opts);
    v_sub := v_sub + v_unit * v_qty;
  end loop;

  if v_sub = 0 then raise exception 'empty cart'; end if;
  if p_type = 'delivery' then
    if v_sub < r.min_order_usd then raise exception 'below minimum order'; end if;
    v_del := coalesce((v_dl->>'fee')::numeric, r.delivery_fee_usd);
  end if;

  v_tot := v_sub + v_del;
  v_lbp := round(v_tot * r.exchange_rate / r.lbp_rounding) * r.lbp_rounding;
  update public.orders set subtotal_usd = v_sub, delivery_usd = v_del,
         total_usd = v_tot, total_lbp = v_lbp where id = v_id;

  return query select v_id, v_no, v_tok, v_tot, v_lbp;
end $$;
grant execute on function public.place_order(text,text,text,text,text,text,double precision,double precision,text,text,jsonb,uuid) to anon, authenticated;

-- set_order_vendor: رسم التوصيل حسب المحل (رسم خاص / مناطق / مسافة من موقع المحل)
create or replace function public.set_order_vendor(p_token text, p_vendor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders%rowtype; b public.restaurant_branches%rowtype; r public.restaurants%rowtype;
        v_del numeric(10,2); v_tot numeric(10,2); v_dl jsonb;
begin
  select * into o from public.orders where token = p_token;
  if not found then raise exception 'order not found'; end if;
  if o.branch_id is not null then return jsonb_build_object('ok', true); end if;
  if o.created_at < now() - interval '30 minutes' then raise exception 'too late'; end if;
  select * into r from public.restaurants where id = o.restaurant_id;
  if not coalesce(r.vendors_mode, false) then raise exception 'vendors mode off'; end if;
  select * into b from public.restaurant_branches where id = p_vendor and restaurant_id = o.restaurant_id and is_active;
  if not found then raise exception 'vendor not found'; end if;
  if exists (select 1 from public.order_items oi
               left join public.items i on i.id = oi.item_id
               left join public.categories c on c.id = i.category_id
               left join public.categories p on p.id = c.parent_id
             where oi.order_id = o.id and coalesce(c.vendor_id, p.vendor_id) is distinct from p_vendor) then
    raise exception 'items from another vendor';
  end if;
  v_del := o.delivery_usd;
  if o.order_type = 'delivery' then
    v_dl := public.calc_delivery(o.restaurant_id, p_vendor, o.zone_id, o.lat, o.lng);
    v_del := (v_dl->>'fee')::numeric;
  end if;
  v_tot := o.subtotal_usd + v_del;
  update public.orders set branch_id = p_vendor, branch_status = 'pending', branch_updated_at = now(),
         delivery_usd = v_del, total_usd = v_tot, distance_km = coalesce((v_dl->>'km')::numeric, distance_km),
         total_lbp = round(v_tot * o.exchange_rate / greatest(r.lbp_rounding,1)) * greatest(r.lbp_rounding,1)
   where id = o.id;
  return jsonb_build_object('ok', true, 'total_usd', v_tot, 'delivery_usd', v_del);
end $$;

-- ---------- 3) الشوفير: هل المحل فاتح لوحتو؟ + يبعتلو الطلب + موافقة عالتلفون ----------
create or replace function public.driver_vendor_info(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d public.drivers%rowtype; v jsonb;
begin
  if coalesce(p_token,'') = '' then return '{}'::jsonb; end if;
  select * into d from public.drivers where token = p_token and is_active;
  if not found then return '{}'::jsonb; end if;
  select coalesce(jsonb_object_agg(o.id::text, jsonb_build_object(
           'branch_status', o.branch_status,
           'reason', coalesce(nullif(o.rejection_reason,''), o.reject_reason, ''),
           'name_ar', b.name_ar, 'name_en', b.name_en, 'phone', b.phone, 'whatsapp', b.whatsapp,
           'address_ar', b.address_ar, 'lat', b.lat, 'lng', b.lng,
           'online', b.panel_seen_at is not null and b.panel_seen_at > now() - interval '60 seconds',
           'order_no', o.order_no, 'note', o.customer_note, 'subtotal_usd', o.subtotal_usd,
           'panel', (select l.token from public.vendor_links l where l.branch_id = b.id),
           'items', (select coalesce(jsonb_agg(jsonb_build_object('qty', oi.qty, 'name', oi.name_ar)), '[]'::jsonb)
                       from public.order_items oi where oi.order_id = o.id))), '{}'::jsonb)
    into v
    from public.orders o join public.restaurant_branches b on b.id = o.branch_id
   where o.restaurant_id = d.restaurant_id and o.created_at > now() - interval '36 hours';
  return v;
end $$;

-- الشوفير حكى المحل عالتلفون والمحل وافق
create or replace function public.driver_vendor_accept(p_token text, p_order bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d public.drivers%rowtype; o public.orders%rowtype;
begin
  select * into d from public.drivers where token = p_token and is_active;
  if not found then raise exception 'driver not found'; end if;
  select * into o from public.orders where id = p_order and restaurant_id = d.restaurant_id and branch_id is not null;
  if not found then raise exception 'order not found'; end if;
  if o.branch_status <> 'pending' then return jsonb_build_object('ok', false); end if;
  update public.orders set branch_status = 'accepted', branch_updated_at = now(),
         status = case when status = 'pending' then 'accepted' else status end,
         dispatch = case when order_type = 'delivery' and coalesce(dispatch,'') = '' then 'waiting' else dispatch end
   where id = o.id;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.driver_vendor_accept(text, bigint) to anon, authenticated;
