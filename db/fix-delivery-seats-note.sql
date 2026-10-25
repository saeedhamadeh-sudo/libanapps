-- إضافة عمود note لجدول delivery_seats إذا ما كان موجود
alter table public.delivery_seats
  add column if not exists note text not null default '';

-- إعادة إنشاء الـ RPC بعد إضافة العمود
drop function if exists public.super_delivery_list();
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

-- تحقق
select public.super_delivery_list();
