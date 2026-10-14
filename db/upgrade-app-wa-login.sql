-- =====================================================================
--  الدخول عبر واتساب لمستخدمي برامج التجاري والصناعي (ADMIN والموظفين)
--  + تغيير كلمة السر للمستخدم نفسه
--  شغّله بعد upgrade-whatsapp-login.sql. آمن للتشغيل أكثر من مرة.
-- =====================================================================

-- SUPER يفعّل الميزة لكل زبون
alter table public.clients add column if not exists wa_login boolean not null default false;

-- رقم واتساب لكل مستخدم بالبرنامج (بصيغة 961xxxxxxxx)
alter table public.trade_app_users add column if not exists phone text;
alter table public.alum_app_users  add column if not exists phone text;
create index if not exists trade_app_users_phone_idx on public.trade_app_users (client_id, phone);
create index if not exists alum_app_users_phone_idx  on public.alum_app_users  (client_id, phone);

-- تذكرة دخول قصيرة العمر يصدرها الـWorker بعد التحقق من رمز الواتساب
create table if not exists public.app_wa_tickets (
  ticket_hash text primary key,
  client_id   uuid not null,
  product     text not null,
  account_id  text not null,
  expires_at  timestamptz not null,
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);
alter table public.app_wa_tickets enable row level security;
revoke all on public.app_wa_tickets from anon, authenticated;

-- الدخول بالتذكرة (نفس جلسة app_login بالضبط)
create or replace function public.app_login_wa(p_product text, p_ticket text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_cid uuid := public.my_client_id(); v_sid uuid := public.app_sid();
        tk public.app_wa_tickets; r jsonb; t text;
begin
  if p_product not in ('alum','trade') then raise exception 'bad product'; end if;
  if auth.uid() is null or v_sid is null then return jsonb_build_object('ok', false, 'reason', 'no_session'); end if;
  if v_cid is null then return jsonb_build_object('ok', false, 'reason', 'no_client'); end if;
  delete from public.app_wa_tickets where created_at < now() - interval '1 day';
  select * into tk from public.app_wa_tickets
   where ticket_hash = encode(digest(coalesce(p_ticket,''), 'sha256'), 'hex')
     and used_at is null and expires_at > now();
  if not found or tk.client_id <> v_cid or tk.product <> p_product then
    return jsonb_build_object('ok', false, 'reason', 'invalid');
  end if;
  update public.app_wa_tickets set used_at = now() where ticket_hash = tk.ticket_hash;
  t := p_product || '_app_users';
  execute format('select to_jsonb(x) from public.%I x where x.client_id = $1 and x.id::text = $2 limit 1', t)
    into r using v_cid, tk.account_id;
  if r is null then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  insert into public.app_sessions as a (sid, product, uid, client_id, kind, account_id, role, perms)
  values (v_sid, p_product, auth.uid(), v_cid, 'staff', r->>'id', r->>'role',
          coalesce(array(select jsonb_array_elements_text(case when jsonb_typeof(r->'permissions')='array' then r->'permissions' else '[]'::jsonb end)), '{}'))
  on conflict (sid, product) do update set uid = excluded.uid, client_id = excluded.client_id, kind = excluded.kind,
    account_id = excluded.account_id, role = excluded.role, perms = excluded.perms,
    customer_id = null, worker_id = null, created_at = now();
  return jsonb_build_object('ok', true, 'kind', 'staff', 'account', (r - 'password' - 'totp_secret' - 'client_id'));
end $$;
revoke all on function public.app_login_wa(text, text) from public, anon;
grant execute on function public.app_login_wa(text, text) to authenticated;

-- المستخدم يغيّر كلمة سرّه بنفسه (الوضع الآمن) — لازم كلمة السر الحالية
create or replace function public.app_change_password(p_product text, p_old text, p_new text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.app_sessions; t text; r jsonb;
begin
  if p_product not in ('alum','trade') then raise exception 'bad product'; end if;
  s := public.app_cur(p_product);
  if s.sid is null or s.kind <> 'staff' then return jsonb_build_object('ok', false, 'reason', 'no_session'); end if;
  if length(coalesce(p_new,'')) < 4 then return jsonb_build_object('ok', false, 'reason', 'short'); end if;
  t := p_product || '_app_users';
  execute format('select to_jsonb(x) from public.%I x where x.client_id = $1 and x.id::text = $2 limit 1', t)
    into r using s.client_id, s.account_id;
  if r is null or not public.app_pw_ok(t, r, p_old) then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  execute format('update public.%I set password = $1 where client_id = $2 and id::text = $3', t)
    using p_new, s.client_id, s.account_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.app_change_password(text, text, text) from public, anon;
grant execute on function public.app_change_password(text, text, text) to authenticated;
