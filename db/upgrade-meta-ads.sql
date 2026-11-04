-- =====================================================================
--  ربط حسابات إعلانات Meta بلوحة الحساب (ads_read)
--  آمن للتشغيل أكثر من مرة: ما بيحذف ولا بيغيّر بيانات موجودة.
--  شغّله مرة وحدة بـ Supabase ← SQL Editor (مشروع المنصة moriwmhlgugmjzddwfgv)
-- =====================================================================
create table if not exists public.meta_ads_connections (
  user_id          uuid primary key references auth.users(id) on delete cascade,
  fb_user_id       text not null,
  fb_name          text default '',
  token_enc        text not null,   -- التوكن مشفّر AES-GCM من الـworker
  token_expires_at timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists meta_ads_connections_fb_idx on public.meta_ads_connections (fb_user_id);

-- ما حدا بيقرأه من المتصفح — بس الـ worker (service key)
alter table public.meta_ads_connections enable row level security;
revoke all on public.meta_ads_connections from anon, authenticated;
