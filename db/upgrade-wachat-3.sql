-- ============================================================
--  LibanApps Chat (3): استيراد المحادثات القديمة من WhatChimp
--  (الـworker بيقرا GET /v1/conversations و /v1/conversations/{id}/messages وبيبعتها لهون)
-- ============================================================
alter table public.wa_inboxes add column if not exists history_done boolean not null default false;
alter table public.wa_inboxes add column if not exists history_count int not null default 0;

-- إعادة حساب سطر المحادثة من رسائلها
create or replace function public._wa_chat_refresh(p_inbox uuid, p_phone text, p_name text default '', p_unread int default null)
returns void language plpgsql security definer set search_path = public as $$
declare l public.wa_msgs%rowtype; lin timestamptz;
begin
  select * into l from public.wa_msgs where inbox_id = p_inbox and phone = p_phone order by created_at desc, id desc limit 1;
  if not found then return; end if;
  select max(created_at) into lin from public.wa_msgs where inbox_id = p_inbox and phone = p_phone and dir = 'in';
  insert into public.wa_chats as c (inbox_id, phone, name, last_text, last_dir, last_at, last_in_at, unread)
  values (p_inbox, p_phone, coalesce(p_name,''), case when l.text <> '' then left(l.text, 140) else '[' || l.type || ']' end, l.dir, l.created_at, lin, coalesce(p_unread, 0))
  on conflict (inbox_id, phone) do update set
    name = case when c.name = '' then excluded.name else c.name end,
    last_text = excluded.last_text, last_dir = excluded.last_dir, last_at = excluded.last_at, last_in_at = excluded.last_in_at,
    unread = coalesce(p_unread, c.unread);
end $$;
revoke all on function public._wa_chat_refresh(uuid,text,text,int) from public, anon, authenticated;

-- رسائل محادثة وحدة دفعة وحدة (بلا تكرار: ext_id = id الرسالة عند WhatChimp)
create or replace function public.wa_ingest_many(p_inbox uuid, p_phone text, p_name text, p_items jsonb, p_unread int default null)
returns int language plpgsql security definer set search_path = public as $$
declare n int; ph text := public._wa_digits(p_phone);
begin
  if ph = '' then return 0; end if;
  insert into public.wa_msgs (inbox_id, phone, dir, type, text, media_url, ext_id, by_name, status, created_at)
  select p_inbox, ph, it->>'dir', coalesce(nullif(it->>'type',''),'text'), left(coalesce(it->>'text',''), 4000), left(coalesce(it->>'media',''), 1000),
         left(coalesce(it->>'ext',''), 200), left(coalesce(it->>'by',''), 80), left(coalesce(it->>'status',''), 20), coalesce((it->>'at')::timestamptz, now())
    from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) it
   where it->>'dir' in ('in','out') and coalesce(it->>'ext','') <> ''
   order by (it->>'at')::timestamptz
  on conflict (inbox_id, ext_id) where ext_id <> '' do nothing;
  get diagnostics n = row_count;
  perform public._wa_chat_refresh(p_inbox, ph, p_name, p_unread);
  update public.wa_inboxes set history_count = history_count + n where id = p_inbox;
  return n;
end $$;
revoke all on function public.wa_ingest_many(uuid,text,text,jsonb,int) from public, anon, authenticated;
grant execute on function public.wa_ingest_many(uuid,text,text,jsonb,int) to service_role;

-- بداية/نهاية الاستيراد. بالنهاية منرتّب أرقام الرسائل حسب الوقت (العرض بيمشي على الرقم)
create or replace function public.wa_history_mark(p_inbox uuid, p_done boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not p_done then
    update public.wa_inboxes set history_done = false, history_count = 0 where id = p_inbox;
    return jsonb_build_object('ok', true);
  end if;
  create temp table if not exists _wa_resort (like public.wa_msgs) on commit drop;
  delete from _wa_resort;
  insert into _wa_resort select * from public.wa_msgs where inbox_id = p_inbox;
  delete from public.wa_msgs where inbox_id = p_inbox;
  insert into public.wa_msgs (inbox_id, phone, dir, type, text, media_url, ext_id, status, by_name, created_at)
  select inbox_id, phone, dir, type, text, media_url, ext_id, status, by_name, created_at from _wa_resort order by created_at, id;
  update public.wa_inboxes set history_done = true where id = p_inbox;
  return jsonb_build_object('ok', true, 'count', (select history_count from public.wa_inboxes where id = p_inbox));
end $$;
revoke all on function public.wa_history_mark(uuid,boolean) from public, anon, authenticated;
grant execute on function public.wa_history_mark(uuid,boolean) to service_role;

create or replace function public._wa_inbox_json(p_inbox uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', i.id, 'name', i.name,
    'has_key', coalesce(i.wc_api_key,'') <> '' or (i.motor_site_id is not null and coalesce(m.wc_api_key,'') <> ''),
    'has_secret', coalesce(i.wc_hook_secret,'') <> '', 'motor', i.motor_site_id is not null, 'motor_name', m.name,
    'history_done', i.history_done, 'history_count', i.history_count)
  from public.wa_inboxes i left join public.motor_sites m on m.id = i.motor_site_id where i.id = p_inbox;
$$;

-- الرسائل المركّبة من فواتير/إيصالات البرنامج بتنشال، لأن WhatChimp عندو النسخة الحقيقية
delete from public.wa_msgs where ext_id like 'inv-%' or ext_id like 'pay-%';
delete from public.wa_chats c where not exists (select 1 from public.wa_msgs m where m.inbox_id = c.inbox_id and m.phone = c.phone);
drop table if exists public.tmp_wc_spec;
