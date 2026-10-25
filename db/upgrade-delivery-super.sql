-- ============================================================
--  LibanApps — تبويب التوصيل في لوحة Super
--  ينشئ:
--   · جدول addon_prices  (أسعار التوصيل العامة)
--   · جدول delivery_seats (مقاعد موظفين لكل مطعم)
--   · RPC super_delivery_list
--   · RPC super_delivery_extend
--   · RPC super_delivery_stop
--   · RPC super_delivery_add_seats
--   · RPC super_delivery_seat
--   · RPC super_delivery_prices
--  آمن للتشغيل أكثر من مرة
-- ============================================================

-- ============================================================
-- 1) جدول الأسعار العامة
-- ============================================================
create table if not exists public.addon_prices (
  code        text primary key,          -- 'delivery' | 'driver_seat'
  price_usd   numeric(8,2) not null default 0,
  days        integer      not null default 365,
  updated_at  timestamptz  not null default now()
);

-- قيم افتراضية (بتتغير من لوحة super)
insert into public.addon_prices(code, price_usd, days) values
  ('delivery',    19, 365),
  ('driver_seat', 25, 365)
on conflict(code) do nothing;

-- ============================================================
-- 2) جدول مقاعد الموظفين الإضافية
-- ============================================================
create table if not exists public.delivery_seats (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  expires_at    timestamptz not null,
  source        text not null default 'cash',   -- cash | whish | gift
  note          text not null default '',
  created_at    timestamptz not null default now()
);
create index if not exists dseats_rest_idx on public.delivery_seats(restaurant_id);

-- RLS
alter table public.addon_prices enable row level security;
drop policy if exists "prices_read" on public.addon_prices;
create policy "prices_read" on public.addon_prices for select using (true);

alter table public.delivery_seats enable row level security;
drop policy if exists "seats_read"  on public.delivery_seats;
drop policy if exists "seats_write" on public.delivery_seats;
create policy "seats_read"  on public.delivery_seats for select using (true);
create policy "seats_write" on public.delivery_seats for all
  using (public.is_member(restaurant_id)) with check (public.is_member(restaurant_id));

-- إضافة حقول السعر الخاص والمقاعد المشمولة على restaurants
alter table public.restaurants
  add column if not exists dlv_base_price  numeric(8,2),
  add column if not exists dlv_seat_price  numeric(8,2),
  add column if not exists dlv_included    integer not null default 1,
  add column if not exists dlv_notes       text not null default '';

-- ============================================================
-- 3) DROP القديم قبل CREATE
-- ============================================================
drop function if exists public.super_delivery_list();
drop function if exists public.super_delivery_extend(uuid,integer,text);
drop function if exists public.super_delivery_stop(uuid);
drop function if exists public.super_delivery_add_seats(uuid,integer,integer,text);
drop function if exists public.super_delivery_seat(uuid,integer);
drop function if exists public.super_delivery_prices(uuid,numeric,numeric,integer);

-- ============================================================
-- 4) super_delivery_list — قائمة المطاعم مع حالة التوصيل
-- ============================================================
create or replace function public.super_delivery_list()
returns jsonb language plpgsql security definer set search_path = public as $$
declare rows jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',          r.id,
    'name',        r.name_ar,
    'slug',        r.slug,
    'active',      coalesce(r.delivery_active, false),
    'expires_at',  r.delivery_expires_at,
    'capacity',    coalesce(r.delivery_capacity, 1),
    'drivers',     (select count(*) from public.drivers d where d.restaurant_id=r.id and d.is_active),
    'base_price',  r.dlv_base_price,
    'seat_price',  r.dlv_seat_price,
    'included',    coalesce(r.dlv_included, 1),
    'notes',       r.dlv_notes,
    'paid',        null,
    'seats', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id',         s.id,
        'expires_at', s.expires_at,
        'source',     s.source,
        'note',       s.note
      ) order by s.expires_at),'[]'::jsonb)
      from public.delivery_seats s where s.restaurant_id=r.id
    )
  ) order by r.name_ar),'[]'::jsonb)
  into rows from public.restaurants r;
  return rows;
end $$;

-- ============================================================
-- 5) super_delivery_extend — تفعيل أو تمديد اشتراك مطعم
-- ============================================================
create or replace function public.super_delivery_extend(
  rid     uuid,
  p_days  integer default 365,
  p_note  text    default ''
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  cur_exp timestamptz;
  new_exp timestamptz;
begin
  select delivery_expires_at into cur_exp from public.restaurants where id=rid;
  new_exp := coalesce(
    case when cur_exp > now() then cur_exp else now() end,
    now()
  ) + (p_days || ' days')::interval;
  update public.restaurants
    set delivery_active=true,
        delivery_expires_at=new_exp,
        dlv_notes=case when p_note<>'' then p_note else dlv_notes end
    where id=rid;
  return jsonb_build_object('ok',true,'expires_at',new_exp);
end $$;

-- ============================================================
-- 6) super_delivery_stop — إيقاف الاشتراك
-- ============================================================
create or replace function public.super_delivery_stop(rid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update public.restaurants
    set delivery_active=false, delivery_expires_at=now()
    where id=rid;
  return '{"ok":true}'::jsonb;
end $$;

-- ============================================================
-- 7) super_delivery_add_seats — إضافة مقاعد موظفين
-- ============================================================
create or replace function public.super_delivery_add_seats(
  rid       uuid,
  p_count   integer default 1,
  p_days    integer default 365,
  p_source  text    default 'cash'
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  exp_at timestamptz;
  r      public.restaurants%rowtype;
  i      integer;
begin
  select * into r from public.restaurants where id=rid;
  exp_at := coalesce(
    case when r.delivery_expires_at > now() then r.delivery_expires_at else now() end,
    now()
  ) + (p_days || ' days')::interval;
  for i in 1..p_count loop
    insert into public.delivery_seats(restaurant_id, expires_at, source)
      values(rid, exp_at, p_source);
  end loop;
  -- تحديث الـ capacity
  update public.restaurants
    set delivery_capacity = coalesce(dlv_included,1) +
      (select count(*) from public.delivery_seats where restaurant_id=rid)
    where id=rid;
  return jsonb_build_object('ok',true,'added',p_count);
end $$;

-- ============================================================
-- 8) super_delivery_seat — تمديد أو حذف مقعد واحد
-- ============================================================
create or replace function public.super_delivery_seat(
  p_seat  uuid,
  p_days  integer default 365
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  rid uuid;
begin
  if p_days=0 then
    select restaurant_id into rid from public.delivery_seats where id=p_seat;
    delete from public.delivery_seats where id=p_seat;
  else
    update public.delivery_seats
      set expires_at = expires_at + (p_days || ' days')::interval
      where id=p_seat
      returning restaurant_id into rid;
  end if;
  -- تحديث الـ capacity
  if rid is not null then
    update public.restaurants
      set delivery_capacity = coalesce(dlv_included,1) +
        (select count(*) from public.delivery_seats where restaurant_id=rid)
      where id=rid;
  end if;
  return '{"ok":true}'::jsonb;
end $$;

-- ============================================================
-- 9) super_delivery_prices — سعر خاص لمطعم معيّن
-- ============================================================
create or replace function public.super_delivery_prices(
  rid         uuid,
  p_base      numeric default null,
  p_seat      numeric default null,
  p_included  integer default null
) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update public.restaurants
    set dlv_base_price = p_base,
        dlv_seat_price = p_seat,
        dlv_included   = coalesce(p_included, dlv_included, 1),
        delivery_capacity = coalesce(p_included, dlv_included, 1) +
          (select count(*) from public.delivery_seats where restaurant_id=rid)
    where id=rid;
  return '{"ok":true}'::jsonb;
end $$;

-- ============================================================
-- تحقق
-- ============================================================
select code, price_usd, days from public.addon_prices;
select public.super_delivery_list();
