-- إضافة أعمدة التوصيل الخاصة لجدول restaurants
alter table public.restaurants
  add column if not exists dlv_base_price numeric(8,2),
  add column if not exists dlv_seat_price numeric(8,2),
  add column if not exists dlv_included   integer not null default 1,
  add column if not exists dlv_notes      text    not null default '';

-- تحقق
select id, name_ar, dlv_base_price, dlv_seat_price, dlv_included from public.restaurants limit 3;
