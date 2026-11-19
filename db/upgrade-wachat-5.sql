-- ============================================================
--  LibanApps Chat (5): الشراء من داخل التطبيق (الموبايل) — رمز الإعداد بيشتغل قبل الشراء، والقفل بعد الدخول
-- ============================================================

-- سياق الشراء: دخول بلا شرط الاشتراك
create or replace function public.wa_buy_ctx(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.wa_sessions%rowtype; u public.wa_users%rowtype; ib public.wa_inboxes%rowtype; c public.clients%rowtype;
begin
  select * into s from public.wa_sessions where token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex') and expires_at > now();
  if not found then perform public._wa_err('auth'); end if;
  select * into u from public.wa_users where id = s.user_id;
  select * into ib from public.wa_inboxes where id = s.inbox_id;
  if not u.is_active or not ib.is_active then perform public._wa_err('auth'); end if;
  select * into c from public.clients where id = ib.client_id;
  return jsonb_build_object('inbox_id', ib.id, 'role', u.role, 'client_id', c.id, 'user_id', c.user_id,
    'licensed', public._wa_licensed(ib.id),
    'plan', (select jsonb_build_object('id', id, 'price', price_usd, 'days', days, 'name', name_ar) from public.plans
              where product_code = 'chat' and is_active and price_usd > 0 limit 1));
end $$;
revoke all on function public.wa_buy_ctx(text) from public, anon, authenticated;
grant execute on function public.wa_buy_ctx(text) to service_role;

-- رمز الإعداد ما بقى بدو شراء (القفل بيطلع بعد الدخول مع زر الشراء)
do $$
declare d text;
begin
  select pg_get_functiondef('public.wa_setup(text,text,text,text)'::regprocedure) into d;
  if position('_wa_licensed' in d) > 0 then
    d := regexp_replace(d, 'if not public\._wa_licensed\(ib\.id\) then perform public\._wa_err\(''no_license''\); end if;\s*', '');
    execute d;
  end if;
end $$;

-- صفحة الحساب: الصندوق + رمز الإعداد دايماً، مع حالة الشراء
create or replace function public.wa_my_inbox(p_new_code boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare cid uuid; ib public.wa_inboxes%rowtype; code text; cname text; has_main boolean;
begin
  select id, name into cid, cname from public.clients where user_id = auth.uid() limit 1;
  if cid is null then perform public._wa_err('auth'); end if;
  select * into ib from public.wa_inboxes where client_id = cid order by created_at limit 1;
  if not found then
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
  return jsonb_build_object('licensed', public._wa_licensed(ib.id), 'id', ib.id, 'name', ib.name, 'has_main', has_main, 'setup_code', code,
    'plan', (select jsonb_build_object('id', id, 'price', price_usd, 'name', name_ar) from public.plans where product_code = 'chat' and is_active limit 1),
    'users', (select count(*) from public.wa_users where inbox_id = ib.id),
    'chats', (select count(*) from public.wa_chats where inbox_id = ib.id));
end $$;
revoke all on function public.wa_my_inbox(boolean) from public, anon;
grant execute on function public.wa_my_inbox(boolean) to authenticated;
