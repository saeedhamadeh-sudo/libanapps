-- ============================================================
--  LibanApps — إضافة إعدادات التوصيل لكل فرع
--  شغّله على Supabase SQL Editor
--  آمن للتشغيل أكثر من مرة
-- ============================================================

alter table public.restaurant_branches
  add column if not exists delivery_enabled  boolean not null default false;

alter table public.restaurant_branches
  add column if not exists delivery_fee_usd  numeric(8,2) not null default 0;

alter table public.restaurant_branches
  add column if not exists min_order_usd     numeric(8,2) not null default 0;

alter table public.restaurant_branches
  add column if not exists delivery_note_ar  text not null default '';

-- تحقق
select id, name_ar, delivery_enabled, delivery_fee_usd, min_order_usd
from public.restaurant_branches
limit 10;
