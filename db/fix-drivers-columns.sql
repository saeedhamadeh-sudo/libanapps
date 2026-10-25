-- ============================================================
--  LibanApps — إصلاح أعمدة جدول drivers الناقصة
--  شغّله على Supabase SQL Editor
--  آمن للتشغيل أكثر من مرة
-- ============================================================

alter table public.drivers
  add column if not exists token       text    not null default '',
  add column if not exists on_duty     boolean not null default false,
  add column if not exists done_today  integer not null default 0,
  add column if not exists allowed     boolean not null default true;

-- تحقق
select id, name, token, on_duty, done_today, allowed
from public.drivers limit 5;
