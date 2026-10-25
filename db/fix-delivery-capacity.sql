-- ============================================================
--  إصلاح capacity لكل المطاعم بناءً على مقاعدها الفعلية
--  وضبط expires_at للمطاعم اللي active=true وما عندها تاريخ
-- ============================================================

-- إعادة حساب capacity = dlv_included + عدد المقاعد الإضافية
update public.restaurants r
set delivery_capacity = coalesce(r.dlv_included, 1) +
  (select count(*) from public.delivery_seats s where s.restaurant_id=r.id);

-- المطاعم اللي active=true وما عندها expires_at:
-- نحط تاريخ انتهاء سنة من اليوم (كاش — تعديلها من لوحة super)
update public.restaurants
set delivery_expires_at = now() + interval '1 year'
where delivery_active = true
  and delivery_expires_at is null;

-- تحقق
select name_ar, delivery_active, delivery_expires_at, delivery_capacity
from public.restaurants;
