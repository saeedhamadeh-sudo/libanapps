-- ============================================================
--  security-fixes-3.sql — مراجعة أمنية (2026-11-15)
--  1) صفحة طلبات الموظف (/orders.html): كانت كل الدوال بتشتغل بالـslug بس،
--     يعني أي حدا بيعرف رابط المطعم بيقدر يشوف أرقام الزباين ويقبل/يرفض/يمسح الطلبات.
--     هلق لازم مفتاح سري لكل مطعم (staff_key) بالرابط: /orders.html?r=<slug>&k=<key>
--  2) redeem_coupon: كان أي زائر يقدر يزيد عدّاد استعمال أي كوبون لحد ما يخلص.
--  آمن تشغيله أكتر من مرة.
-- ============================================================

-- المفاتيح بجدول منفصل (مش بجدول restaurants لأنو مقروء للعامة بسبب المنيو)
create table if not exists public.restaurant_staff_keys (
  restaurant_id uuid primary key references public.restaurants(id) on delete cascade,
  staff_key     text not null default encode(extensions.gen_random_bytes(24), 'hex'),
  created_at    timestamptz not null default now()
);
alter table public.restaurant_staff_keys enable row level security;   -- بلا policies: بس الدوال بتقرأه
revoke all on public.restaurant_staff_keys from anon, authenticated;

insert into public.restaurant_staff_keys (restaurant_id)
select id from public.restaurants on conflict do nothing;

-- مطعم جديد ← مفتاح تلقائي
create or replace function public._rest_staff_key_new() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.restaurant_staff_keys (restaurant_id) values (new.id) on conflict do nothing;
  return new;
end $$;
revoke execute on function public._rest_staff_key_new() from public, anon, authenticated;
drop trigger if exists trg_rest_staff_key on public.restaurants;
create trigger trg_rest_staff_key after insert on public.restaurants
  for each row execute function public._rest_staff_key_new();

-- التحقق: الـslug + المفتاح لازم يتطابقوا
create or replace function public._staff_rid(p_slug text, p_key text) returns uuid
language sql stable security definer set search_path = public as $$
  select r.id from public.restaurants r
  join public.restaurant_staff_keys k on k.restaurant_id = r.id
  where r.slug = p_slug and length(coalesce(p_key,'')) >= 32 and k.staff_key = p_key
$$;
revoke execute on function public._staff_rid(text, text) from public, anon, authenticated;

-- صاحب المطعم (أو موظف مربوط) بيجيب المفتاح لرابط الموظف — وبيقدر يجدّدو (بيبطّل الرابط القديم)
create or replace function public.staff_orders_key(rid uuid, p_rotate boolean default false) returns text
language plpgsql security definer set search_path = public as $$
declare k text;
begin
  if not (public.is_member(rid) or public.is_admin()) then raise exception 'not allowed'; end if;
  insert into public.restaurant_staff_keys (restaurant_id) values (rid) on conflict do nothing;
  if p_rotate then
    update public.restaurant_staff_keys set staff_key = encode(extensions.gen_random_bytes(24), 'hex'), created_at = now() where restaurant_id = rid;
  end if;
  select staff_key into k from public.restaurant_staff_keys where restaurant_id = rid;
  return k;
end $$;
revoke execute on function public.staff_orders_key(uuid, boolean) from public, anon;
grant execute on function public.staff_orders_key(uuid, boolean) to authenticated;

-- الدوال القديمة (بالـslug بس) بتنشال
drop function if exists public.staff_get_orders(text);
drop function if exists public.staff_accept_order(text, bigint);
drop function if exists public.staff_reject_order(text, bigint, text);
drop function if exists public.staff_clear_orders(text);

create or replace function public.staff_get_orders(p_slug text, p_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare rid uuid; rows jsonb;
begin
  rid := public._staff_rid(p_slug, p_key);
  if rid is null then raise exception 'STAFF:bad_key'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', o.id, 'order_no', o.order_no, 'customer_name', o.customer_name, 'customer_phone', o.customer_phone,
    'order_type', o.order_type, 'total_usd', o.total_usd, 'status', o.status, 'created_at', o.created_at
  ) order by o.created_at desc), '[]'::jsonb) into rows
  from public.orders o
  where o.restaurant_id = rid and o.created_at > now() - interval '24 hours'
    and o.status in ('pending','accepted','rejected');
  return rows;
end $$;

create or replace function public.staff_accept_order(p_slug text, p_key text, p_order_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare rid uuid; otype text;
begin
  rid := public._staff_rid(p_slug, p_key);
  if rid is null then raise exception 'STAFF:bad_key'; end if;
  select order_type into otype from public.orders where id = p_order_id and restaurant_id = rid and status = 'pending';
  if not found then return '{"ok":false,"error":"order not found or not pending"}'::jsonb; end if;
  if otype = 'delivery' then
    update public.orders set status = 'accepted', dispatch = 'waiting' where id = p_order_id and restaurant_id = rid;
  else
    update public.orders set status = 'accepted' where id = p_order_id and restaurant_id = rid;
  end if;
  return '{"ok":true}'::jsonb;
end $$;

create or replace function public.staff_reject_order(p_slug text, p_key text, p_order_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare rid uuid;
begin
  rid := public._staff_rid(p_slug, p_key);
  if rid is null then raise exception 'STAFF:bad_key'; end if;
  update public.orders set status = 'rejected', reject_reason = left(coalesce(p_reason,''), 300)
  where id = p_order_id and restaurant_id = rid and status = 'pending';
  if not found then return '{"ok":false,"error":"order not found or not pending"}'::jsonb; end if;
  return '{"ok":true}'::jsonb;
end $$;

create or replace function public.staff_clear_orders(p_slug text, p_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare rid uuid; n integer;
begin
  rid := public._staff_rid(p_slug, p_key);
  if rid is null then raise exception 'STAFF:bad_key'; end if;
  delete from public.orders where restaurant_id = rid and status in ('accepted','rejected','cancelled');
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'deleted', n);
end $$;

grant execute on function public.staff_get_orders(text, text)                 to anon, authenticated;
grant execute on function public.staff_accept_order(text, text, bigint)       to anon, authenticated;
grant execute on function public.staff_reject_order(text, text, bigint, text) to anon, authenticated;
grant execute on function public.staff_clear_orders(text, text)               to anon, authenticated;

-- 2) الكوبونات: الاستهلاك بيصير بس من جوّا place_order (security definer) — مش من المتصفح
revoke execute on function public.redeem_coupon(uuid) from public, anon, authenticated;
