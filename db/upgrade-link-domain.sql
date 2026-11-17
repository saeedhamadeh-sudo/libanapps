-- ============================================================
--  LibanApps — «وصلة»: دومين خاص لكل صفحة (Cloudflare for SaaS)
--  الزبون بيضيف links.mybrand.com ← سجل CNAME إلى stores.libanapps.com
--  الإضافة والتحقق والحذف عبر الـWorker (/api/link/domain) بمفتاح الخدمة.
--  آمن للتشغيل أكثر من مرة. شرط مسبق: upgrade-link.sql
-- ============================================================

create table if not exists public.link_domains (
  id             uuid primary key default gen_random_uuid(),
  page_id        uuid not null unique references public.link_pages(id) on delete cascade,
  domain         text not null unique,
  cf_hostname_id text,
  status         text not null default 'pending',   -- pending | active | failed
  cf_status      text not null default '',
  ssl_status     text not null default '',
  info           jsonb not null default '{}'::jsonb, -- cname_target / txt_name / txt_value / errors
  verified_at    timestamptz,
  created_at     timestamptz not null default now()
);
alter table public.link_domains enable row level security;
revoke all on public.link_domains from anon;

-- صاحب الصفحة بيقرأ دومينه فقط (الكتابة عبر الـWorker)
drop policy if exists own_link_domains on public.link_domains;
create policy own_link_domains on public.link_domains for select to authenticated
  using (public.link_owned(page_id));
grant select on public.link_domains to authenticated;

select 'link_domains' as item, to_regclass('public.link_domains') is not null as ok;
