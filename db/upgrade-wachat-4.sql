-- ============================================================
--  LibanApps Chat (4): شراء مرة وحدة — السعر من /super، وبلا اشتراك ما بيفتح الصندوق
-- ============================================================
insert into public.products (code, name_ar, name_en, prefix, is_active, trial_days)
values ('chat', 'LibanApps Chat — محادثات واتساب', 'LibanApps Chat — WhatsApp inbox', 'CHT', true, 0)
on conflict (code) do nothing;

insert into public.plans (product_code, name_ar, name_en, days, price_usd, renew_price_usd, features_ar, features_en, is_active, sort)
select 'chat', 'LibanApps Chat — شراء مرة واحدة', 'LibanApps Chat — one-time purchase', 36500, 0, null,
  array['محادثات واتساب (WhatChimp) من المتصفح وتطبيق الأندرويد',
        'إرسال واستقبال الصور والفيديو والرسائل الصوتية',
        'مدير أساسي ومدراء بصلاحيات',
        'استيراد المحادثات القديمة',
        'دفعة واحدة — بلا تجديد سنوي'],
  array['WhatsApp (WhatChimp) chats in the browser and Android app',
        'Send and receive photos, video and voice notes',
        'Main manager and managers',
        'Import old conversations',
        'Pay once — no yearly renewal'], false, 1
where not exists (select 1 from public.plans where product_code = 'chat');

-- السعر وإظهار الباقة من لوحة /super
create or replace function public.admin_chat_product(p_price numeric, p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update public.plans set price_usd = greatest(0, coalesce(p_price, price_usd)), renew_price_usd = null, days = 36500,
         is_active = coalesce(p_active, is_active) and coalesce(p_price, price_usd) > 0
   where product_code = 'chat';
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.admin_chat_product(numeric, boolean) from public, anon;
grant execute on function public.admin_chat_product(numeric, boolean) to authenticated;

-- الصندوق مشترى؟ (اشتراك chat فعّال لصاحب الصندوق)
create or replace function public._wa_licensed(p_inbox uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.wa_inboxes i join public.subscriptions s on s.client_id = i.client_id
                  where i.id = p_inbox and s.product_code = 'chat' and s.status = 'active' and s.expires_at > now());
$$;
revoke all on function public._wa_licensed(uuid) from public, anon, authenticated;

create or replace function public._wa_who(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.wa_sessions%rowtype; u public.wa_users%rowtype; ib public.wa_inboxes%rowtype;
begin
  select * into s from public.wa_sessions where token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex') and expires_at > now();
  if not found then perform public._wa_err('auth'); end if;
  select * into u from public.wa_users where id = s.user_id;
  select * into ib from public.wa_inboxes where id = s.inbox_id;
  if not u.is_active or not ib.is_active then perform public._wa_err('auth'); end if;
  if not public._wa_licensed(ib.id) then perform public._wa_err('no_license'); end if;
  return jsonb_build_object('user_id', u.id, 'inbox_id', ib.id, 'role', u.role, 'name', u.name, 'username', u.username);
end $$;
revoke all on function public._wa_who(text) from public, anon, authenticated;

-- صفحة الحساب: بلا شراء ما في رمز إعداد
create or replace function public.wa_my_inbox(p_new_code boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare cid uuid; ib public.wa_inboxes%rowtype; code text; cname text; has_main boolean; lic boolean;
begin
  select id, name into cid, cname from public.clients where user_id = auth.uid() limit 1;
  if cid is null then perform public._wa_err('auth'); end if;
  lic := exists (select 1 from public.subscriptions where client_id = cid and product_code = 'chat' and status = 'active' and expires_at > now());
  if not lic then
    return jsonb_build_object('licensed', false,
      'plan', (select jsonb_build_object('id', id, 'price', price_usd, 'name', name_ar) from public.plans where product_code = 'chat' and is_active limit 1));
  end if;
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
  return jsonb_build_object('licensed', true, 'id', ib.id, 'name', ib.name, 'has_main', has_main, 'setup_code', code,
    'users', (select count(*) from public.wa_users where inbox_id = ib.id),
    'chats', (select count(*) from public.wa_chats where inbox_id = ib.id));
end $$;
revoke all on function public.wa_my_inbox(boolean) from public, anon;
grant execute on function public.wa_my_inbox(boolean) to authenticated;

-- اشتراك الـsetup code كمان بدو شراء
do $$
declare d text;
begin
  select pg_get_functiondef('public.wa_setup(text,text,text,text)'::regprocedure) into d;
  if d is not null and position('_wa_licensed' in d) = 0 then
    d := regexp_replace(d, '(insert into public\.wa_users)', 'if not public._wa_licensed(ib.id) then perform public._wa_err(''no_license''); end if;' || chr(10) || '  \1');
    execute d;
  end if;
end $$;

-- شراء بمدة 10 سنين وأكتر = دائم
do $$
declare d text;
begin
  select pg_get_functiondef('public.provision_purchase(bigint,text)'::regprocedure) into d;
  if position('''lifetime''' in d) = 0 then
    d := replace(d, 'when p.days <= 31 then ''monthly'' else ''yearly'' end', 'when p.days <= 31 then ''monthly'' when p.days >= 3650 then ''lifetime'' else ''yearly'' end');
    execute d;
  end if;
end $$;
