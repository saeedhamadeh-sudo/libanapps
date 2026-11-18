-- ============================================================
--  LibanApps Chat (2): صندوق لكل زبون من حسابو + الوسائط (صوت/صورة/فيديو) + سجلّ تشخيص
-- ============================================================

-- ملفات الوسائط اللي منبعتها (WhatChimp بدها رابط عام للملف)
insert into storage.buckets (id, name, public, file_size_limit)
values ('wachat', 'wachat', true, 16777216)
on conflict (id) do update set public = true, file_size_limit = 16777216;

-- سجلّ تشخيص (آخر أحداث الـwebhook وردود WhatChimp) — للخدمة بس
create table if not exists public.wa_debug (
  id         bigserial primary key,
  inbox_id   uuid,
  kind       text not null default '',
  body       text not null default '',
  created_at timestamptz not null default now()
);
alter table public.wa_debug enable row level security;
revoke all on public.wa_debug from anon, authenticated;

create or replace function public.wa_debug_log(p_inbox uuid, p_kind text, p_body text)
returns void language sql security definer set search_path = public as $$
  insert into public.wa_debug (inbox_id, kind, body) values (p_inbox, left(coalesce(p_kind,''),40), left(coalesce(p_body,''), 20000));
  delete from public.wa_debug where id < (select coalesce(max(id),0) - 300 from public.wa_debug);
$$;
revoke all on function public.wa_debug_log(uuid,text,text) from public, anon, authenticated;
grant execute on function public.wa_debug_log(uuid,text,text) to service_role;

-- صندوق صاحب الحساب (زبون LibanApps): بينعمل تلقائياً أول مرة، وبيرجّع رمز إعداد إذا بعد ما في مدير أساسي
create or replace function public.wa_my_inbox(p_new_code boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare cid uuid; ib public.wa_inboxes%rowtype; code text; cname text; has_main boolean;
begin
  select id, name into cid, cname from public.clients where user_id = auth.uid() limit 1;
  if cid is null then perform public._wa_err('auth'); end if;
  select * into ib from public.wa_inboxes where client_id = cid order by created_at limit 1;
  if not found then
    -- عندو برنامج مولّد مربوط بصندوق؟ منربطو بالحساب
    select i.* into ib from public.wa_inboxes i join public.motor_sites m on m.id = i.motor_site_id where m.client_id = cid limit 1;
    if found then update public.wa_inboxes set client_id = cid where id = ib.id;
    else
      insert into public.wa_inboxes (name, client_id, motor_site_id)
      values (coalesce(nullif(cname,''),'WhatsApp'), cid, (select id from public.motor_sites where client_id = cid limit 1))
      returning * into ib;
    end if;
  end if;
  has_main := exists (select 1 from public.wa_users where inbox_id = ib.id and role = 'main' and is_active);
  if not has_main or p_new_code then
    code := upper(substr(encode(gen_random_bytes(6),'hex'), 1, 8));
    update public.wa_inboxes set setup_hash = encode(digest(code,'sha256'),'hex'), setup_expires = now() + interval '30 days' where id = ib.id;
  end if;
  return jsonb_build_object('id', ib.id, 'name', ib.name, 'has_main', has_main, 'setup_code', code,
    'users', (select count(*) from public.wa_users where inbox_id = ib.id),
    'chats', (select count(*) from public.wa_chats where inbox_id = ib.id));
end $$;
revoke all on function public.wa_my_inbox(boolean) from public, anon;
grant execute on function public.wa_my_inbox(boolean) to authenticated;
