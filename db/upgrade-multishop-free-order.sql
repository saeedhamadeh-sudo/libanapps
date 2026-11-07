-- ============================================================
--  LibanApps — طلب واحد من أكثر من مطعم/محل + «طلب حر» + ترتيب الصفحة الرئيسية
--  آمن للتشغيل أكثر من مرة
-- ============================================================

-- ---------- 1) الجداول ----------
alter table public.order_items add column if not exists branch_id uuid references public.restaurant_branches(id) on delete set null;

create table if not exists public.order_vendors (
  order_id     bigint not null references public.orders(id) on delete cascade,
  branch_id    uuid   not null references public.restaurant_branches(id) on delete cascade,
  status       text   not null default 'pending' check (status in ('pending','accepted','rejected')),
  reason       text   not null default '',
  subtotal_usd numeric(10,2) not null default 0,
  updated_at   timestamptz,
  primary key (order_id, branch_id)
);
create index if not exists order_vendors_branch_idx on public.order_vendors (branch_id);
alter table public.order_vendors enable row level security;
drop policy if exists "order_vendors_member" on public.order_vendors;
create policy "order_vendors_member" on public.order_vendors
  for all using (exists (select 1 from public.orders o where o.id = order_vendors.order_id and public.is_member(o.restaurant_id)))
  with check (exists (select 1 from public.orders o where o.id = order_vendors.order_id and public.is_member(o.restaurant_id)));

alter table public.orders add column if not exists free_text text not null default '';

alter table public.restaurants
  add column if not exists home_layout jsonb not null default '{}'::jsonb,       -- {"order":["مطاعم","__free",...],"icons":{"مطاعم":"🍽️"}}
  add column if not exists free_order_enabled boolean not null default false,
  add column if not exists free_order_title_ar text not null default 'طلب حر',
  add column if not exists free_order_title_en text not null default 'Anything you need',
  add column if not exists free_order_fee_usd numeric(8,2),                        -- فاضي = رسم التوصيل العادي
  add column if not exists dlv_extra_vendor_usd numeric(8,2) not null default 0;   -- لكل محل زيادة بالطلب

-- الطلبات القديمة (محل واحد) → order_vendors
insert into public.order_vendors (order_id, branch_id, status, reason, subtotal_usd, updated_at)
select o.id, o.branch_id, o.branch_status, coalesce(nullif(o.rejection_reason,''), o.reject_reason, ''), o.subtotal_usd, o.branch_updated_at
  from public.orders o where o.branch_id is not null
on conflict do nothing;
update public.order_items oi set branch_id = o.branch_id
  from public.orders o where o.id = oi.order_id and o.branch_id is not null and oi.branch_id is null;

-- ---------- 2) حالة الطلب الكلّية من حالات المحلات ----------
create or replace function public._sync_order_vendors(p_order bigint)
returns void language plpgsql security definer set search_path = public as $$
declare n int; n_pend int; n_acc int; n_rej int; o public.orders%rowtype; v_sub numeric(10,2); v_tot numeric(10,2);
        v_round numeric; v_first uuid;
begin
  select * into o from public.orders where id = p_order;
  if not found then return; end if;
  select count(*), count(*) filter (where status='pending'), count(*) filter (where status='accepted'),
         count(*) filter (where status='rejected')
    into n, n_pend, n_acc, n_rej from public.order_vendors where order_id = p_order;
  if n = 0 then return; end if;

  -- المجموع من غير أصناف المحلات اللي رفضت
  select coalesce(sum(oi.line_usd),0) into v_sub from public.order_items oi
   where oi.order_id = p_order
     and (oi.branch_id is null or oi.branch_id not in (select branch_id from public.order_vendors where order_id = p_order and status = 'rejected'));
  select greatest(lbp_rounding,1) into v_round from public.restaurants where id = o.restaurant_id;
  v_tot := v_sub + o.delivery_usd;

  update public.orders set
    branch_status = case when n_rej = n then 'rejected' when n_pend > 0 then 'pending' else 'accepted' end,
    branch_updated_at = now(),
    subtotal_usd = v_sub,
    total_usd = v_tot,
    total_lbp = round(v_tot * exchange_rate / v_round) * v_round,
    status = case when n_rej = n and status in ('pending','accepted') then 'rejected'
                  when n_pend = 0 and n_acc > 0 and status = 'pending' then 'accepted' else status end,
    rejection_reason = case when n_rej = n then (select string_agg(reason, ' · ') from public.order_vendors where order_id = p_order and reason <> '') else rejection_reason end,
    dispatch = case when n_rej = n and order_type = 'delivery' and coalesce(dispatch,'') not in ('on_the_way','delivered') then 'cancelled'
                    when n_pend = 0 and n_acc > 0 and order_type = 'delivery' and coalesce(dispatch,'') = '' then 'waiting'
                    else dispatch end
   where id = p_order;
end $$;
revoke execute on function public._sync_order_vendors(bigint) from public, anon, authenticated;

-- ---------- 3) place_order: + طلب حر + أكثر من محل ----------
drop function if exists public.place_order(text,text,text,text,text,text,double precision,double precision,text,text,jsonb,uuid);
create or replace function public.place_order(
  p_slug text, p_type text, p_name text, p_phone text, p_table text,
  p_address text, p_lat double precision, p_lng double precision,
  p_note text, p_payment text, p_lines jsonb, p_zone uuid default null, p_free_text text default null
) returns table (order_id bigint, order_no text, token text, total_usd numeric, total_lbp numeric)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  r public.restaurants%rowtype;
  v_sub numeric(10,2) := 0; v_del numeric(10,2) := 0;
  v_tot numeric(10,2); v_lbp numeric(14,0);
  v_no text; v_id bigint; v_tok text;
  ln jsonb; it public.items%rowtype; v_qty integer;
  v_builder jsonb; g jsonb; v_sel jsonb;
  v_unit numeric(10,2); v_opts jsonb; v_lab_ar text; v_lab_en text;
  v_cnt integer; v_add numeric(10,2); v_gar text; v_gen text; v_gjs jsonb; v_bad integer;
  v_dl jsonb; v_vendor uuid; v_free boolean; v_nv int := 0; v_vb record; v_max numeric := null; v_km numeric := null;
begin
  select * into r from public.restaurants where slug = p_slug;
  if not found or not public.menu_live(r.id) then raise exception 'restaurant unavailable'; end if;
  v_free := coalesce(trim(p_free_text),'') <> '';
  if v_free then
    if not r.free_order_enabled then raise exception 'free order disabled'; end if;
    if p_type <> 'delivery' then raise exception 'free order is delivery only'; end if;
    if length(trim(p_free_text)) > 2000 then raise exception 'free order too long'; end if;
  end if;
  if p_type = 'dine_in'  and not r.dinein_enabled   then raise exception 'dine-in disabled'; end if;
  if p_type = 'delivery' and not r.delivery_enabled then raise exception 'delivery disabled'; end if;
  if length(trim(p_name)) < 2 or length(regexp_replace(p_phone,'\D','','g')) < 7 then
    raise exception 'invalid customer details'; end if;
  if p_type = 'delivery' and r.require_location and (p_lat is null or p_lng is null) then
    raise exception 'location required'; end if;
  if not v_free and (jsonb_array_length(coalesce(p_lines,'[]'::jsonb)) = 0) then raise exception 'invalid cart'; end if;
  if jsonb_array_length(coalesce(p_lines,'[]'::jsonb)) > 60 then raise exception 'invalid cart'; end if;
  if p_type = 'delivery' and r.delivery_pricing = 'zones' then
    perform public.calc_delivery(r.id, null, p_zone, p_lat, p_lng);   -- بيرفض إذا ما في منطقة
  end if;

  r.order_seq := r.order_seq + 1;
  update public.restaurants set order_seq = r.order_seq where id = r.id;
  v_no := upper(left(r.slug, 2)) || '-' || (1000 + r.order_seq);

  insert into public.orders (restaurant_id, order_no, order_type, customer_name, customer_phone,
                             table_no, address_text, lat, lng, customer_note,
                             subtotal_usd, delivery_usd, total_usd, exchange_rate, total_lbp,
                             payment_method, status, zone_id, free_text)
  values (r.id, v_no, p_type, trim(p_name), trim(p_phone),
          coalesce(p_table,''), coalesce(p_address,''), p_lat, p_lng, coalesce(p_note,''),
          0, 0, 0, r.exchange_rate, 0, case when v_free then 'cash' else p_payment end,
          case when p_payment = 'whish' and not v_free then 'awaiting_payment' else 'pending' end,
          case when p_type = 'delivery' then p_zone end, case when v_free then trim(p_free_text) else '' end)
  returning orders.id, orders.token into v_id, v_tok;

  for ln in select * from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) loop
    v_qty := greatest(1, least(50, (ln->>'qty')::int));
    select * into it from public.items
      where id = (ln->>'item_id')::uuid and restaurant_id = r.id and is_available;
    if not found then continue; end if;

    v_unit := it.price_usd; v_opts := null; v_lab_ar := ''; v_lab_en := '';
    select c.builder, coalesce(c.vendor_id, p.vendor_id) into v_builder, v_vendor
      from public.categories c left join public.categories p on p.id = c.parent_id where c.id = it.category_id;
    if not coalesce(r.vendors_mode,false) then v_vendor := null; end if;

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

    insert into public.order_items (order_id, item_id, name_ar, name_en, price_usd, qty, line_usd, options, branch_id)
    values (v_id, it.id,
            it.name_ar || case when v_lab_ar <> '' then ' — ' || v_lab_ar else '' end,
            it.name_en || case when v_lab_en <> '' then ' — ' || v_lab_en else '' end,
            v_unit, v_qty, v_unit * v_qty, v_opts, v_vendor);
    v_sub := v_sub + v_unit * v_qty;
  end loop;

  if v_sub = 0 and not v_free then raise exception 'empty cart'; end if;

  -- المحلات بالطلب
  insert into public.order_vendors (order_id, branch_id, subtotal_usd)
  select v_id, oi.branch_id, sum(oi.line_usd) from public.order_items oi
   where oi.order_id = v_id and oi.branch_id is not null group by oi.branch_id;
  get diagnostics v_nv = row_count;

  if p_type = 'delivery' then
    if v_sub < r.min_order_usd and not v_free then raise exception 'below minimum order'; end if;
    if v_free and r.free_order_fee_usd is not null then
      v_del := r.free_order_fee_usd;
    elsif v_nv > 0 then
      -- أكثر من محل: أعلى رسم بين المحلات + رسم إضافي لكل محل زيادة
      for v_vb in select branch_id from public.order_vendors where order_id = v_id loop
        v_dl := public.calc_delivery(r.id, v_vb.branch_id, p_zone, p_lat, p_lng);
        if v_max is null or (v_dl->>'fee')::numeric > v_max then
          v_max := (v_dl->>'fee')::numeric; v_km := (v_dl->>'km')::numeric; end if;
      end loop;
      v_del := coalesce(v_max,0) + r.dlv_extra_vendor_usd * greatest(v_nv - 1, 0);
    else
      v_dl := public.calc_delivery(r.id, null, p_zone, p_lat, p_lng);
      v_del := (v_dl->>'fee')::numeric; v_km := (v_dl->>'km')::numeric;
    end if;
  end if;

  v_tot := v_sub + v_del;
  v_lbp := round(v_tot * r.exchange_rate / r.lbp_rounding) * r.lbp_rounding;
  update public.orders set subtotal_usd = v_sub, delivery_usd = v_del, total_usd = v_tot, total_lbp = v_lbp,
         distance_km = v_km,
         branch_id = (select branch_id from public.order_vendors where order_id = v_id order by subtotal_usd desc limit 1),
         branch_status = 'pending', branch_updated_at = now()
   where id = v_id;

  return query select v_id, v_no, v_tok, v_tot, v_lbp;
end $$;
grant execute on function public.place_order(text,text,text,text,text,text,double precision,double precision,text,text,jsonb,uuid,text) to anon, authenticated;

-- القديمة: الطلب صار مربوط بمحلاتو من place_order
create or replace function public.set_order_vendor(p_token text, p_vendor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders%rowtype;
begin
  select * into o from public.orders where token = p_token;
  if not found then raise exception 'order not found'; end if;
  return jsonb_build_object('ok', true, 'total_usd', o.total_usd, 'delivery_usd', o.delivery_usd);
end $$;

-- ---------- 4) لوحة المحل: الطلبات اللي إلو فيها أصناف ----------
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
      'subtotal_usd', ov.subtotal_usd, 'payment_method', o.payment_method,
      'status', o.status, 'branch_status', ov.status, 'dispatch', coalesce(o.dispatch,''),
      'reason', ov.reason, 'created_at', o.created_at,
      'others', (select count(*) from public.order_vendors x where x.order_id = o.id and x.branch_id <> v_bid),
      'driver', (select jsonb_build_object('name', d.name, 'phone', d.phone) from public.drivers d where d.id = o.driver_id),
      'items', (select coalesce(jsonb_agg(jsonb_build_object('name_ar', oi.name_ar, 'name_en', oi.name_en, 'qty', oi.qty, 'line_usd', oi.line_usd)), '[]'::jsonb)
                from public.order_items oi where oi.order_id = o.id and oi.branch_id = v_bid)
    ) as x
    from public.order_vendors ov join public.orders o on o.id = ov.order_id
    where ov.branch_id = v_bid and o.created_at > now() - interval '36 hours' and o.status <> 'awaiting_payment'
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

create or replace function public.vendor_respond(p_token text, p_order bigint, p_accept boolean, p_reason text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_bid uuid; ov public.order_vendors%rowtype;
begin
  select branch_id into v_bid from public.vendor_links where token = p_token;
  if v_bid is null then raise exception 'invalid link'; end if;
  select * into ov from public.order_vendors where order_id = p_order and branch_id = v_bid;
  if not found then raise exception 'order not found'; end if;
  if ov.status <> 'pending' then return jsonb_build_object('ok', false, 'error', 'already answered'); end if;
  update public.order_vendors set status = case when p_accept then 'accepted' else 'rejected' end,
         reason = case when p_accept then '' else coalesce(p_reason,'') end, updated_at = now()
   where order_id = p_order and branch_id = v_bid;
  perform public._sync_order_vendors(p_order);
  return jsonb_build_object('ok', true);
end $$;

-- ---------- 5) الشوفير: كل محلات الطلب + الطلب الحر ----------
create or replace function public.driver_vendor_info(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d public.drivers%rowtype; v jsonb;
begin
  if coalesce(p_token,'') = '' then return '{}'::jsonb; end if;
  select * into d from public.drivers where token = p_token and is_active;
  if not found then return '{}'::jsonb; end if;
  select coalesce(jsonb_object_agg(o.id::text, jsonb_build_object(
           'order_no', o.order_no, 'note', o.customer_note, 'free_text', o.free_text,
           'vendors', (select coalesce(jsonb_agg(jsonb_build_object(
                'branch_id', b.id, 'status', ov.status, 'reason', ov.reason, 'subtotal_usd', ov.subtotal_usd,
                'name_ar', b.name_ar, 'phone', b.phone, 'whatsapp', b.whatsapp, 'address_ar', b.address_ar,
                'lat', b.lat, 'lng', b.lng,
                'online', b.panel_seen_at is not null and b.panel_seen_at > now() - interval '60 seconds',
                'panel', (select l.token from public.vendor_links l where l.branch_id = b.id),
                'items', (select coalesce(jsonb_agg(jsonb_build_object('qty', oi.qty, 'name', oi.name_ar)), '[]'::jsonb)
                            from public.order_items oi where oi.order_id = o.id and oi.branch_id = b.id))
              order by b.sort), '[]'::jsonb)
              from public.order_vendors ov join public.restaurant_branches b on b.id = ov.branch_id where ov.order_id = o.id))), '{}'::jsonb)
    into v
    from public.orders o
   where o.restaurant_id = d.restaurant_id and o.created_at > now() - interval '36 hours'
     and (o.free_text <> '' or exists (select 1 from public.order_vendors ov where ov.order_id = o.id));
  return v;
end $$;

drop function if exists public.driver_vendor_accept(text, bigint);
create or replace function public.driver_vendor_accept(p_token text, p_order bigint, p_branch uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d public.drivers%rowtype;
begin
  select * into d from public.drivers where token = p_token and is_active;
  if not found then raise exception 'driver not found'; end if;
  if not exists (select 1 from public.orders where id = p_order and restaurant_id = d.restaurant_id) then
    raise exception 'order not found'; end if;
  update public.order_vendors set status = 'accepted', updated_at = now()
   where order_id = p_order and status = 'pending' and (p_branch is null or branch_id = p_branch);
  perform public._sync_order_vendors(p_order);
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.driver_vendor_accept(text, bigint, uuid) to anon, authenticated;

-- ---------- 6) تتبع الزبون والفاتورة ----------
create or replace function public.order_vendor_info(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders%rowtype; v_mode boolean;
begin
  select * into o from public.orders where token = p_token;
  if not found then return null; end if;
  select coalesce(vendors_mode,false) into v_mode from public.restaurants where id = o.restaurant_id;
  return jsonb_build_object(
    'vendors_mode', v_mode, 'status', o.status, 'branch_status', o.branch_status,
    'free', o.free_text <> '',
    'has_vendor', exists (select 1 from public.order_vendors where order_id = o.id),
    'reason', coalesce(nullif(o.rejection_reason,''), o.reject_reason, ''),
    'vendors', (select coalesce(jsonb_agg(jsonb_build_object('name_ar', b.name_ar, 'name_en', b.name_en,
                   'status', ov.status, 'reason', ov.reason, 'phone', b.phone) order by b.sort), '[]'::jsonb)
                from public.order_vendors ov join public.restaurant_branches b on b.id = ov.branch_id where ov.order_id = o.id),
    'vendor', (select jsonb_build_object('name_ar', b.name_ar, 'name_en', b.name_en, 'phone', b.phone,
                   'address_ar', b.address_ar, 'address_en', b.address_en)
               from public.restaurant_branches b where b.id = o.branch_id));
end $$;

create or replace function public.get_order(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders%rowtype; r public.restaurants%rowtype;
begin
  select * into o from public.orders where token = p_token;
  if not found then raise exception 'not found'; end if;
  select * into r from public.restaurants where id = o.restaurant_id;
  return jsonb_build_object(
    'order', to_jsonb(o) - 'restaurant_id',
    'restaurant', jsonb_build_object('name_ar',r.name_ar,'name_en',r.name_en,'logo_url',r.logo_url,
                                     'phone',r.phone,'slug',r.slug,'theme',r.theme,
                                     'default_lang',r.default_lang,
                                     'base_currency',r.base_currency,
                                     'exchange_rate',r.exchange_rate),
    'items', coalesce((select jsonb_agg(to_jsonb(oi) - 'order_id' - 'id')
                       from public.order_items oi where oi.order_id = o.id), '[]'::jsonb),
    'vendors', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name_ar', b.name_ar, 'name_en', b.name_en,
                       'status', ov.status, 'subtotal_usd', ov.subtotal_usd) order by b.sort)
                       from public.order_vendors ov join public.restaurant_branches b on b.id = ov.branch_id
                       where ov.order_id = o.id), '[]'::jsonb)
  );
end $$;
