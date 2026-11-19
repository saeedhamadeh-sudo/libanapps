-- LibanApps Chat (6): لائحة المشتركين بلوحة /super
create or replace function public.admin_chat_list()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(x order by (x->>'sub_at') desc nulls last, x->>'client') from (
    select jsonb_build_object(
      'client_id', c.id, 'client', c.name, 'business', c.business, 'phone', c.phone,
      'sub_id', s.id, 'status', s.status, 'sub_at', s.created_at, 'price', s.price_usd, 'notes', s.notes,
      'active', (s.status = 'active' and s.expires_at > now()),
      'inbox', i.name, 'inbox_at', i.created_at,
      'users', (select count(*) from public.wa_users u where u.inbox_id = i.id),
      'chats', (select count(*) from public.wa_chats ch where ch.inbox_id = i.id),
      'last_at', (select max(last_at) from public.wa_chats ch where ch.inbox_id = i.id)) as x
    from public.clients c
    left join lateral (select * from public.subscriptions s where s.client_id = c.id and s.product_code = 'chat' order by s.expires_at desc limit 1) s on true
    left join lateral (select * from public.wa_inboxes i where i.client_id = c.id order by i.created_at limit 1) i on true
    where s.id is not null or i.id is not null) t), '[]'::jsonb);
end $$;
revoke all on function public.admin_chat_list() from public, anon;
grant execute on function public.admin_chat_list() to authenticated;
