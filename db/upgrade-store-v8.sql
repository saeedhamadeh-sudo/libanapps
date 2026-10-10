-- ============================================================
--  LibanApps Store — v8
--   • تصنيف نظامي ثابت "منتجات بدون تصنيف" لكل متجر
--     (ما بينحذف، وبيستقبل أي منتج تصنيفه انحذف)
--  شغّله بعد upgrade-store-v7.sql — آمن للتشغيل أكثر من مرة.
-- ============================================================
alter table public.store_categories add column if not exists is_system boolean not null default false;

-- متجر واحد ما بيقدر يكون فيه أكتر من تصنيف نظامي واحد
create unique index if not exists store_cat_system_uq on public.store_categories (store_id) where is_system;

select 'categories.is_system' as item,
       exists (select 1 from information_schema.columns where table_name='store_categories' and column_name='is_system') as ok
union all
select 'store_cat_system_uq', exists (select 1 from pg_indexes where indexname='store_cat_system_uq');
