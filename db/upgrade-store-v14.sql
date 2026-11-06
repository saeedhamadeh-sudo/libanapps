-- ============================================================
--  LibanApps Store — v14
--   • صورة مخصصة للتلفون لكل سلايد (mobile_image_url) — اختيارية.
--  شغّله مرة وحدة — آمن للتشغيل أكثر من مرة.
-- ============================================================
alter table public.store_slides add column if not exists mobile_image_url text default '';

select 'slides.mobile_image_url' as item,
       exists (select 1 from information_schema.columns
               where table_name='store_slides' and column_name='mobile_image_url') as ok;
