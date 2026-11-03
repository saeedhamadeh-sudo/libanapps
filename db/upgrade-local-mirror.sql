-- ============================================================
--  النسخة المحلية — نسخة «للقراءة بس» على السحابة للزباين والعمال
--  البرنامج على كمبيوتر المحل بيرفع كل ١٠ دقايق:
--   · لكل حساب زبون: بيانات الزبون + فواتيرو + إيصالاتو
--   · لكل حساب عامل: العامل + يومياتو + دفعاتو
--   · إعدادات البرنامج (الاسم والشعار لشاشة الدخول)
--  لما الكمبيوتر يكون مطفي، الـWorker بيفتح البرنامج من هالنسخة — للقراءة بس.
--  كلمات السر بتنفحص هون بقاعدة البيانات (bcrypt) وما بتطلع لبرّا.
--  شغّلو مرة وحدة — آمن للتكرار. (بعد upgrade-local-tunnels.sql)
-- ============================================================
create extension if not exists pgcrypto;

create table if not exists public.local_mirror (
  client_id     uuid not null references public.clients(id) on delete cascade,
  product       text not null,                 -- alum / trade
  kind          text not null,                 -- settings / customer / worker
  username      text not null default '',      -- lower(username) — فاضي للإعدادات
  account       jsonb,                         -- سطر الحساب بلا كلمة السر
  password_hash text,                          -- bcrypt ($2a$)
  payload       jsonb not null default '{}'::jsonb,
  updated_at    timestamptz not null default now(),
  primary key (client_id, product, kind, username)
);
alter table public.local_mirror enable row level security;   -- بلا سياسات: عبر الدوال بس
revoke all on public.local_mirror from anon, authenticated;

create table if not exists public.local_mirror_sessions (
  sid        text not null,
  product    text not null,
  client_id  uuid not null,
  kind       text not null,
  username   text not null,
  created_at timestamptz not null default now(),
  primary key (sid, product)
);
alter table public.local_mirror_sessions enable row level security;
revoke all on public.local_mirror_sessions from anon, authenticated;

create table if not exists public.local_mirror_attempts (
  client_id uuid not null, product text not null, username text not null, at timestamptz not null default now()
);
create index if not exists local_mirror_attempts_idx on public.local_mirror_attempts (client_id, product, username, at);
alter table public.local_mirror_attempts enable row level security;
revoke all on public.local_mirror_attempts from anon, authenticated;

-- ---------- الرفع: من البرنامج المحلي (بحساب صاحب المحل) ----------
create or replace function public.local_mirror_push(p_product text, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare cid uuid := public.my_client_id(); n int;
begin
  if p_product not in ('alum','trade') then raise exception 'bad product'; end if;
  if cid is null then return jsonb_build_object('ok', false, 'reason', 'no_client'); end if;
  delete from public.local_mirror where client_id = cid and product = p_product;
  insert into public.local_mirror (client_id, product, kind, username, account, password_hash, payload, updated_at)
  select cid, p_product, x->>'kind', lower(coalesce(x->>'username','')), x->'account',
         nullif(x->>'password_hash',''), coalesce(x->'payload','{}'::jsonb), now()
    from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) x
   where x->>'kind' in ('settings','customer','worker')
  on conflict (client_id, product, kind, username) do update
     set account = excluded.account, password_hash = excluded.password_hash, payload = excluded.payload, updated_at = now();
  get diagnostics n = row_count;
  -- جلسات قديمة لحسابات انمحت
  delete from public.local_mirror_sessions s where s.client_id = cid and s.product = p_product
     and not exists (select 1 from public.local_mirror m where m.client_id = cid and m.product = p_product and m.kind = s.kind and m.username = s.username);
  return jsonb_build_object('ok', true, 'count', n);
end $$;
revoke all on function public.local_mirror_push(text, jsonb) from public, anon;
grant execute on function public.local_mirror_push(text, jsonb) to authenticated;

-- ---------- الدخول: من الـWorker بس (service role) ----------
create or replace function public.local_mirror_login(p_host text, p_product text, p_username text, p_password text, p_sid text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare cid uuid; r public.local_mirror; u text := lower(trim(coalesce(p_username,''))); fails int;
begin
  select client_id into cid from public.local_tunnels where hostname = lower(p_host);
  if cid is null or coalesce(p_sid,'') = '' then return jsonb_build_object('ok', false, 'reason', 'error', 'message', 'رابط غير معروف'); end if;
  delete from public.local_mirror_attempts where at < now() - interval '1 day';
  select count(*) into fails from public.local_mirror_attempts a
   where a.client_id = cid and a.product = p_product and a.username = u and a.at > now() - interval '15 minutes';
  if fails >= 8 then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into r from public.local_mirror m
   where m.client_id = cid and m.product = p_product and m.kind in ('customer','worker') and m.username = u
   limit 1;
  if r.client_id is null or r.password_hash is null or crypt(coalesce(p_password,''), r.password_hash) <> r.password_hash then
    insert into public.local_mirror_attempts (client_id, product, username) values (cid, p_product, u);
    return jsonb_build_object('ok', false, 'reason', 'error',
      'message', 'الكمبيوتر الأساسي بالمحل مطفي هلق — الدخول متاح لحسابات الزباين والعمال بس (للقراءة). تأكد من الاسم وكلمة السر.');
  end if;
  insert into public.local_mirror_sessions (sid, product, client_id, kind, username)
  values (p_sid, p_product, cid, r.kind, u)
  on conflict (sid, product) do update set client_id = excluded.client_id, kind = excluded.kind, username = excluded.username, created_at = now();
  return jsonb_build_object('ok', true, 'kind', r.kind, 'account', coalesce(r.account, '{}'::jsonb) - 'password' - 'client_id');
end $$;

-- البيانات: الإعدادات (قبل الدخول) + بيانات الحساب (بعد الدخول، لمدة ١٢ ساعة)
create or replace function public.local_mirror_fetch(p_host text, p_product text, p_sid text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare cid uuid; s public.local_mirror_sessions; st public.local_mirror; acc public.local_mirror;
        sub record;
begin
  select client_id into cid from public.local_tunnels where hostname = lower(p_host);
  if cid is null then return jsonb_build_object('ok', false); end if;
  select * into st from public.local_mirror where client_id = cid and product = p_product and kind = 'settings' and username = '';
  select * into sub from public.subscriptions where client_id = cid and product_code = p_product order by expires_at desc limit 1;
  if coalesce(p_sid,'') <> '' then
    select * into s from public.local_mirror_sessions where sid = p_sid and product = p_product and client_id = cid
       and created_at > now() - interval '12 hours';
    if s.sid is not null then
      select * into acc from public.local_mirror where client_id = cid and product = p_product and kind = s.kind and username = s.username;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'client_id', cid,
    'settings', coalesce(st.payload, '{}'::jsonb), 'updated_at', coalesce(acc.updated_at, st.updated_at),
    'kind', s.kind, 'data', case when acc.client_id is not null then acc.payload else null end,
    'sub', case when sub.client_id is null then null else jsonb_build_object('status', sub.status, 'expires_at', sub.expires_at, 'plan', sub.plan, 'id', sub.id) end);
end $$;

create or replace function public.local_mirror_logout(p_sid text, p_product text)
returns void language sql security definer set search_path = public as $$
  delete from public.local_mirror_sessions where sid = p_sid and product = p_product;
$$;

revoke all on function public.local_mirror_login(text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.local_mirror_fetch(text, text, text) from public, anon, authenticated;
revoke all on function public.local_mirror_logout(text, text) from public, anon, authenticated;
grant execute on function public.local_mirror_login(text, text, text, text, text) to service_role;
grant execute on function public.local_mirror_fetch(text, text, text) to service_role;
grant execute on function public.local_mirror_logout(text, text) to service_role;
