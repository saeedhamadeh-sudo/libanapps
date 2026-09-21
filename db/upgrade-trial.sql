-- ============================================================
--  ترقية: تجربة مجانية ٣ أيام
--  الزبون بيبلّش تجريبي بدون دفع، وبيدفع خلالها أو بعدها
--  الدفع بيمدّد نفس الاشتراك — ما بيعمل مطعماً جديداً
-- ============================================================

alter table public.platform_settings
  add column if not exists trial_days integer not null default 3;

-- هل استعمل هذا الزبون تجربة هذا البرنامج من قبل؟
create or replace function public.trial_used(p_product text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.subscriptions s
    join public.clients c on c.id = s.client_id
    where c.user_id = auth.uid() and s.product_code = p_product
  );
$$;

-- بدء التجربة
create or replace function public.start_trial(
  p_product text, p_slug text default '', p_biz text default ''
) returns jsonb language plpgsql security definer set search_path = public as $$
declare cid uuid; s public.subscriptions; r public.restaurants%rowtype;
        c public.clients%rowtype; d integer; v_slug text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;

  select id into cid from public.clients where user_id = auth.uid();
  if cid is null then raise exception 'complete your profile first'; end if;

  if not exists (select 1 from public.products where code = p_product) then
    raise exception 'unknown product';
  end if;

  -- تجربة واحدة لكل برنامج لكل زبون
  if exists (select 1 from public.subscriptions where client_id = cid and product_code = p_product) then
    return jsonb_build_object('ok', false, 'reason', 'عندك اشتراك أو تجربة سابقة لهذا البرنامج');
  end if;

  select trial_days into d from public.platform_settings where id = 1;
  d := greatest(1, coalesce(d, 3));

  select * into c from public.clients where id = cid;
  v_slug := lower(trim(coalesce(p_slug,'')));

  if p_product = 'menu' then
    if v_slug !~ '^[a-z0-9][a-z0-9-]{1,30}$' then raise exception 'invalid slug'; end if;
    if exists (select 1 from public.restaurants where slug = v_slug) then
      return jsonb_build_object('ok', false, 'reason', 'هذا الرابط محجوز — اختار غيره');
    end if;

    insert into public.restaurants (client_id, slug, name_ar, name_en, phone, whatsapp)
    values (cid, v_slug,
            coalesce(nullif(p_biz,''), v_slug), coalesce(nullif(p_biz,''), v_slug),
            coalesce(c.phone,''), regexp_replace(coalesce(c.phone,''),'\D','','g'))
    returning * into r;

    insert into public.restaurant_users (user_id, restaurant_id, role)
    values (auth.uid(), r.id, 'owner') on conflict do nothing;

    insert into public.categories (restaurant_id, name_ar, name_en, sort)
    values (r.id, 'الأصناف', 'Menu', 1);
  end if;

  insert into public.subscriptions (client_id, product_code, key, plan, expires_at,
                                    price_usd, ref_slug, notes)
  values (cid, p_product, public.gen_license_key(p_product), 'trial',
          now() + make_interval(days => d), 0, v_slug, 'تجربة مجانية')
  returning * into s;

  return jsonb_build_object('ok', true, 'key', s.key, 'expires_at', s.expires_at,
                            'days', d, 'slug', v_slug, 'subscription_id', s.id);
end $$;

-- إعدادات عامة للموقع تشمل مدة التجربة
create or replace function public.public_settings()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'brand_name', s.brand_name, 'whatsapp', s.whatsapp, 'phone', s.phone,
    'email', s.email, 'address', s.address,
    'facebook', s.facebook, 'instagram', s.instagram,
    'whish_enabled', s.whish_enabled, 'trial_days', s.trial_days
  ) from public.platform_settings s where s.id = 1;
$$;
