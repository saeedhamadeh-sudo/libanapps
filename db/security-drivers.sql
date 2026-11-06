-- ============================================================
--  LibanApps — تسكير جدولي drivers و tracker_devices عن العموم
--  ------------------------------------------------------------
--  المشكلة: policy "drivers_read" و "tdev_read" كانت using (true)
--  يعني أي حدا معو الـanon key (موجود بكل صفحة) بيقدر يقرا:
--    • drivers.token        ← رابط دخول كل شوفير (/d/<token>)
--    • tracker_devices.identifier ← IMEI/ID الجهاز، وهو المفتاح اللي
--      /api/track/push بيقبل فيه المواقع → حدا بيقدر يزوّر موقع الشوفير
--    • موقع الشوفيرية المباشر (lat/lng)
--
--  الحل: القراءة بس لأعضاء المطعم وللسوبر (public.is_member بيشمل is_admin).
--  صفحة الشوفير وصفحة التتبع ما بيتأثروا — بيشتغلوا عبر دوال security definer
--  (driver_session, track_order, driver_vendor_info...) والـWorker بيستعمل service key.
--
--  شغّله مرة وحدة على Supabase SQL Editor — آمن للتشغيل أكثر من مرة
-- ============================================================

-- 1) drivers
alter table public.drivers enable row level security;
drop policy if exists "drivers_read"  on public.drivers;
drop policy if exists "drivers_write" on public.drivers;
drop policy if exists "drivers_member" on public.drivers;
create policy "drivers_member" on public.drivers
  for all using (public.is_member(restaurant_id))
  with check (public.is_member(restaurant_id));

-- 2) tracker_devices
alter table public.tracker_devices enable row level security;
drop policy if exists "tdev_read"  on public.tracker_devices;
drop policy if exists "tdev_write" on public.tracker_devices;
drop policy if exists "tdev_member" on public.tracker_devices;
create policy "tdev_member" on public.tracker_devices
  for all using (public.is_member(restaurant_id))
  with check (public.is_member(restaurant_id));

-- 3) ما في داعي يكون للـanon أي صلاحية مباشرة على الجدولين
revoke all on public.drivers         from anon;
revoke all on public.tracker_devices from anon;

-- 4) أي policy تانية مفتوحة (using true) على الجدولين؟ لازم يطلع فاضي
select tablename, policyname, cmd, qual
from pg_policies
where schemaname = 'public'
  and tablename in ('drivers','tracker_devices')
  and (qual = 'true' or qual is null);
