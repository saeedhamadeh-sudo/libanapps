-- ============================================================
--  LibanApps — إصلاح أعمدة جدول tracker_devices الناقصة
--  آمن للتشغيل أكثر من مرة
-- ============================================================

alter table public.tracker_devices
  add column if not exists kind        text             not null default 'gps_tracker',
  add column if not exists label       text                      default '',
  add column if not exists identifier  text                      default '',
  add column if not exists lat         double precision,
  add column if not exists lng         double precision,
  add column if not exists speed       double precision,
  add column if not exists battery     double precision,
  add column if not exists pos_at      timestamptz,
  add column if not exists src         text                      default 'gps_tracker';

-- تحقق
select id, driver_id, kind, lat, lng, speed, battery, pos_at
from public.tracker_devices limit 5;
