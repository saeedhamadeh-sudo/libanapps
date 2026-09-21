-- ============================================================
--  LibanApps — موقع البيع الذاتي
--  باقات · إعدادات المنصة · مشتريات · توليد ترخيص تلقائي
--  آمن للتشغيل أكثر من مرة — لا يحذف أي بيانات
-- ============================================================

-- ---------- 1) الباقات ----------
create table if not exists public.plans (
  id            uuid primary key default gen_random_uuid(),
  product_code  text not null references public.products(code),
  name_ar       text not null,
  name_en       text not null default '',
  days          integer not null default 365,
  price_usd     numeric(10,2) not null default 0,
  old_price_usd numeric(10,2),                    -- للشطب (اختياري)
  badge_ar      text default '',                  -- "الأكثر طلباً"
  features_ar   text[] not null default '{}',
  features_en   text[] not null default '{}',
  is_active     boolean not null default true,
  sort          integer not null default 0,
  created_at    timestamptz not null default now()
);
create index if not exists plans_product_idx on public.plans (product_code, sort);

-- ---------- 2) إعدادات المنصة ----------
create table if not exists public.platform_settings (
  id             integer primary key default 1 check (id = 1),
  brand_name     text default 'LibanApps',
  whatsapp       text default '',                 -- 961XXXXXXXX
  phone          text default '',
  email          text default '',
  address        text default '',
  facebook       text default '',
  instagram      text default '',
  whish_enabled  boolean not null default false,
  whish_channel  text default '',
  whish_secret   text default '',
  website_url    text default 'https://libanapps.com',
  updated_at     timestamptz not null default now()
);
insert into public.platform_settings (id) values (1) on conflict (id) do nothing;

-- ---------- 3) ربط الزبون بحسابه ----------
alter table public.clients add column if not exists user_id uuid references auth.users(id) on delete set null;
create index if not exists clients_user_idx on public.clients (user_id);

-- ---------- 4) المشتريات ----------
create table if not exists public.purchases (
  id              bigint generated always as identity primary key,   -- = Whish externalId
  user_id         uuid not null references auth.users(id) on delete cascade,
  client_id       uuid references public.clients(id) on delete set null,
  plan_id         uuid not null references public.plans(id),
  product_code    text not null,
  amount_usd      numeric(10,2) not null,
  days            integer not null,
  slug            text default '',                -- للمنيو
  biz_name        text default '',
  status          text not null default 'pending'
                  check (status in ('pending','awaiting_payment','paid','failed','cancelled')),
  whish_txn_id    text,
  subscription_id uuid references public.subscriptions(id) on delete set null,
  paid_at         timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists purchases_user_idx on public.purchases (user_id, created_at desc);

-- ============================================================
--  دوال عامة
-- ============================================================

-- معلومات التواصل للموقع (بدون أي سر)
create or replace function public.public_settings()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'brand_name', s.brand_name, 'whatsapp', s.whatsapp, 'phone', s.phone,
    'email', s.email, 'address', s.address,
    'facebook', s.facebook, 'instagram', s.instagram,
    'whish_enabled', s.whish_enabled
  ) from public.platform_settings s where s.id = 1;
$$;

-- تسجيل بيانات الزبون بعد إنشاء حسابه
create or replace function public.register_customer(
  p_name text, p_phone text, p_business text default '', p_city text default ''
) returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select id into cid from public.clients where user_id = auth.uid();
  if cid is null then
    insert into public.clients (name, phone, business, city, user_id)
    values (trim(p_name), trim(p_phone), coalesce(p_business,''), coalesce(p_city,''), auth.uid())
    returning id into cid;
  else
    update public.clients
       set name = trim(p_name), phone = trim(p_phone),
           business = coalesce(p_business, business), city = coalesce(p_city, city)
     where id = cid;
  end if;
  return cid;
end $$;

-- بدء عملية شراء
create or replace function public.start_purchase(
  p_plan uuid, p_slug text default '', p_biz text default ''
) returns jsonb language plpgsql security definer set search_path = public as $$
declare pl public.plans%rowtype; cid uuid; pid bigint; v_slug text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into pl from public.plans where id = p_plan and is_active;
  if not found then raise exception 'plan not found'; end if;

  select id into cid from public.clients where user_id = auth.uid();
  if cid is null then raise exception 'complete your profile first'; end if;

  v_slug := lower(trim(coalesce(p_slug,'')));
  if pl.product_code = 'menu' then
    if v_slug !~ '^[a-z0-9][a-z0-9-]{1,30}$' then raise exception 'invalid slug'; end if;
    if exists (select 1 from public.restaurants where slug = v_slug) then
      raise exception 'slug taken';
    end if;
  end if;

  insert into public.purchases (user_id, client_id, plan_id, product_code,
                                amount_usd, days, slug, biz_name)
  values (auth.uid(), cid, pl.id, pl.product_code,
          pl.price_usd, pl.days, v_slug, coalesce(p_biz,''))
  returning id into pid;

  return jsonb_build_object('purchase_id', pid, 'amount', pl.price_usd,
                            'product', pl.product_code, 'days', pl.days);
end $$;

-- تفعيل الشراء بعد نجاح الدفع (يستدعيها السيرفر فقط)
create or replace function public.provision_purchase(p_id bigint, p_txn text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.purchases%rowtype; s public.subscriptions; r public.restaurants%rowtype; c public.clients%rowtype;
begin
  select * into p from public.purchases where id = p_id;
  if not found then raise exception 'purchase not found'; end if;
  if p.status = 'paid' then
    return jsonb_build_object('ok', true, 'already', true, 'subscription_id', p.subscription_id);
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
    values (p.user_id, r.id, 'owner')
    on conflict do nothing;

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
     set status = 'paid', paid_at = now(), whish_txn_id = p_txn, subscription_id = s.id
   where id = p.id;

  return jsonb_build_object('ok', true, 'key', s.key, 'expires_at', s.expires_at,
                            'slug', coalesce(p.slug,''), 'product', p.product_code);
end $$;

-- مشترياتي (لصفحة حساب الزبون)
create or replace function public.my_purchases()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', p.id, 'product', p.product_code, 'status', p.status,
      'amount', p.amount_usd, 'slug', p.slug, 'created_at', p.created_at,
      'plan_name', pl.name_ar,
      'key', s.key, 'expires_at', s.expires_at,
      'days_left', greatest(0, ceil(extract(epoch from (s.expires_at - now()))/86400))::int
    ) as x
    from public.purchases p
    join public.plans pl on pl.id = p.plan_id
    left join public.subscriptions s on s.id = p.subscription_id
    where p.user_id = auth.uid()
  ) t;
$$;

-- حفظ بيانات Whish الخاصة بالمنصة (بدون إرجاع السر)
create or replace function public.set_platform_whish(
  p_enabled boolean, p_channel text, p_secret text
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update public.platform_settings set
    whish_enabled = p_enabled,
    whish_channel = p_channel,
    whish_secret  = case when p_secret = '' then whish_secret else p_secret end,
    updated_at    = now()
  where id = 1;
end $$;

create or replace function public.platform_whish_status()
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.platform_settings%rowtype;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  select * into s from public.platform_settings where id = 1;
  return jsonb_build_object(
    'enabled', s.whish_enabled,
    'channel_hint', case when s.whish_channel = '' then '' else '••••' || right(s.whish_channel,4) end,
    'has_secret', s.whish_secret <> ''
  );
end $$;

-- ============================================================
--  RLS
-- ============================================================
alter table public.plans              enable row level security;
alter table public.platform_settings  enable row level security;
alter table public.purchases          enable row level security;

drop policy if exists pub_plans on public.plans;
create policy pub_plans on public.plans for select to anon, authenticated
  using (is_active);

drop policy if exists adm_plans on public.plans;
create policy adm_plans on public.plans for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- platform_settings: لا قراءة عامة (فيه أسرار) — العامة عبر public_settings()
-- والمشرف بيحتاج قراءة كمان، لأن التحديث بيرجّع الصف
drop policy if exists adm_settings_read on public.platform_settings;
create policy adm_settings_read on public.platform_settings for select to authenticated
  using (public.is_admin());

drop policy if exists adm_settings on public.platform_settings;
create policy adm_settings on public.platform_settings for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists own_purchases on public.purchases;
create policy own_purchases on public.purchases for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists adm_purchases on public.purchases;
create policy adm_purchases on public.purchases for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- الزبون يقرأ بياناته هو
drop policy if exists own_client on public.clients;
create policy own_client on public.clients for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- ============================================================
--  باقات ابتدائية — عدّلها من لوحتك
-- ============================================================
insert into public.plans (product_code, name_ar, days, price_usd, badge_ar, features_ar, sort)
select 'menu', 'منيو المطاعم — سنة', 365, 60, 'الأكثر طلباً',
  array['منيو رقمي بلغتين','رمز QR جاهز للطباعة','طلبات على الواتساب','خريطة لتحديد موقع الزبون',
        'أسعار بالدولار والليرة','١٣ ثيم جاهز','لوحة تحكم كاملة','دعم فني'], 1
where not exists (select 1 from public.plans where product_code='menu');

insert into public.plans (product_code, name_ar, days, price_usd, features_ar, sort)
select 'alum', 'محاسبة الصناعيين — سنة', 365, 150,
  array['فواتير وكشوف حساب','حساب التربيع تلقائياً','إدارة الزبائن والإيصالات','نسخ احتياطي سحابي',
        'تعدد المستخدمين','دعم فني'], 1
where not exists (select 1 from public.plans where product_code='alum');

insert into public.plans (product_code, name_ar, days, price_usd, features_ar, sort)
select 'trade', 'محاسبة التجارة — سنة', 365, 120,
  array['نقطة بيع POS','إدارة مستودع وصلاحيات','تنبيه انتهاء الصلاحية','طباعة A4 وحرارية',
        'صندوق دولار وليرة','دعم فني'], 1
where not exists (select 1 from public.plans where product_code='trade');
