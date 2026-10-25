-- ============================================================
--  LibanApps — تحديث حالة الطلب: قبول / رفض + سبب الرفض
--  آمن للتشغيل أكثر من مرة
-- ============================================================

-- إضافة القيم الجديدة لـ status (إذا كان enum)
-- لو status عمود text عادي ما في مشكلة
alter table public.orders
  add column if not exists reject_reason text default '';

-- تأكد من قيم status المقبولة (إذا في check constraint)
-- نزيل القيد القديم ونضيف جديد يشمل accepted/rejected
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders
  add constraint orders_status_check
  check (status in ('pending','accepted','rejected','paid','cancelled','refunded'));

-- تحقق
select status, count(*) from public.orders group by status;
