-- ============================================================
--  LibanApps Store — v5
--   • قائمة ماركات نظيفة (store_brands) + تعبئة تلقائية من ماركات المنتجات الحالية
--   • أيقونة متصفح (favicon) منفصلة عن اللوغو
--  شغّله بعد upgrade-store-v4.sql — آمن للتشغيل أكثر من مرة.
-- ============================================================
alter table public.stores add column if not exists favicon_url text default '';

create table if not exists public.store_brands (
  id        uuid primary key default gen_random_uuid(),
  store_id  uuid not null references public.stores(id) on delete cascade,
  name      text not null,
  sort      integer not null default 0,
  is_active boolean not null default true,
  unique (store_id, name)
);
create index if not exists store_brands_idx on public.store_brands (store_id, sort);
alter table public.store_brands enable row level security;
drop policy if exists own_store_brands on public.store_brands;
create policy own_store_brands on public.store_brands for all to authenticated
  using (public.store_owned(store_id)) with check (public.store_owned(store_id));

-- تعبئة الماركات الموجودة حالياً بمنتجات كل متجر
insert into public.store_brands (store_id, name, sort)
select p.store_id, p.brand, row_number() over (partition by p.store_id order by min(p.created_at))
from public.store_products p
where coalesce(trim(p.brand), '') <> ''
group by p.store_id, p.brand
on conflict (store_id, name) do nothing;

select 'store_brands' as item, to_regclass('public.store_brands') is not null as ok
union all select 'favicon_url', exists (select 1 from information_schema.columns where table_name='stores' and column_name='favicon_url');
