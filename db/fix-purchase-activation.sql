-- ============================================================
--  إصلاحات الشراء
--   ١) تفعيل يدوي من لوحتك لأي عملية شراء
--   ٢) إعادة محاولة الدفع بعملية جديدة (روابط Whish تنتهي)
--   ٣) حارس: التفعيل للسيرفر أو للمشرف فقط
--  آمن للتشغيل أكثر من مرة
-- ============================================================

-- ---------- حارس على التفعيل ----------
--  السيرفر بينادي بمفتاح الخدمة (auth.uid() فاضية) → مسموح
--  وأي مستخدم مسجّل لازم يكون مشرف منصة
create or replace function public.provision_purchase(p_id bigint, p_txn text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.purchases%rowtype; s public.subscriptions; r public.restaurants%rowtype;
        c public.clients%rowtype; old public.subscriptions%rowtype;
begin
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'not allowed';
  end if;

  select * into p from public.purchases where id = p_id;
  if not found then raise exception 'purchase not found'; end if;
  if p.status = 'paid' then
    return jsonb_build_object('ok', true, 'already', true, 'subscription_id', p.subscription_id);
  end if;

  -- تجديد اشتراك قائم
  if p.renew_of is not null then
    select * into old from public.subscriptions where id = p.renew_of;
    if not found then raise exception 'subscription to renew not found'; end if;

    update public.subscriptions
       set expires_at = greatest(expires_at, now()) + make_interval(days => greatest(1, p.days)),
           status = 'active',
           plan = case when p.days <= 7 then 'trial'
                       when p.days <= 31 then 'monthly' else 'yearly' end,
           price_usd = p.amount_usd
     where id = old.id
    returning * into s;

    update public.purchases
       set status='paid', paid_at=now(), whish_txn_id=p_txn, subscription_id=s.id
     where id = p.id;

    return jsonb_build_object('ok', true, 'renewed', true, 'key', s.key,
                              'expires_at', s.expires_at, 'product', s.product_code);
  end if;

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
          p.amount_usd, coalesce(p.slug,''), 'شراء #' || p.id)
  returning * into s;

  update public.purchases
     set status='paid', paid_at=now(), whish_txn_id=p_txn, subscription_id=s.id
   where id = p.id;

  return jsonb_build_object('ok', true, 'key', s.key, 'expires_at', s.expires_at,
                            'slug', coalesce(p.slug,''), 'product', p.product_code);
end $$;

-- ---------- إعادة محاولة الدفع ----------
--  روابط Whish صالحة لمرة واحدة، فمنعمل عملية جديدة برقم جديد
create or replace function public.retry_purchase(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.purchases%rowtype; nid bigint;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;

  select * into p from public.purchases where id = p_id;
  if not found then raise exception 'not found'; end if;
  if p.user_id <> auth.uid() and not public.is_admin() then raise exception 'not allowed'; end if;
  if p.status = 'paid' then
    return jsonb_build_object('ok', false, 'reason', 'مدفوعة أصلاً');
  end if;

  insert into public.purchases (user_id, client_id, plan_id, product_code, amount_usd,
                                days, slug, biz_name, renew_of)
  values (p.user_id, p.client_id, p.plan_id, p.product_code, p.amount_usd,
          p.days, p.slug, p.biz_name, p.renew_of)
  returning id into nid;

  update public.purchases set status = 'cancelled' where id = p.id;

  return jsonb_build_object('ok', true, 'purchase_id', nid);
end $$;

-- ---------- عرض المشتريات المعلّقة (للوحتك) ----------
create or replace function public.pending_purchases()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', p.id, 'client', c.name, 'phone', c.phone,
      'product', p.product_code, 'amount', p.amount_usd,
      'status', p.status, 'slug', p.slug, 'created_at', p.created_at,
      'plan_name', pl.name_ar, 'is_renewal', (p.renew_of is not null)
    ) as x
    from public.purchases p
    join public.clients c on c.id = p.client_id
    join public.plans pl on pl.id = p.plan_id
    where p.status in ('pending','awaiting_payment') and public.is_admin()
  ) t;
$$;
