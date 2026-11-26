-- LibanApps Chat (7): حذف محادثة من الصندوق (المدير الأساسي). ما بتنمحى من واتساب نفسه.
create table if not exists public.wa_chat_dels (
  inbox_id uuid not null references public.wa_inboxes(id) on delete cascade,
  phone text not null,
  at timestamptz not null default now(),
  primary key (inbox_id, phone)
);
alter table public.wa_chat_dels enable row level security;

create or replace function public.wa_chat_delete(p_token text, p_phone text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; ib uuid; ph text := public._wa_digits(p_phone); n int;
begin
  w := public._wa_who(p_token); ib := (w->>'inbox_id')::uuid;
  if w->>'role' <> 'main' then perform public._wa_err('forbidden'); end if;
  if ph = '' then perform public._wa_err('bad_phone'); end if;
  delete from public.wa_msgs where inbox_id = ib and phone = ph;
  get diagnostics n = row_count;
  delete from public.wa_chats where inbox_id = ib and phone = ph;
  insert into public.wa_chat_dels (inbox_id, phone) values (ib, ph) on conflict (inbox_id, phone) do update set at = now();
  return jsonb_build_object('ok', true, 'deleted', n);
end $$;
revoke all on function public.wa_chat_delete(text,text) from public;
grant execute on function public.wa_chat_delete(text,text) to anon, authenticated;

-- المزامنة: المحادثات المحذوفة من وقت آخر سحب، لتنشال من باقي الأجهزة
do $$
declare d text;
begin
  select pg_get_functiondef('public.wa_chats(text,text,timestamptz)'::regprocedure) into d;
  if position('wa_chat_dels' in d) = 0 then
    d := replace(d, E'return jsonb_build_object(''now'', now(), ''rows'',',
      E'return jsonb_build_object(''now'', now(),\n    ''deleted'', coalesce((select jsonb_agg(x.phone) from public.wa_chat_dels x where x.inbox_id = (w->>''inbox_id'')::uuid and p_since is not null and x.at > p_since - interval ''15 seconds''\n                 and not exists (select 1 from public.wa_chats c2 where c2.inbox_id = x.inbox_id and c2.phone = x.phone)), ''[]''::jsonb),\n    ''rows'',');
    if position('wa_chat_dels' in d) = 0 then raise exception 'patch'; end if;
    execute d;
  end if;
end $$;

-- استيراد المحادثات القديمة ما بيرجّع رسائل محادثة محذوفة (بس الرسائل الأجدد من وقت الحذف)
do $$
declare d text;
begin
  select pg_get_functiondef('public.wa_ingest_many(uuid,text,text,jsonb,integer)'::regprocedure) into d;
  if position('wa_chat_dels' in d) = 0 then
    d := replace(d, E'   where it->>''dir'' in (''in'',''out'') and coalesce(it->>''ext'','''') <> ''''',
      E'   where it->>''dir'' in (''in'',''out'') and coalesce(it->>''ext'','''') <> ''''\n     and not exists (select 1 from public.wa_chat_dels x where x.inbox_id = p_inbox and x.phone = ph and coalesce((it->>''at'')::timestamptz, now()) <= x.at)');
    if position('wa_chat_dels' in d) = 0 then raise exception 'ingest patch'; end if;
    execute d;
  end if;
end $$;
