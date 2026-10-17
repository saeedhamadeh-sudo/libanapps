-- =====================================================================
--  تصليح: رابط الزبون (/portal-trade/… و /portal/…) عم يطلع «أكمل بياناتك»
--  السبب: ملف upgrade-store.sql كان يرجّع تعريف my_client_id القديم
--  اللي ما بيعرف حسابات الروابط (portal_users).
--  آمن للتشغيل أكثر من مرة. شغّله بـ Supabase ← SQL Editor.
-- =====================================================================
create table if not exists public.portal_users (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  client_id  uuid not null unique references public.clients(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.portal_users add column if not exists email text;
alter table public.portal_users enable row level security;

create or replace function public.my_client_id()
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(
    (select p.client_id from public.portal_users p where p.user_id = auth.uid() limit 1),
    (select c.id from public.clients c where c.user_id = auth.uid() limit 1)
  );
$$;

-- فحص: لازم يطلع فيه portal_users
select pg_get_functiondef('public.my_client_id()'::regprocedure) like '%portal_users%' as portal_ok;
