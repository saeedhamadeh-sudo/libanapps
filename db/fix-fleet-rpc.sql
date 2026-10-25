-- ============================================================
--  LibanApps — إصلاح دالة admin_fleet
--  يصلح: days_left، expires_at، included، السعر $25 للمقعد الإضافي
--  آمن للتشغيل أكثر من مرة
-- ============================================================

drop function if exists public.admin_fleet(uuid);

create or replace function public.admin_fleet(rid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  res      jsonb;
  r        public.restaurants%rowtype;
  exp_at   timestamptz;
  d_left   integer;
begin
  select * into r from public.restaurants where id=rid;
  if not found then return '{"error":"not found"}'::jsonb; end if;

  exp_at := r.delivery_expires_at;
  d_left := case
    when exp_at is null then null
    else greatest(0, extract(day from (exp_at - now()))::integer)
  end;

  select jsonb_build_object(
    'billing', jsonb_build_object(
      'active',     coalesce(r.delivery_active, false),
      'capacity',   coalesce(r.delivery_capacity, 3),
      'used',       (select count(*) from public.drivers where restaurant_id=rid and is_active),
      'expires_at', exp_at,
      'days_left',  d_left,
      'price',      19,
      'seat_price', 25,
      'included',   1,
      'ever',       coalesce(r.delivery_active, false)
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
        'branch_id',  d.branch_id,
        'pos', (
          select jsonb_build_object(
            'lat',     t.lat,
            'lng',     t.lng,
            'speed',   t.speed,
            'battery', t.battery,
            'pos_at',  t.pos_at,
            'src',     t.kind
          )
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

-- إصلاح delivery_state كذلك
drop function if exists public.delivery_state(uuid);
create or replace function public.delivery_state(rid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r      public.restaurants%rowtype;
  exp_at timestamptz;
  d_left integer;
begin
  select * into r from public.restaurants where id=rid;
  if not found then return '{"active":false}'::jsonb; end if;
  exp_at := r.delivery_expires_at;
  d_left := case
    when exp_at is null then null
    else greatest(0, extract(day from (exp_at - now()))::integer)
  end;
  return jsonb_build_object(
    'active',     coalesce(r.delivery_active, false),
    'capacity',   coalesce(r.delivery_capacity, 3),
    'used',       (select count(*) from public.drivers where restaurant_id=rid and is_active),
    'expires_at', exp_at,
    'days_left',  d_left,
    'price',      19,
    'seat_price', 25,
    'included',   1,
    'ever',       coalesce(r.delivery_active, false)
  );
end $$;

-- تحقق
select public.delivery_state(id) from public.restaurants limit 1;
