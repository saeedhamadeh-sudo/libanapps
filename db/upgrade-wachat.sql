-- ============================================================
--  LibanApps Chat — صندوق محادثات واتساب (عبر WhatChimp) لكل زبائن LibanApps
--  كل صندوق (inbox) = رقم واتساب واحد مربوط بمفتاح WhatChimp
--  المستخدمين: main (المدير الأساسي) و admin (مدير) — دخول باسم مستخدم وكلمة سر
--  الرسائل بتوصل عبر webhook (واردة وصادرة) وبتنحفظ هون؛ الإرسال من الـworker
-- ============================================================

create table if not exists public.wa_inboxes (
  id             uuid primary key default gen_random_uuid(),
  name           text not null default '',
  wc_api_key     text,                       -- سرّي: ما بيطلع للمتصفح أبداً
  wc_hook_secret text,                       -- سرّي: للتحقق من توقيع الـwebhook
  motor_site_id  uuid references public.motor_sites(id) on delete set null,  -- صندوق مربوط ببرنامج موتير (بياخد مفتاحو ورسائلو)
  client_id      uuid,
  setup_hash     text,                       -- رمز الإعداد لأول مدير أساسي (مخزّن مشفّر)
  setup_expires  timestamptz,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);
create unique index if not exists wa_inboxes_motor_uq on public.wa_inboxes(motor_site_id) where motor_site_id is not null;

create table if not exists public.wa_users (
  id            uuid primary key default gen_random_uuid(),
  inbox_id      uuid not null references public.wa_inboxes(id) on delete cascade,
  name          text not null default '',
  username      text not null,
  password_hash text not null,
  role          text not null default 'admin' check (role in ('main','admin')),
  is_active     boolean not null default true,
  failed_count  int not null default 0,
  locked_until  timestamptz,
  created_at    timestamptz not null default now()
);
create unique index if not exists wa_users_username_uq on public.wa_users(lower(username));

create table if not exists public.wa_sessions (
  token_hash text primary key,
  user_id    uuid not null references public.wa_users(id) on delete cascade,
  inbox_id   uuid not null references public.wa_inboxes(id) on delete cascade,
  expires_at timestamptz not null default now() + interval '120 days',
  created_at timestamptz not null default now()
);

create table if not exists public.wa_chats (
  inbox_id   uuid not null references public.wa_inboxes(id) on delete cascade,
  phone      text not null,                  -- أرقام بس (بلا +)
  name       text not null default '',
  last_text  text not null default '',
  last_dir   text not null default 'in',
  last_at    timestamptz not null default now(),
  last_in_at timestamptz,                    -- آخر رسالة من الزبون (نافذة الـ24 ساعة)
  unread     int not null default 0,
  primary key (inbox_id, phone)
);
create index if not exists wa_chats_last on public.wa_chats(inbox_id, last_at desc);

create table if not exists public.wa_msgs (
  id         bigserial primary key,
  inbox_id   uuid not null references public.wa_inboxes(id) on delete cascade,
  phone      text not null,
  dir        text not null check (dir in ('in','out')),
  type       text not null default 'text',
  text       text not null default '',
  media_url  text not null default '',
  ext_id     text not null default '',
  status     text not null default '',
  by_name    text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists wa_msgs_chat on public.wa_msgs(inbox_id, phone, id desc);
create unique index if not exists wa_msgs_ext_uq on public.wa_msgs(inbox_id, ext_id) where ext_id <> '';

alter table public.wa_inboxes enable row level security;
alter table public.wa_users enable row level security;
alter table public.wa_sessions enable row level security;
alter table public.wa_chats enable row level security;
alter table public.wa_msgs enable row level security;
revoke all on public.wa_inboxes, public.wa_users, public.wa_sessions, public.wa_chats, public.wa_msgs from anon, authenticated;

create or replace function public._wa_err(p_code text) returns void language plpgsql as $$
begin raise exception 'WACHAT:%', p_code; end $$;

-- مين صاحب الجلسة
create or replace function public._wa_who(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.wa_sessions%rowtype; u public.wa_users%rowtype; ib public.wa_inboxes%rowtype;
begin
  select * into s from public.wa_sessions where token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex') and expires_at > now();
  if not found then perform public._wa_err('auth'); end if;
  select * into u from public.wa_users where id = s.user_id;
  select * into ib from public.wa_inboxes where id = s.inbox_id;
  if not u.is_active or not ib.is_active then perform public._wa_err('auth'); end if;
  return jsonb_build_object('user_id', u.id, 'inbox_id', ib.id, 'role', u.role, 'name', u.name, 'username', u.username);
end $$;
revoke all on function public._wa_who(text) from public, anon, authenticated;

create or replace function public._wa_digits(p text) returns text language sql immutable as $$
  select regexp_replace(coalesce(p,''), '\D', '', 'g');
$$;

create or replace function public._wa_inbox_json(p_inbox uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', i.id, 'name', i.name,
    'has_key', coalesce(i.wc_api_key,'') <> '' or (i.motor_site_id is not null and coalesce(m.wc_api_key,'') <> ''),
    'has_secret', coalesce(i.wc_hook_secret,'') <> '', 'motor', i.motor_site_id is not null, 'motor_name', m.name)
  from public.wa_inboxes i left join public.motor_sites m on m.id = i.motor_site_id where i.id = p_inbox;
$$;
revoke all on function public._wa_inbox_json(uuid) from public, anon, authenticated;

create or replace function public.wa_login(p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u public.wa_users%rowtype; tok text;
begin
  select * into u from public.wa_users where lower(username) = lower(trim(coalesce(p_username,''))) for update;
  if not found or not u.is_active then perform pg_sleep(0.4); return jsonb_build_object('ok', false, 'reason', 'bad_login'); end if;
  if u.locked_until is not null and u.locked_until > now() then
    return jsonb_build_object('ok', false, 'reason', 'locked', 'minutes', ceil(extract(epoch from (u.locked_until - now()))/60)::int);
  end if;
  if u.password_hash <> crypt(coalesce(p_password,''), u.password_hash) then
    update public.wa_users set failed_count = failed_count + 1,
           locked_until = case when failed_count + 1 >= 6 then now() + interval '15 minutes' end where id = u.id;
    return jsonb_build_object('ok', false, 'reason', 'bad_login');
  end if;
  if not exists (select 1 from public.wa_inboxes where id = u.inbox_id and is_active) then return jsonb_build_object('ok', false, 'reason', 'inactive'); end if;
  update public.wa_users set failed_count = 0, locked_until = null where id = u.id;
  delete from public.wa_sessions where user_id = u.id and expires_at < now();
  tok := encode(gen_random_bytes(24),'hex');
  insert into public.wa_sessions (token_hash, user_id, inbox_id) values (encode(digest(tok,'sha256'),'hex'), u.id, u.inbox_id);
  return jsonb_build_object('ok', true, 'token', tok);
end $$;
grant execute on function public.wa_login(text,text) to anon, authenticated;

create or replace function public.wa_logout(p_token text)
returns jsonb language sql security definer set search_path = public, extensions as $$
  delete from public.wa_sessions where token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex');
  select jsonb_build_object('ok', true);
$$;
grant execute on function public.wa_logout(text) to anon, authenticated;

-- أول مدير أساسي: برمز الإعداد
create or replace function public.wa_setup(p_code text, p_name text, p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare ib public.wa_inboxes%rowtype; uid uuid; tok text;
begin
  select * into ib from public.wa_inboxes where setup_hash = encode(digest(upper(trim(coalesce(p_code,''))),'sha256'),'hex') and setup_expires > now() for update;
  if not found then perform pg_sleep(0.4); perform public._wa_err('bad_code'); end if;
  if coalesce(trim(p_username),'') !~ '^[A-Za-z0-9._-]{3,40}$' then perform public._wa_err('bad_username'); end if;
  if length(coalesce(p_password,'')) < 6 then perform public._wa_err('weak_password'); end if;
  if exists (select 1 from public.wa_users where lower(username) = lower(trim(p_username))) then perform public._wa_err('username_taken'); end if;
  insert into public.wa_users (inbox_id, name, username, password_hash, role)
  values (ib.id, coalesce(nullif(trim(p_name),''), trim(p_username)), trim(p_username), crypt(p_password, gen_salt('bf')), 'main') returning id into uid;
  update public.wa_inboxes set setup_hash = null, setup_expires = null where id = ib.id;
  tok := encode(gen_random_bytes(24),'hex');
  insert into public.wa_sessions (token_hash, user_id, inbox_id) values (encode(digest(tok,'sha256'),'hex'), uid, ib.id);
  return jsonb_build_object('ok', true, 'token', tok);
end $$;
grant execute on function public.wa_setup(text,text,text,text) to anon, authenticated;

create or replace function public.wa_me(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._wa_who(p_token);
  return jsonb_build_object('me', w, 'inbox', public._wa_inbox_json((w->>'inbox_id')::uuid),
    'users', case when w->>'role' = 'main' then coalesce((select jsonb_agg(jsonb_build_object('id', u.id, 'name', u.name, 'username', u.username, 'role', u.role, 'is_active', u.is_active) order by u.created_at)
                   from public.wa_users u where u.inbox_id = (w->>'inbox_id')::uuid), '[]'::jsonb) end,
    'unread', coalesce((select sum(unread) from public.wa_chats where inbox_id = (w->>'inbox_id')::uuid), 0));
end $$;
grant execute on function public.wa_me(text) to anon, authenticated;

-- لائحة المحادثات (الأحدث أول) — p_since: بس اللي تغيّر من بعد هالوقت
create or replace function public.wa_chats(p_token text, p_q text default '', p_since timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; q text := lower(trim(coalesce(p_q,'')));
begin
  w := public._wa_who(p_token);
  return jsonb_build_object('now', now(), 'rows', coalesce((select jsonb_agg(jsonb_build_object('phone', c.phone, 'name', c.name, 'last_text', c.last_text,
           'last_dir', c.last_dir, 'last_at', c.last_at, 'last_in_at', c.last_in_at, 'unread', c.unread) order by c.last_at desc)
         from (select * from public.wa_chats c where c.inbox_id = (w->>'inbox_id')::uuid
                 and (p_since is null or c.last_at > p_since - interval '15 seconds')   -- هامش للرسائل اللي انحفظت بنفس اللحظة
                 and (q = '' or lower(c.name) like '%' || q || '%' or c.phone like '%' || public._wa_digits(q) || '%' and public._wa_digits(q) <> '')
               order by c.last_at desc limit 500) c), '[]'::jsonb));
end $$;
grant execute on function public.wa_chats(text,text,timestamptz) to anon, authenticated;

-- رسائل محادثة: آخر 80 (أو الأقدم من p_before، أو الأحدث من p_after) — وبتصفّر عدّاد غير المقروء
create or replace function public.wa_messages(p_token text, p_phone text, p_before bigint default null, p_after bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; ib uuid; ph text := public._wa_digits(p_phone);
begin
  w := public._wa_who(p_token); ib := (w->>'inbox_id')::uuid;
  update public.wa_chats set unread = 0 where inbox_id = ib and phone = ph and unread <> 0;
  return jsonb_build_object('chat', (select jsonb_build_object('phone', c.phone, 'name', c.name, 'last_in_at', c.last_in_at) from public.wa_chats c where c.inbox_id = ib and c.phone = ph),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'dir', m.dir, 'type', m.type, 'text', m.text, 'media_url', m.media_url,
                 'status', m.status, 'by', m.by_name, 'at', m.created_at) order by m.id)
       from (select * from public.wa_msgs m where m.inbox_id = ib and m.phone = ph
               and (p_before is null or m.id < p_before) and (p_after is null or m.id > p_after)
             order by m.id desc limit 80) m), '[]'::jsonb));
end $$;
grant execute on function public.wa_messages(text,text,bigint,bigint) to anon, authenticated;

-- إعدادات الصندوق (المدير الأساسي): الاسم + مفتاح WhatChimp + سرّ الـwebhook (المفاتيح بتنكتب بس، ما بتنقرا)
create or replace function public.wa_settings_save(p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; d jsonb := coalesce(p_data,'{}'::jsonb);
begin
  w := public._wa_who(p_token);
  if w->>'role' <> 'main' then perform public._wa_err('forbidden'); end if;
  update public.wa_inboxes set
    name = case when d ? 'name' then left(trim(d->>'name'), 80) else name end,
    wc_api_key = case when coalesce(trim(d->>'wc_api_key'),'') <> '' then trim(d->>'wc_api_key') when d ? 'clear_key' then null else wc_api_key end,
    wc_hook_secret = case when coalesce(trim(d->>'wc_hook_secret'),'') <> '' then trim(d->>'wc_hook_secret') else wc_hook_secret end
   where id = (w->>'inbox_id')::uuid;
  return public._wa_inbox_json((w->>'inbox_id')::uuid);
end $$;
grant execute on function public.wa_settings_save(text,jsonb) to anon, authenticated;

-- المستخدمين (المدير الأساسي)
create or replace function public.wa_user_save(p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare w jsonb; d jsonb := coalesce(p_data,'{}'::jsonb); u public.wa_users%rowtype; ib uuid;
begin
  w := public._wa_who(p_token); ib := (w->>'inbox_id')::uuid;
  if w->>'role' <> 'main' then perform public._wa_err('forbidden'); end if;
  if coalesce(trim(d->>'username'),'') !~ '^[A-Za-z0-9._-]{3,40}$' then perform public._wa_err('bad_username'); end if;
  if coalesce(d->>'role','admin') not in ('main','admin') then perform public._wa_err('bad_role'); end if;
  if exists (select 1 from public.wa_users where lower(username) = lower(trim(d->>'username')) and id::text <> coalesce(d->>'id','')) then perform public._wa_err('username_taken'); end if;
  if coalesce(d->>'id','') = '' then
    if length(coalesce(d->>'password','')) < 6 then perform public._wa_err('weak_password'); end if;
    insert into public.wa_users (inbox_id, name, username, password_hash, role)
    values (ib, coalesce(nullif(trim(d->>'name'),''), trim(d->>'username')), trim(d->>'username'), crypt(d->>'password', gen_salt('bf')), coalesce(d->>'role','admin'))
    returning * into u;
  else
    select * into u from public.wa_users where id = (d->>'id')::uuid and inbox_id = ib for update;
    if not found then perform public._wa_err('not_found'); end if;
    -- ما منشيل آخر مدير أساسي
    if u.role = 'main' and (coalesce(d->>'role','main') <> 'main' or not coalesce((d->>'is_active')::boolean, true))
       and not exists (select 1 from public.wa_users x where x.inbox_id = ib and x.role = 'main' and x.is_active and x.id <> u.id) then
      perform public._wa_err('last_main');
    end if;
    if coalesce(d->>'password','') <> '' and length(d->>'password') < 6 then perform public._wa_err('weak_password'); end if;
    update public.wa_users set name = coalesce(nullif(trim(d->>'name'),''), name), username = trim(d->>'username'),
           role = coalesce(d->>'role', role), is_active = coalesce((d->>'is_active')::boolean, is_active),
           password_hash = case when coalesce(d->>'password','') <> '' then crypt(d->>'password', gen_salt('bf')) else password_hash end,
           failed_count = 0, locked_until = null
     where id = u.id returning * into u;
    if not u.is_active or coalesce(d->>'password','') <> '' then delete from public.wa_sessions where user_id = u.id and u.id::text <> w->>'user_id'; end if;
  end if;
  return jsonb_build_object('ok', true, 'id', u.id);
end $$;
grant execute on function public.wa_user_save(text,jsonb) to anon, authenticated;

create or replace function public.wa_user_delete(p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._wa_who(p_token);
  if w->>'role' <> 'main' then perform public._wa_err('forbidden'); end if;
  if p_id::text = w->>'user_id' then perform public._wa_err('self'); end if;
  delete from public.wa_users where id = p_id and inbox_id = (w->>'inbox_id')::uuid;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.wa_user_delete(text,uuid) to anon, authenticated;

-- ===== للـworker بس (مفتاح الخدمة) =====

-- حفظ رسالة (واردة/صادرة) + تحديث المحادثة
create or replace function public.wa_ingest(p_inbox uuid, p_dir text, p_phone text, p_name text, p_type text, p_text text,
  p_media text default '', p_ext text default '', p_by text default '', p_status text default '', p_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ph text := public._wa_digits(p_phone); mid bigint; at_ timestamptz := coalesce(p_at, now()); preview text;
begin
  if ph = '' or p_dir not in ('in','out') then return jsonb_build_object('ok', false); end if;
  -- رسالة صادرة ما إلها id: إذا نفس النص انبعت لنفس الرقم من شوي (من التطبيق) ما منكرّرها
  if p_dir = 'out' and exists (select 1 from public.wa_msgs where inbox_id = p_inbox and phone = ph and dir = 'out'
        and text = coalesce(p_text,'') and created_at > now() - interval '3 minutes'
        and (coalesce(p_ext,'') = '' or ext_id = '' or ext_id = p_ext)) then
    if coalesce(p_ext,'') <> '' then
      update public.wa_msgs set ext_id = p_ext where id = (select id from public.wa_msgs where inbox_id = p_inbox and phone = ph and dir = 'out'
        and text = coalesce(p_text,'') and ext_id = '' and created_at > now() - interval '3 minutes' order by id desc limit 1)
        and not exists (select 1 from public.wa_msgs where inbox_id = p_inbox and ext_id = p_ext);
    end if;
    return jsonb_build_object('ok', true, 'dup', true);
  end if;
  insert into public.wa_msgs (inbox_id, phone, dir, type, text, media_url, ext_id, by_name, status, created_at)
  values (p_inbox, ph, p_dir, coalesce(nullif(p_type,''),'text'), left(coalesce(p_text,''), 4000), left(coalesce(p_media,''), 1000),
          left(coalesce(p_ext,''), 200), left(coalesce(p_by,''), 80), left(coalesce(p_status,''), 20), at_)
  on conflict (inbox_id, ext_id) where ext_id <> '' do nothing
  returning id into mid;
  if mid is null then return jsonb_build_object('ok', true, 'dup', true); end if;
  preview := case when coalesce(p_text,'') <> '' then left(p_text, 140) else '[' || coalesce(nullif(p_type,''),'media') || ']' end;
  insert into public.wa_chats as c (inbox_id, phone, name, last_text, last_dir, last_at, last_in_at, unread)
  values (p_inbox, ph, coalesce(p_name,''), preview, p_dir, at_, case when p_dir = 'in' then at_ end, case when p_dir = 'in' then 1 else 0 end)
  on conflict (inbox_id, phone) do update set
    name = case when coalesce(excluded.name,'') <> '' and p_dir = 'in' then excluded.name else c.name end,
    last_text = excluded.last_text, last_dir = excluded.last_dir, last_at = greatest(c.last_at, excluded.last_at),
    last_in_at = case when p_dir = 'in' then greatest(coalesce(c.last_in_at, at_), at_) else c.last_in_at end,
    unread = case when p_dir = 'in' then c.unread + 1 else c.unread end;
  return jsonb_build_object('ok', true, 'id', mid);
end $$;
revoke all on function public.wa_ingest(uuid,text,text,text,text,text,text,text,text,text,timestamptz) from public, anon, authenticated;
grant execute on function public.wa_ingest(uuid,text,text,text,text,text,text,text,text,text,timestamptz) to service_role;

create or replace function public.wa_status(p_inbox uuid, p_ext text, p_status text)
returns void language sql security definer set search_path = public as $$
  update public.wa_msgs set status = left(coalesce(p_status,''),20) where inbox_id = p_inbox and ext_id = p_ext and coalesce(p_ext,'') <> '';
$$;
revoke all on function public.wa_status(uuid,text,text) from public, anon, authenticated;
grant execute on function public.wa_status(uuid,text,text) to service_role;

-- سياق الإرسال: مين المستخدم + مفتاح WhatChimp (أو مفتاح برنامج الموتير المربوط)
create or replace function public.wa_send_ctx(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; k text;
begin
  w := public._wa_who(p_token);
  select coalesce(nullif(i.wc_api_key,''), m.wc_api_key) into k from public.wa_inboxes i left join public.motor_sites m on m.id = i.motor_site_id
   where i.id = (w->>'inbox_id')::uuid;
  return w || jsonb_build_object('key', coalesce(k,''));
end $$;
revoke all on function public.wa_send_ctx(text) from public, anon, authenticated;
grant execute on function public.wa_send_ctx(text) to service_role;

-- الـwebhook: سرّ التوقيع للصندوق
create or replace function public.wa_hook_ctx(p_inbox uuid)
returns jsonb language sql security definer set search_path = public as $$
  select jsonb_build_object('id', i.id, 'secret', coalesce(i.wc_hook_secret,''), 'active', i.is_active)
  from public.wa_inboxes i where i.id = p_inbox;
$$;
revoke all on function public.wa_hook_ctx(uuid) from public, anon, authenticated;
grant execute on function public.wa_hook_ctx(uuid) to service_role;

-- صندوق مربوط ببرنامج موتير (رسائل الـwebhook تبع الموتير بتنحفظ فيه كمان)
create or replace function public.wa_inbox_for_motor(p_site uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.wa_inboxes where motor_site_id = p_site and is_active limit 1;
$$;
revoke all on function public.wa_inbox_for_motor(uuid) from public, anon, authenticated;
grant execute on function public.wa_inbox_for_motor(uuid) to service_role;

-- إنشاء صندوق جديد + رمز إعداد (للمشرف على LibanApps — من SQL أو لوحة الإدارة)
create or replace function public.wa_inbox_create(p_name text, p_motor_site uuid default null, p_client uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare iid uuid; code text;
begin
  code := upper(substr(encode(gen_random_bytes(6),'hex'), 1, 8));
  insert into public.wa_inboxes (name, motor_site_id, client_id, setup_hash, setup_expires)
  values (coalesce(nullif(trim(p_name),''),'WhatsApp'), p_motor_site, p_client, encode(digest(code,'sha256'),'hex'), now() + interval '30 days')
  returning id into iid;
  return jsonb_build_object('id', iid, 'setup_code', code);
end $$;
revoke all on function public.wa_inbox_create(text,uuid,uuid) from public, anon, authenticated;

create or replace function public.wa_inbox_new_code(p_inbox uuid)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare code text;
begin
  code := upper(substr(encode(gen_random_bytes(6),'hex'), 1, 8));
  update public.wa_inboxes set setup_hash = encode(digest(code,'sha256'),'hex'), setup_expires = now() + interval '30 days' where id = p_inbox;
  return code;
end $$;
revoke all on function public.wa_inbox_new_code(uuid) from public, anon, authenticated;
