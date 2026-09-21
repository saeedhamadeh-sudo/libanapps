-- ============================================================
--  ترقية: تجديد الاشتراك
--  التجديد بيمدّد الاشتراك الموجود — ما بيعمل مطعماً جديداً
--  شغّله لحاله — لا يحذف أي بيانات
-- ============================================================

alter table public.purchases add column if not exists renew_of uuid
  references public.subscriptions(id) on delete set null;

-- ---------- بدء تجديد ----------
create or replace function public.start_renewal(p_plan uuid, p_sub uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pl public.plans%rowtype; s public.subscriptions%rowtype; cid uuid; pid bigint;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;

  select id into cid from public.clients where user_id = auth.uid();
  if cid is null then raise exception 'no client'; end if;

  select * into s from public.subscriptions where id = p_sub and client_id = cid;
  if not found then raise exception 'subscription not found'; end if;

  select * into pl from public.plans where id = p_plan and is_active;
  if not found then raise exception 'plan not found'; end if;
  if pl.product_code <> s.product_code then raise exception 'plan/product mismatch'; end if;

  insert into public.purchases (user_id, client_id, plan_id, product_code,
                               amount_usd, days, slug, biz_name, renew_of)
  values (auth.uid(), cid, pl.id, pl.product_code,
          pl.price_usd, pl.days, coalesce(s.ref_slug,''), '', s.id)
  returning id into pid;

  return jsonb_build_object('purchase_id', pid, 'amount', pl.price_usd);
end $$;

-- ---------- التفعيل: تجديد أو اشتراك جديد ----------
create or replace function public.provision_purchase(p_id bigint, p_txn text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.purchases%rowtype; s public.subscriptions; r public.restaurants%rowtype;
        c public.clients%rowtype; old public.subscriptions%rowtype;
begin
  select * into p from public.purchases where id = p_id;
  if not found then raise exception 'purchase not found'; end if;
  if p.status = 'paid' then
    return jsonb_build_object('ok', true, 'already', true, 'subscription_id', p.subscription_id);
  end if;

  -- ===== تجديد =====
  if p.renew_of is not null then
    select * into old from public.subscriptions where id = p.renew_of;
    if not found then raise exception 'subscription to renew not found'; end if;

    update public.subscriptions
       set expires_at = greatest(expires_at, now()) + make_interval(days => greatest(1, p.days)),
           status     = 'active',
           plan       = case when p.days <= 7 then 'trial'
                             when p.days <= 31 then 'monthly' else 'yearly' end,
           price_usd  = p.amount_usd
     where id = old.id
    returning * into s;

    update public.purchases
       set status='paid', paid_at=now(), whish_txn_id=p_txn, subscription_id=s.id
     where id = p.id;

    return jsonb_build_object('ok', true, 'renewed', true, 'key', s.key,
                              'expires_at', s.expires_at, 'product', s.product_code);
  end if;

  -- ===== اشتراك جديد =====
  select * into c from public.clients where id = p.client_id;

  if p.product_code = 'menu' then
    insert into public.restaurants (client_id, slug, name_ar, name_en, phone, whatsapp)
    values (p.client_id, p.slug,
            coalesce(nullif(p.biz_name,''), p.slug),
            coalesce(nullif(p.biz_name,''), p.slug),
            coalesce(c.phone,''), regexp_replace(coalesce(c.phone,''),'\D','','g'))
    returning * into r;

    insert into public.restaurant_users (user_id, restaurant_id, role)
    values (p.user_id, r.id, 'owner') on conflict do nothing;

    insert into public.categories (restaurant_id, name_ar, name_en, sort)
    values (r.id, 'الأصناف', 'Menu', 1);
  end if;

  insert into public.subscriptions (client_id, product_code, key, plan, expires_at,
                                    price_usd, ref_slug, notes)
  values (p.client_id, p.product_code, public.gen_license_key(p.product_code),
          case when p.days <= 7 then 'trial' when p.days <= 31 then 'monthly' else 'yearly' end,
          now() + make_interval(days => greatest(1, p.days)),
          p.amount_usd, coalesce(p.slug,''), 'شراء ذاتي #' || p.id)
  returning * into s;

  update public.purchases
     set status='paid', paid_at=now(), whish_txn_id=p_txn, subscription_id=s.id
   where id = p.id;

  return jsonb_build_object('ok', true, 'key', s.key, 'expires_at', s.expires_at,
                            'slug', coalesce(p.slug,''), 'product', p.product_code);
end $$;

-- ---------- اشتراك المطعم الحالي (للوحة صاحب المطعم) ----------
create or replace function public.restaurant_subscription(rid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v timestamptz; s public.subscriptions%rowtype; r public.restaurants%rowtype;
begin
  if not public.is_member(rid) then raise exception 'not allowed'; end if;
  select * into r from public.restaurants where id = rid;
  v := public.license_until(rid);

  select * into s from public.subscriptions
   where product_code = 'menu' and ref_slug = r.slug
   order by expires_at desc limit 1;

  return jsonb_build_object(
    'expires_at', v,
    'days_left',  greatest(0, ceil(extract(epoch from (v - now()))/86400))::int,
    'active',     v > now(),
    'subscription_id', s.id,
    'plan', s.plan,
    'can_renew', (s.id is not null)
  );
end $$;
