-- ============================================================
--  LibanApps — وضع «أسماء المطاعم / المحلات» (منيو شركات التوصيل)
--  ------------------------------------------------------------
--  بيتفعّل من لوحة السوبر لمنيو معيّن. بس يتفعّل:
--    • «الفروع» بتصير «المطاعم / المحلات» — كل واحد إلو منيو (أقسام) خاص فيه
--    • الزبون بيختار المطعم/المحل وبيطلب منه
--    • كل مطعم/محل إلو رابط لوحة خاص فيه (/v/<token>) بيوصلو الطلب
--      ليوافق أو يرفض ويجهّزو للشوفير
--    • الشوفير والزبون بيشوفوا إذا المطعم وافق أو لا
--  شغّله مرة وحدة على Supabase SQL Editor — آمن للتشغيل أكثر من مرة
-- ============================================================

-- 1) مفتاح الوضع على المطعم (بيتحكم فيه السوبر)
alter table public.restaurants
  add column if not exists vendors_mode boolean not null default false;

-- 2) كل قسم بينتمي لمطعم/محل معيّن (بوضع المحلات فقط)
alter table public.categories
  add column if not exists vendor_id uuid references public.restaurant_branches(id) on delete set null;
create index if not exists categories_vendor_idx on public.categories (vendor_id);

-- 3) أعمدة الطلب (موجودة من upgrade-branches — منتأكد)
alter table public.orders
  add column if not exists branch_id uuid references public.restaurant_branches(id) on delete set null;
alter table public.orders
  add column if not exists branch_status text not null default 'pending';
alter table public.orders
  add column if not exists rejection_reason text default '';
alter table public.orders
  add column if not exists branch_updated_at timestamptz;
alter table public.orders
  add column if not exists reject_reason text default '';
create index if not exists orders_branch_idx on public.orders (branch_id, created_at desc);

-- 4) رابط لوحة كل مطعم/محل — بجدول منفصل لأن restaurant_branches مقروء للعموم
create table if not exists public.vendor_links (
  branch_id  uuid primary key references public.restaurant_branches(id) on delete cascade,
  token      text not null unique default replace(gen_random_uuid()::text,'-',''),
  created_at timestamptz not null default now()
);
alter table public.vendor_links enable row level security;
drop policy if exists "vendor_links_member" on public.vendor_links;
create policy "vendor_links_member" on public.vendor_links
  for all using (
    exists (select 1 from public.restaurant_branches b
            where b.id = vendor_links.branch_id and public.is_member(b.restaurant_id)))
  with check (
    exists (select 1 from public.restaurant_branches b
            where b.id = vendor_links.branch_id and public.is_member(b.restaurant_id)));

-- صاحب المنيو بيجيب الرابط (أو بيولّد واحد جديد)
create or replace function public.vendor_link(p_branch uuid, p_new boolean default false)
returns text language plpgsql security definer set search_path = public as $$
declare v_rid uuid; v_tok text;
begin
  select restaurant_id into v_rid from public.restaurant_branches where id = p_branch;
  if v_rid is null or not public.is_member(v_rid) then raise exception 'not allowed'; end if;
  if p_new then delete from public.vendor_links where branch_id = p_branch; end if;
  insert into public.vendor_links (branch_id) values (p_branch) on conflict (branch_id) do nothing;
  select token into v_tok from public.vendor_links where branch_id = p_branch;
  return v_tok;
end $$;
grant execute on function public.vendor_link(uuid, boolean) to authenticated;

-- 5) ربط الطلب بالمطعم/المحل بعد place_order (بالـtoken تبع الطلب)
--    + رسوم التوصيل من المحل إذا محددة
create or replace function public.set_order_vendor(p_token text, p_vendor uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders%rowtype; b public.restaurant_branches%rowtype; r public.restaurants%rowtype;
        v_del numeric(10,2); v_tot numeric(10,2);
begin
  select * into o from public.orders where token = p_token;
  if not found then raise exception 'order not found'; end if;
  if o.branch_id is not null then return jsonb_build_object('ok', true); end if;
  if o.created_at < now() - interval '30 minutes' then raise exception 'too late'; end if;
  select * into r from public.restaurants where id = o.restaurant_id;
  if not coalesce(r.vendors_mode, false) then raise exception 'vendors mode off'; end if;
  select * into b from public.restaurant_branches
    where id = p_vendor and restaurant_id = o.restaurant_id and is_active;
  if not found then raise exception 'vendor not found'; end if;
  -- كل الأصناف لازم تكون من نفس المحل
  if exists (select 1 from public.order_items oi
               left join public.items i on i.id = oi.item_id
               left join public.categories c on c.id = i.category_id
             where oi.order_id = o.id and c.vendor_id is distinct from p_vendor) then
    raise exception 'items from another vendor';
  end if;

  v_del := o.delivery_usd;
  if o.order_type = 'delivery' and b.delivery_enabled then v_del := b.delivery_fee_usd; end if;
  v_tot := o.subtotal_usd + v_del;

  update public.orders set branch_id = p_vendor, branch_status = 'pending', branch_updated_at = now(),
         delivery_usd = v_del, total_usd = v_tot,
         total_lbp = round(v_tot * o.exchange_rate / greatest(r.lbp_rounding,1)) * greatest(r.lbp_rounding,1)
   where id = o.id;
  return jsonb_build_object('ok', true, 'total_usd', v_tot, 'delivery_usd', v_del);
end $$;
grant execute on function public.set_order_vendor(text, uuid) to anon, authenticated;

-- 6) لوحة المطعم/المحل — /v/<token>
create or replace function public.vendor_panel(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_bid uuid; b public.restaurant_branches%rowtype; r public.restaurants%rowtype; v_orders jsonb;
begin
  select branch_id into v_bid from public.vendor_links where token = p_token;
  if v_bid is null then raise exception 'invalid link'; end if;
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
      'driver', (select jsonb_build_object('name', d.name, 'phone', d.phone)
                   from public.drivers d where d.id = o.driver_id),
      'items', (select coalesce(jsonb_agg(jsonb_build_object(
                  'name_ar', oi.name_ar, 'name_en', oi.name_en, 'qty', oi.qty, 'line_usd', oi.line_usd)), '[]'::jsonb)
                from public.order_items oi where oi.order_id = o.id)
    ) as x
    from public.orders o
    where o.branch_id = v_bid and o.created_at > now() - interval '36 hours'
      and o.status <> 'awaiting_payment'
    order by o.created_at desc limit 80
  ) s;

  return jsonb_build_object(
    'vendor', jsonb_build_object('name_ar', b.name_ar, 'name_en', b.name_en, 'image_url', b.image_url,
                                 'force_closed', b.force_closed, 'is_active', b.is_active),
    'company', jsonb_build_object('name_ar', r.name_ar, 'name_en', r.name_en, 'logo_url', r.logo_url,
                                  'phone', r.phone, 'whatsapp', r.whatsapp, 'theme', r.theme),
    'orders', v_orders);
end $$;
grant execute on function public.vendor_panel(text) to anon, authenticated;

create or replace function public.vendor_respond(p_token text, p_order bigint, p_accept boolean, p_reason text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_bid uuid; o public.orders%rowtype;
begin
  select branch_id into v_bid from public.vendor_links where token = p_token;
  if v_bid is null then raise exception 'invalid link'; end if;
  select * into o from public.orders where id = p_order and branch_id = v_bid;
  if not found then raise exception 'order not found'; end if;
  if o.branch_status <> 'pending' then return jsonb_build_object('ok', false, 'error', 'already answered'); end if;

  if p_accept then
    update public.orders set branch_status = 'accepted', branch_updated_at = now(),
           status = case when status = 'pending' then 'accepted' else status end,
           dispatch = case when order_type = 'delivery' and coalesce(dispatch,'') = '' then 'waiting' else dispatch end
     where id = o.id;
  else
    update public.orders set branch_status = 'rejected', branch_updated_at = now(),
           rejection_reason = coalesce(p_reason,''), reject_reason = coalesce(p_reason,''),
           status = case when status in ('pending','accepted') then 'rejected' else status end,
           dispatch = case when coalesce(dispatch,'') in ('on_the_way','delivered') then dispatch
                           when order_type = 'delivery' then 'cancelled' else dispatch end
     where id = o.id;
  end if;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.vendor_respond(text, bigint, boolean, text) to anon, authenticated;

create or replace function public.vendor_set_closed(p_token text, p_closed boolean, p_msg text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_bid uuid;
begin
  select branch_id into v_bid from public.vendor_links where token = p_token;
  if v_bid is null then raise exception 'invalid link'; end if;
  update public.restaurant_branches
     set force_closed = p_closed, force_closed_msg_ar = case when p_closed then coalesce(p_msg,'') else '' end
   where id = v_bid;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.vendor_set_closed(text, boolean, text) to anon, authenticated;

-- 7) صفحة تتبع الزبون — حالة موافقة المطعم
create or replace function public.order_vendor_info(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders%rowtype; b public.restaurant_branches%rowtype; v_mode boolean;
begin
  select * into o from public.orders where token = p_token;
  if not found then return null; end if;
  select coalesce(vendors_mode,false) into v_mode from public.restaurants where id = o.restaurant_id;
  if o.branch_id is not null then select * into b from public.restaurant_branches where id = o.branch_id; end if;
  return jsonb_build_object(
    'vendors_mode', v_mode, 'status', o.status, 'branch_status', o.branch_status,
    'has_vendor', o.branch_id is not null,
    'reason', coalesce(nullif(o.rejection_reason,''), o.reject_reason, ''),
    'vendor', case when o.branch_id is null then null else jsonb_build_object(
       'name_ar', b.name_ar, 'name_en', b.name_en, 'phone', b.phone,
       'address_ar', b.address_ar, 'address_en', b.address_en) end);
end $$;
grant execute on function public.order_vendor_info(text) to anon, authenticated;

-- 8) صفحة الشوفير — لكل طلب: أي مطعم/محل وهل وافق
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
           'name_ar', b.name_ar, 'name_en', b.name_en, 'phone', b.phone,
           'address_ar', b.address_ar)), '{}'::jsonb)
    into v
    from public.orders o join public.restaurant_branches b on b.id = o.branch_id
   where o.restaurant_id = d.restaurant_id and o.created_at > now() - interval '36 hours';
  return v;
end $$;
grant execute on function public.driver_vendor_info(text) to anon, authenticated;

-- تحقق
select 'vendors_mode' as item, exists(select 1 from information_schema.columns
  where table_name='restaurants' and column_name='vendors_mode') as ok
union all select 'categories.vendor_id', exists(select 1 from information_schema.columns
  where table_name='categories' and column_name='vendor_id')
union all select 'vendor_panel', exists(select 1 from pg_proc where proname='vendor_panel')
union all select 'driver_vendor_info', exists(select 1 from pg_proc where proname='driver_vendor_info');
