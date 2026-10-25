-- ============================================================
--  LibanApps — نظام التوصيل الكامل
--  شغّله مرة وحدة على Supabase SQL Editor
--  آمن للتشغيل أكثر من مرة (if not exists / or replace)
-- ============================================================

-- ============================================================
-- 1) جدول السائقين / موظفي التوصيل
-- ============================================================
create table if not exists public.drivers (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  name          text not null,
  phone         text default '',
  token         text default '',          -- رابط تسجيل الدخول
  is_active     boolean not null default true,
  on_duty       boolean not null default false,
  done_today    integer not null default 0,
  allowed       boolean not null default true,  -- ضمن حصة الاشتراك
  created_at    timestamptz not null default now()
);
create index if not exists drivers_rest_idx on public.drivers (restaurant_id);

-- ============================================================
-- 2) جدول أجهزة التتبع
-- ============================================================
create table if not exists public.tracker_devices (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  driver_id     uuid references public.drivers(id) on delete set null,
  kind          text not null default 'gps_tracker',
  label         text default '',
  identifier    text default '',    -- IMEI أو ID
  lat           double precision,
  lng           double precision,
  speed         double precision,
  battery       double precision,
  pos_at        timestamptz,
  src           text default 'gps_tracker',
  created_at    timestamptz not null default now(),
  unique (restaurant_id, identifier)
);
create index if not exists tdev_rest_idx on public.tracker_devices (restaurant_id);

-- ============================================================
-- 3) إضافة حقول التوصيل على جدول orders
-- ============================================================
alter table public.orders
  add column if not exists dispatch text default ''
  check (dispatch in ('','waiting','claimed','ready_wait','on_the_way','delivered','cancelled'));
alter table public.orders
  add column if not exists driver_id uuid references public.drivers(id) on delete set null;
alter table public.orders
  add column if not exists lat double precision;
alter table public.orders
  add column if not exists lng double precision;

-- ============================================================
-- 4) إعدادات التوصيل (جزء من جدول restaurants)
-- ============================================================
alter table public.restaurants
  add column if not exists delivery_mode text not null default 'manual';
alter table public.restaurants
  add column if not exists delivery_api_key text default '';
alter table public.restaurants
  add column if not exists delivery_active boolean not null default false;
alter table public.restaurants
  add column if not exists delivery_capacity integer not null default 3;
alter table public.restaurants
  add column if not exists delivery_expires_at timestamptz;

-- ============================================================
-- 5) RLS — السائقين
-- ============================================================
alter table public.drivers enable row level security;
drop policy if exists "drivers_read"  on public.drivers;
drop policy if exists "drivers_write" on public.drivers;
create policy "drivers_read" on public.drivers
  for select using (public.is_member(restaurant_id) or true);
create policy "drivers_write" on public.drivers
  for all using (public.is_member(restaurant_id))
  with check (public.is_member(restaurant_id));

-- أجهزة التتبع
alter table public.tracker_devices enable row level security;
drop policy if exists "tdev_read"  on public.tracker_devices;
drop policy if exists "tdev_write" on public.tracker_devices;
create policy "tdev_read"  on public.tracker_devices for select using (true);
create policy "tdev_write" on public.tracker_devices
  for all using (public.is_member(restaurant_id))
  with check (public.is_member(restaurant_id));

-- ============================================================
-- 6) دالة admin_fleet — ترجع كل بيانات لوحة التوصيل
-- ============================================================
create or replace function public.admin_fleet(rid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  res jsonb;
  r   public.restaurants%rowtype;
begin
  select * into r from public.restaurants where id=rid;
  if not found then return '{"error":"not found"}'::jsonb; end if;

  select jsonb_build_object(
    'billing', jsonb_build_object(
      'active',    coalesce(r.delivery_active, false),
      'capacity',  coalesce(r.delivery_capacity, 3),
      'used',      (select count(*) from public.drivers where restaurant_id=rid and is_active),
      'expires',   r.delivery_expires_at,
      'price',     19,
      'seat_price',9,
      'ever',      coalesce(r.delivery_active, false)
    ),
    'drivers', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id',         d.id,
        'name',       d.name,
        'phone',      d.phone,
        'token',      d.token,
        'is_active',  d.is_active,
        'on_duty',    d.on_duty,
        'done_today', d.done_today,
        'allowed',    d.allowed,
        'pos', (
          select jsonb_build_object('lat',t.lat,'lng',t.lng,'speed',t.speed,
                                   'battery',t.battery,'pos_at',t.pos_at,'src',t.kind)
          from public.tracker_devices t
          where t.driver_id=d.id and t.pos_at is not null
          order by t.pos_at desc limit 1
        )
      ) order by d.created_at),'[]'::jsonb)
      from public.drivers d where d.restaurant_id=rid
    ),
    'orders', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id',            o.id,
        'order_no',      o.order_no,
        'customer_name', o.customer_name,
        'customer_phone',o.customer_phone,
        'total_usd',     o.total_usd,
        'dispatch',      coalesce(o.dispatch,''),
        'driver_id',     o.driver_id,
        'lat',           o.lat,
        'lng',           o.lng,
        'created_at',    o.created_at
      ) order by o.created_at desc),'[]'::jsonb)
      from public.orders o
      where o.restaurant_id=rid
        and o.order_type='delivery'
        and o.status not in ('rejected','cancelled')
        and (o.dispatch is null or o.dispatch not in ('delivered','cancelled'))
        and o.created_at > now() - interval '8 hours'
    ),
    'settings', jsonb_build_object(
      'dispatch_mode', coalesce(r.delivery_mode,'manual'),
      'api_key',       coalesce(r.delivery_api_key,'')
    )
  ) into res;

  return res;
end $$;

-- ============================================================
-- 7) دالة admin_dispatch — تعيين / سحب / إلغاء توصيل
-- ============================================================
create or replace function public.admin_dispatch(
  p_order  bigint,
  p_action text,
  p_driver uuid default null
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  o public.orders%rowtype;
begin
  select * into o from public.orders where id=p_order;
  if not found then return '{"error":"order not found"}'::jsonb; end if;
  if not public.is_member(o.restaurant_id) then return '{"error":"forbidden"}'::jsonb; end if;

  case p_action
    when 'send' then
      update public.orders set dispatch='waiting', driver_id=null where id=p_order;
    when 'assign' then
      update public.orders set dispatch='claimed', driver_id=p_driver where id=p_order;
    when 'unassign' then
      update public.orders set dispatch='waiting', driver_id=null where id=p_order;
    when 'cancel' then
      update public.orders set dispatch='cancelled' where id=p_order;
    else
      return '{"error":"unknown action"}'::jsonb;
  end case;

  return '{"ok":true}'::jsonb;
end $$;

-- ============================================================
-- 8) دالة admin_delivery_settings — قراءة وتعديل إعدادات التوصيل
-- ============================================================
create or replace function public.admin_delivery_settings(
  rid       uuid,
  p_mode    text    default null,
  p_new_key boolean default false
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r   public.restaurants%rowtype;
  nk  text;
begin
  if not public.is_member(rid) then return '{"error":"forbidden"}'::jsonb; end if;

  if p_mode is not null then
    update public.restaurants set delivery_mode=p_mode where id=rid;
  end if;
  if p_new_key then
    nk := encode(gen_random_bytes(20),'hex');
    update public.restaurants set delivery_api_key=nk where id=rid;
  end if;

  select * into r from public.restaurants where id=rid;
  return jsonb_build_object(
    'dispatch_mode', coalesce(r.delivery_mode,'manual'),
    'api_key',       coalesce(r.delivery_api_key,'')
  );
end $$;

-- ============================================================
-- 9) دالة delivery_state — للتحقق من حالة الاشتراك
-- ============================================================
create or replace function public.delivery_state(rid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.restaurants%rowtype;
begin
  select * into r from public.restaurants where id=rid;
  if not found then return '{"active":false}'::jsonb; end if;
  return jsonb_build_object(
    'active',    coalesce(r.delivery_active, false),
    'capacity',  coalesce(r.delivery_capacity, 3),
    'used',      (select count(*) from public.drivers where restaurant_id=rid and is_active),
    'expires',   r.delivery_expires_at,
    'price',     19,
    'seat_price',9,
    'ever',      coalesce(r.delivery_active, false)
  );
end $$;

-- ============================================================
-- 10) تفعيل التوصيل لكل المطاعم الحالية (للاختبار)
-- ============================================================
update public.restaurants
set delivery_active=true, delivery_capacity=10
where delivery_active is false or delivery_active is null;

-- ============================================================
-- تحقق
-- ============================================================
select 'drivers' as tbl, count(*) from public.drivers
union all
select 'tracker_devices', count(*) from public.tracker_devices;
