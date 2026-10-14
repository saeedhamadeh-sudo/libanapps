-- =====================================================================
--  الدخول برمز واتس اب (VerifyWay) — الجداول التي يحتاجها worker.js
--  آمن للتشغيل أكثر من مرة: ما بيحذف ولا بيغيّر بيانات موجودة.
--  شغّله مرة وحدة بـ Supabase ← SQL Editor (مشروع المنصة moriwmhlgugmjzddwfgv)
-- =====================================================================

-- الرموز المُرسلة (مخزّنة كبصمة hash، مش الرمز نفسه)
create table if not exists public.phone_otps (
  id          uuid primary key default gen_random_uuid(),
  phone       text not null,
  code_hash   text not null,
  ip          text default '',
  attempts    int  not null default 0,
  expires_at  timestamptz not null,
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists phone_otps_phone_idx on public.phone_otps (phone, created_at desc);
create index if not exists phone_otps_ip_idx    on public.phone_otps (ip, created_at desc);

-- ربط رقم الهاتف بحساب الدخول
create table if not exists public.phone_logins (
  phone       text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);
create index if not exists phone_logins_user_idx on public.phone_logins (user_id);

-- ما حدا بيقرأهم من المتصفح — بس الـ worker (service key)
alter table public.phone_otps   enable row level security;
alter table public.phone_logins enable row level security;
revoke all on public.phone_otps, public.phone_logins from anon, authenticated;

-- زبون قديم سجّل بالإيميل وحاطط رقمه بحسابه: منلاقيه بالرقم (بعد توحيد الصيغة: 961xxxxxxx)
create or replace function public.norm_phone_lb(p text)
returns text language sql immutable as $$
  with d as (select regexp_replace(coalesce(p,''), '\D', '', 'g') as v),
       s as (select case when v like '00%' then substr(v, 3) else v end as v from d),
       t as (select case when v like '961%' then v
                         when v like '0%' then substr(v, 2)
                         else v end as v from s)
  select case when v like '961%' then v
              when length(v) between 7 and 8 then '961' || v
              else v end from t;
$$;

drop function if exists public.find_client_users_by_phone(text);
create function public.find_client_users_by_phone(p_phone text)
returns table (user_id uuid)
language sql stable security definer set search_path = public as $$
  select distinct c.user_id
  from public.clients c
  where c.user_id is not null
    and coalesce(c.phone, '') <> ''
    and public.norm_phone_lb(c.phone) = public.norm_phone_lb(p_phone);
$$;
revoke all on function public.find_client_users_by_phone(text) from public, anon, authenticated;
grant execute on function public.find_client_users_by_phone(text) to service_role;

-- تنظيف: الرموز القديمة (أكثر من يومين) ما إلها لزوم
delete from public.phone_otps where created_at < now() - interval '2 days';
