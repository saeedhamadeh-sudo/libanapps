-- ============================================================
--  LibanApps — برنامج «المتجر الإلكتروني» (Ecommerce Website)
--
--  بيضيف:
--   • منتج جديد code = store  (اشتراك سنوي 250$ + تجربة 5 أيام)
--   • جداول المتجر: الإعدادات، التصنيفات، المنتجات، السلايدر،
--     البوب أب، الكوبونات، الطلبات، دومينات الزبون
--   • دوال: التجربة، الطلب، الكوبون، عرض المتجر العام
--
--  آمن للتشغيل أكثر من مرة — ما بيحذف ولا بيغيّر أي بيانات موجودة.
--  شرط مسبق: db/schema.sql + db/upgrade-website.sql +
--            db/upgrade-apps-tenancy.sql (فيها my_client_id / owns).
-- ============================================================

create extension if not exists "pgcrypto";

-- ---------- دوال أساسية (نفسها الموجودة — إعادة تعريف آمنة) ----------
create or replace function public.my_client_id()
returns uuid language sql stable security definer set search_path = public as $$
  select c.id from public.clients c where c.user_id = auth.uid() limit 1;
$$;

create or replace function public.owns(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or (cid is not null and cid = public.my_client_id());
$$;

-- ============================================================
--  1) المنتج والباقة
-- ============================================================
insert into public.products (code, name_ar, name_en, prefix) values
  ('store', 'متجر إلكتروني', 'LibanApps Store', 'STOR')
on conflict (code) do nothing;

-- مدة تجربة خاصة بكل برنامج (فاضي = مدة المنصة العامة)
alter table public.products add column if not exists trial_days integer;
update public.products set trial_days = 5 where code = 'store' and trial_days is null;

insert into public.plans (product_code, name_ar, name_en, days, price_usd, badge_ar, features_ar, sort)
select 'store', 'متجر إلكتروني — سنة', 'Online Store — 1 year', 365, 250, 'جديد',
  array['موقع متجر بالرابط الخاص بك','لوحة تحكم كاملة للمنتجات والطلبات',
        'فيديو يوتيوب لكل منتج','كوبونات خصم وHot Sale وPopup',
        '٥ ثيمات احترافية تختارها أنت','دفع Whish وكاش والطلب على الواتساب',
        'دومين خاص فيك (اختياري)','دعم فني'], 5
where not exists (select 1 from public.plans where product_code = 'store');

-- ============================================================
--  2) الجداول
-- ============================================================
create table if not exists public.stores (
  id                 uuid primary key default gen_random_uuid(),
  client_id          uuid not null references public.clients(id) on delete cascade,
  slug               text unique not null,
  name               text not null default '',
  tagline            text default '',
  logo_url           text default '',
  whatsapp           text default '',            -- أرقام فقط مع رمز الدولة
  phone              text default '',
  email              text default '',
  address            text default '',
  country_code       text not null default 'LB',
  currency_code      text not null default 'USD',
  currency_symbol    text not null default '$',
  currency_decimals  integer not null default 2 check (currency_decimals between 0 and 3),
  theme              text not null default 'maison'
                     check (theme in ('maison','fresh','volt','petal','atelier')),
  primary_color      text default '',
  default_lang       text not null default 'ar',
  announcement       text default '',
  instagram          text default '',
  facebook           text default '',
  tiktok             text default '',
  delivery_enabled   boolean not null default true,
  pickup_enabled     boolean not null default false,
  delivery_fee       numeric(12,2) not null default 0,
  free_delivery_over numeric(12,2),
  min_order          numeric(12,2) not null default 0,
  cod_enabled        boolean not null default true,
  whish_enabled      boolean not null default false,
  hot_enabled        boolean not null default true,
  hot_title          text default '',
  hot_ends_at        timestamptz,
  footer_note        text default '',
  order_seq          integer not null default 0,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now()
);
create index if not exists stores_client_idx on public.stores (client_id);

do $$ begin
  alter table public.stores add constraint stores_slug_format
    check (slug ~ '^[a-z0-9][a-z0-9-]{1,30}$');
exception when duplicate_object then null; end $$;

-- الزبون ما بيغيّر الرابط ولا مالك المتجر (الرابط مربوط باشتراكه)
create or replace function public.stores_lock_fields()
returns trigger language plpgsql as $$
begin
  if not public.is_admin() then
    if new.slug <> old.slug then raise exception 'slug is locked'; end if;
    if new.client_id <> old.client_id then raise exception 'owner is locked'; end if;
  end if;
  return new;
end $$;
drop trigger if exists stores_lock on public.stores;
create trigger stores_lock before update on public.stores
  for each row execute function public.stores_lock_fields();

create table if not exists public.store_categories (
  id         uuid primary key default gen_random_uuid(),
  store_id   uuid not null references public.stores(id) on delete cascade,
  name_ar    text not null,
  name_en    text not null default '',
  image_url  text default '',
  sort       integer not null default 0,
  is_active  boolean not null default true
);
create index if not exists store_cat_idx on public.store_categories (store_id, sort);

create table if not exists public.store_products (
  id            uuid primary key default gen_random_uuid(),
  store_id      uuid not null references public.stores(id) on delete cascade,
  category_id   uuid references public.store_categories(id) on delete set null,
  name_ar       text not null,
  name_en       text not null default '',
  desc_ar       text default '',
  desc_en       text default '',
  price         numeric(12,2) not null default 0,
  compare_price numeric(12,2),                 -- السعر قبل الخصم (للشطب)
  image_url     text default '',
  images        text[] not null default '{}',  -- صور إضافية
  video_url     text default '',               -- رابط يوتيوب
  stock         integer,                       -- فاضي = بلا حد
  is_active     boolean not null default true,
  is_hot        boolean not null default false,
  is_featured   boolean not null default false,
  sort          integer not null default 0,
  created_at    timestamptz not null default now()
);
create index if not exists store_prod_idx on public.store_products (store_id, category_id, sort);

create table if not exists public.store_slides (
  id         uuid primary key default gen_random_uuid(),
  store_id   uuid not null references public.stores(id) on delete cascade,
  image_url  text not null,
  title      text default '',
  subtitle   text default '',
  cta        text default '',
  link_url   text default '',
  sort       integer not null default 0,
  is_active  boolean not null default true
);
create index if not exists store_slides_idx on public.store_slides (store_id, sort);

-- بوب أب واحد لكل متجر
create table if not exists public.store_popups (
  store_id    uuid primary key references public.stores(id) on delete cascade,
  title       text default '',
  body        text default '',
  image_url   text default '',
  cta         text default '',
  link_url    text default '',
  coupon_code text default '',
  show_once   boolean not null default true,
  starts_at   timestamptz,
  ends_at     timestamptz,
  is_active   boolean not null default false,
  updated_at  timestamptz not null default now()
);

create table if not exists public.store_coupons (
  id         uuid primary key default gen_random_uuid(),
  store_id   uuid not null references public.stores(id) on delete cascade,
  code       text not null,
  kind       text not null default 'percent' check (kind in ('percent','fixed')),
  value      numeric(12,2) not null check (value > 0),
  min_order  numeric(12,2) not null default 0,
  max_uses   integer,
  used_count integer not null default 0,
  starts_at  timestamptz,
  expires_at timestamptz,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  unique (store_id, code)
);

create table if not exists public.store_orders (
  id              bigint generated always as identity primary key,
  store_id        uuid not null references public.stores(id) on delete cascade,
  order_no        text not null,
  token           text unique not null default encode(gen_random_bytes(12),'hex'),
  customer_name   text not null,
  customer_phone  text not null,
  customer_email  text default '',
  delivery_method text not null default 'delivery' check (delivery_method in ('delivery','pickup')),
  city            text default '',
  address_text    text default '',
  customer_note   text default '',
  subtotal        numeric(12,2) not null,
  discount        numeric(12,2) not null default 0,
  coupon_code     text default '',
  delivery_fee    numeric(12,2) not null default 0,
  total           numeric(12,2) not null,
  currency_code   text not null default 'USD',
  payment_method  text not null default 'cod' check (payment_method in ('cod','whish')),
  status          text not null default 'pending'
                  check (status in ('pending','awaiting_payment','paid','confirmed','shipped','completed','failed','cancelled')),
  whish_currency  text,
  whish_txn_id    text,
  paid_at         timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists store_orders_idx on public.store_orders (store_id, created_at desc);

create table if not exists public.store_order_items (
  id          bigint generated always as identity primary key,
  order_id    bigint not null references public.store_orders(id) on delete cascade,
  product_id  uuid references public.store_products(id) on delete set null,
  name        text not null,
  unit_price  numeric(12,2) not null,
  qty         integer not null,
  line_total  numeric(12,2) not null
);
create index if not exists store_items_idx on public.store_order_items (order_id);

-- بيانات Whish لكل متجر — بدون أي سياسة قراءة/كتابة عمداً
create table if not exists public.store_payment_credentials (
  store_id      uuid primary key references public.stores(id) on delete cascade,
  whish_channel text default '',
  whish_secret  text default '',
  website_url   text default ''
);

-- دومينات الزبون: بتُدار من السيرفر (Worker) فقط
create table if not exists public.store_domains (
  id             uuid primary key default gen_random_uuid(),
  store_id       uuid not null references public.stores(id) on delete cascade,
  domain         text unique not null,
  status         text not null default 'pending' check (status in ('pending','active','failed')),
  cf_hostname_id text,
  cf_status      text default '',
  ssl_status     text default '',
  info           jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now(),
  verified_at    timestamptz
);
create index if not exists store_domains_store_idx on public.store_domains (store_id);

-- ============================================================
--  3) الصلاحيات (RLS)
-- ============================================================
create or replace function public.store_owned(sid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists (
    select 1 from public.stores s
    where s.id = sid and s.client_id = public.my_client_id());
$$;

alter table public.stores                    enable row level security;
alter table public.store_categories          enable row level security;
alter table public.store_products            enable row level security;
alter table public.store_slides              enable row level security;
alter table public.store_popups              enable row level security;
alter table public.store_coupons             enable row level security;
alter table public.store_orders              enable row level security;
alter table public.store_order_items         enable row level security;
alter table public.store_payment_credentials enable row level security;
alter table public.store_domains             enable row level security;

drop policy if exists own_stores on public.stores;
create policy own_stores on public.stores for all to authenticated
  using (public.store_owned(id)) with check (public.owns(client_id));

do $$
declare t text;
begin
  foreach t in array array['store_categories','store_products','store_slides','store_popups','store_coupons']
  loop
    execute format('drop policy if exists own_%1$s on public.%1$s', t);
    execute format('create policy own_%1$s on public.%1$s for all to authenticated
                    using (public.store_owned(store_id)) with check (public.store_owned(store_id))', t);
  end loop;
end $$;

-- الطلبات: الزبون بيقرأ وبيغيّر الحالة — الإنشاء عبر store_place_order فقط
drop policy if exists own_store_orders_sel on public.store_orders;
create policy own_store_orders_sel on public.store_orders for select to authenticated
  using (public.store_owned(store_id));
drop policy if exists own_store_orders_upd on public.store_orders;
create policy own_store_orders_upd on public.store_orders for update to authenticated
  using (public.store_owned(store_id)) with check (public.store_owned(store_id));
drop policy if exists own_store_orders_del on public.store_orders;
create policy own_store_orders_del on public.store_orders for delete to authenticated
  using (public.store_owned(store_id));

drop policy if exists own_store_items on public.store_order_items;
create policy own_store_items on public.store_order_items for select to authenticated
  using (exists (select 1 from public.store_orders o
                 where o.id = order_id and public.store_owned(o.store_id)));

drop policy if exists own_store_domains on public.store_domains;
create policy own_store_domains on public.store_domains for select to authenticated
  using (public.store_owned(store_id));

-- store_payment_credentials: بدون سياسات — الكتابة عبر set_store_whish() فقط

-- ============================================================
--  4) ترخيص المتجر
--     المتجر مربوط باشتراك: product = store و ref_slug = slug المتجر
-- ============================================================
create or replace function public.store_license(sid uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st public.stores%rowtype; s public.subscriptions%rowtype;
begin
  select * into st from public.stores where id = sid;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;

  select * into s from public.subscriptions
   where client_id = st.client_id and product_code = 'store' and ref_slug = st.slug
   order by expires_at desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no_subscription'); end if;

  return jsonb_build_object(
    'ok',        (s.status = 'active' and s.expires_at > now()),
    'reason',    case when s.status <> 'active' then 'suspended'
                      when s.expires_at <= now() then 'expired' else 'active' end,
    'plan',      s.plan,
    'trial',     (s.plan = 'trial'),
    'expires_at', s.expires_at,
    'days_left', greatest(0, ceil(extract(epoch from (s.expires_at - now()))/86400))::int
  );
end $$;

-- ============================================================
--  5) إنشاء المتجر: تجربة / مشتريات / من لوحتك
-- ============================================================
create or replace function public.store_slug_available(p_slug text)
returns boolean language sql stable security definer set search_path = public as $$
  select lower(trim(coalesce(p_slug,''))) ~ '^[a-z0-9][a-z0-9-]{1,30}$'
     and not exists (select 1 from public.stores where slug = lower(trim(p_slug)))
     and not exists (select 1 from public.subscriptions
                     where product_code = 'store' and ref_slug = lower(trim(p_slug)));
$$;

create or replace function public._make_store(p_client uuid, p_slug text, p_name text)
returns public.stores language plpgsql security definer set search_path = public as $$
declare c public.clients%rowtype; st public.stores;
begin
  select * into c from public.clients where id = p_client;
  insert into public.stores (client_id, slug, name, whatsapp, phone)
  values (p_client, p_slug, coalesce(nullif(trim(p_name),''), p_slug),
          regexp_replace(coalesce(c.phone,''),'\D','','g'), coalesce(c.phone,''))
  returning * into st;
  return st;
end $$;
revoke all on function public._make_store(uuid, text, text) from public, anon, authenticated;

-- تجربة مجانية (5 أيام) — الزبون بيختار رابط متجره
create or replace function public.start_store_trial(p_slug text, p_biz text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare cid uuid; v_slug text; d integer; s public.subscriptions; st public.stores;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select id into cid from public.clients where user_id = auth.uid();
  if cid is null then raise exception 'complete your profile first'; end if;

  if exists (select 1 from public.subscriptions where client_id = cid and product_code = 'store') then
    return jsonb_build_object('ok', false, 'reason', 'عندك اشتراك أو تجربة سابقة لهذا البرنامج');
  end if;

  v_slug := lower(trim(coalesce(p_slug,'')));
  if v_slug !~ '^[a-z0-9][a-z0-9-]{1,30}$' then
    return jsonb_build_object('ok', false, 'reason', 'الرابط لازم يكون إنكليزي (أحرف وأرقام وشرطة) بين 2 و31 حرف');
  end if;
  if not public.store_slug_available(v_slug) then
    return jsonb_build_object('ok', false, 'reason', 'هذا الرابط محجوز — اختار غيره');
  end if;

  select coalesce(trial_days, 5) into d from public.products where code = 'store';
  d := greatest(1, coalesce(d, 5));

  st := public._make_store(cid, v_slug, p_biz);

  insert into public.subscriptions (client_id, product_code, key, plan, expires_at,
                                    price_usd, ref_slug, notes)
  values (cid, 'store', public.gen_license_key('store'), 'trial',
          now() + make_interval(days => d), 0, v_slug, 'تجربة مجانية')
  returning * into s;

  return jsonb_build_object('ok', true, 'key', s.key, 'expires_at', s.expires_at,
                            'days', d, 'slug', v_slug, 'subscription_id', s.id);
end $$;

-- الزبون اشترى (provision_purchase حفظ الرابط بالاشتراك) — منبني المتجر أول ما يفتح اللوحة
create or replace function public.ensure_store(p_slug text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_slug text; st public.stores; cid uuid; s public.subscriptions;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  v_slug := lower(trim(coalesce(p_slug,'')));

  select * into st from public.stores where slug = v_slug;
  if found then
    if not public.owns(st.client_id) then raise exception 'not allowed'; end if;
    return to_jsonb(st);
  end if;

  cid := public.my_client_id();
  if cid is null then raise exception 'no client'; end if;

  select * into s from public.subscriptions
   where client_id = cid and product_code = 'store' and ref_slug = v_slug limit 1;
  if not found then raise exception 'no subscription for this store'; end if;

  select * into st from public._make_store(cid, v_slug, '');
  return to_jsonb(st);
end $$;

-- إصدار متجر من لوحة المشرف
create or replace function public.admin_new_store(
  p_client uuid, p_slug text, p_biz text, p_days integer, p_price numeric default 0
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_slug text; st public.stores; s public.subscriptions;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  v_slug := lower(trim(coalesce(p_slug,'')));
  if v_slug !~ '^[a-z0-9][a-z0-9-]{1,30}$' then raise exception 'invalid slug'; end if;
  if not public.store_slug_available(v_slug) then raise exception 'slug taken'; end if;

  st := public._make_store(p_client, v_slug, p_biz);
  insert into public.subscriptions (client_id, product_code, key, plan, expires_at,
                                    price_usd, ref_slug, notes)
  values (p_client, 'store', public.gen_license_key('store'),
          case when p_days <= 7 then 'trial' when p_days <= 31 then 'monthly' else 'yearly' end,
          now() + make_interval(days => greatest(1, p_days)),
          coalesce(p_price,0), v_slug, 'إصدار يدوي')
  returning * into s;

  return jsonb_build_object('ok', true, 'key', s.key, 'expires_at', s.expires_at, 'slug', v_slug);
end $$;

-- ============================================================
--  6) Whish الخاص بكل متجر
-- ============================================================
create or replace function public.set_store_whish(
  p_store uuid, p_enabled boolean, p_channel text, p_secret text
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.store_owned(p_store) then raise exception 'not allowed'; end if;
  insert into public.store_payment_credentials (store_id, whish_channel, whish_secret)
  values (p_store, coalesce(p_channel,''), coalesce(p_secret,''))
  on conflict (store_id) do update set
    whish_channel = excluded.whish_channel,
    whish_secret  = case when coalesce(p_secret,'') = ''
                         then public.store_payment_credentials.whish_secret
                         else excluded.whish_secret end;
  update public.stores set whish_enabled = coalesce(p_enabled,false) where id = p_store;
end $$;

create or replace function public.store_whish_status(p_store uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c public.store_payment_credentials%rowtype; st public.stores%rowtype;
begin
  if not public.store_owned(p_store) then raise exception 'not allowed'; end if;
  select * into st from public.stores where id = p_store;
  select * into c from public.store_payment_credentials where store_id = p_store;
  return jsonb_build_object(
    'enabled', coalesce(st.whish_enabled,false),
    'channel_hint', case when coalesce(c.whish_channel,'') = '' then ''
                         else '••••' || right(c.whish_channel,4) end,
    'has_secret', coalesce(c.whish_secret,'') <> ''
  );
end $$;

-- ============================================================
--  7) الكوبونات
-- ============================================================
create or replace function public._store_coupon_calc(p_store uuid, p_code text, p_subtotal numeric)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c public.store_coupons%rowtype; st public.stores%rowtype; disc numeric;
begin
  select * into st from public.stores where id = p_store;
  select * into c from public.store_coupons
   where store_id = p_store and code = upper(trim(coalesce(p_code,''))) and is_active;
  if not found then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  if c.starts_at  is not null and c.starts_at  > now() then
    return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  if c.expires_at is not null and c.expires_at < now() then
    return jsonb_build_object('ok', false, 'reason', 'expired'); end if;
  if c.max_uses is not null and c.used_count >= c.max_uses then
    return jsonb_build_object('ok', false, 'reason', 'used_up'); end if;
  if p_subtotal < c.min_order then
    return jsonb_build_object('ok', false, 'reason', 'min_order', 'min', c.min_order); end if;

  disc := case when c.kind = 'percent' then p_subtotal * least(c.value,100) / 100
               else least(c.value, p_subtotal) end;
  disc := round(disc, st.currency_decimals);
  return jsonb_build_object('ok', true, 'code', c.code, 'kind', c.kind,
                            'value', c.value, 'discount', disc);
end $$;
revoke all on function public._store_coupon_calc(uuid, text, numeric) from public, anon, authenticated;

create or replace function public.check_store_coupon(p_slug text, p_code text, p_subtotal numeric)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st public.stores%rowtype;
begin
  select * into st from public.stores where slug = lower(trim(coalesce(p_slug,'')));
  if not found then return jsonb_build_object('ok', false, 'reason', 'invalid'); end if;
  return public._store_coupon_calc(st.id, p_code, coalesce(p_subtotal,0));
end $$;

-- ============================================================
--  8) عرض المتجر للزوّار (بدون تسجيل دخول)
-- ============================================================
create or replace function public.store_public(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st public.stores%rowtype; lic jsonb; whish_ready boolean; pop jsonb;
begin
  select * into st from public.stores where slug = lower(trim(coalesce(p_slug,'')));
  if not found then
    if exists (select 1 from public.subscriptions
               where product_code = 'store' and ref_slug = lower(trim(coalesce(p_slug,'')))) then
      return jsonb_build_object('ok', false, 'reason', 'not_ready');
    end if;
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  lic := public.store_license(st.id);
  if not st.is_active or not (lic->>'ok')::boolean then
    return jsonb_build_object('ok', false,
      'reason', case when not st.is_active then 'inactive' else coalesce(lic->>'reason','expired') end,
      'store', jsonb_build_object('name', st.name, 'logo_url', st.logo_url,
                                   'whatsapp', st.whatsapp, 'theme', st.theme));
  end if;

  whish_ready := st.whish_enabled
    and st.currency_code in ('USD','LBP')
    and exists (select 1 from public.store_payment_credentials c
                where c.store_id = st.id and c.whish_channel <> '' and c.whish_secret <> '');

  select to_jsonb(p) into pop from public.store_popups p
   where p.store_id = st.id and p.is_active
     and (p.starts_at is null or p.starts_at <= now())
     and (p.ends_at   is null or p.ends_at   >= now());

  return jsonb_build_object(
    'ok', true,
    'store', (to_jsonb(st) - 'client_id' - 'order_seq') || jsonb_build_object('whish_ready', whish_ready),
    'categories', coalesce((select jsonb_agg(to_jsonb(c) order by c.sort, c.name_ar)
                            from public.store_categories c
                            where c.store_id = st.id and c.is_active), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(to_jsonb(p) order by p.sort, p.created_at)
                          from (select * from public.store_products
                                where store_id = st.id and is_active
                                order by sort, created_at limit 2000) p), '[]'::jsonb),
    'slides', coalesce((select jsonb_agg(to_jsonb(s) order by s.sort)
                        from public.store_slides s
                        where s.store_id = st.id and s.is_active), '[]'::jsonb),
    'popup', pop
  );
end $$;

-- ============================================================
--  9) الطلب (بيحسب الأسعار من الداتابيس — مش من المتصفح)
-- ============================================================
create or replace function public.store_place_order(
  p_slug text, p_name text, p_phone text, p_email text, p_method text,
  p_city text, p_address text, p_note text, p_payment text, p_coupon text, p_lines jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  st public.stores%rowtype; pr public.store_products%rowtype;
  v_sub numeric := 0; v_disc numeric := 0; v_fee numeric := 0; v_tot numeric;
  v_no text; v_id bigint; v_tok text; v_cp jsonb; v_ready boolean;
  ln record; v_qty integer; v_items jsonb := '[]'::jsonb; v_code text := '';
begin
  select * into st from public.stores
   where slug = lower(trim(coalesce(p_slug,''))) for update;
  if not found or not st.is_active or not (public.store_license(st.id)->>'ok')::boolean then
    raise exception 'store unavailable';
  end if;

  if length(trim(coalesce(p_name,''))) < 2
     or length(regexp_replace(coalesce(p_phone,''),'\D','','g')) < 7 then
    raise exception 'invalid customer details';
  end if;
  if p_method not in ('delivery','pickup') then raise exception 'bad method'; end if;
  if p_method = 'delivery' and not st.delivery_enabled then raise exception 'delivery disabled'; end if;
  if p_method = 'pickup'   and not st.pickup_enabled   then raise exception 'pickup disabled'; end if;
  if p_method = 'delivery' and length(trim(coalesce(p_address,''))) < 3 then
    raise exception 'address required'; end if;

  if p_payment not in ('cod','whish') then raise exception 'bad payment'; end if;
  if p_payment = 'cod' and not st.cod_enabled then raise exception 'cod disabled'; end if;
  if p_payment = 'whish' then
    v_ready := st.whish_enabled and st.currency_code in ('USD','LBP')
      and exists (select 1 from public.store_payment_credentials c
                  where c.store_id = st.id and c.whish_channel <> '' and c.whish_secret <> '');
    if not v_ready then raise exception 'whish disabled'; end if;
  end if;

  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'empty cart'; end if;

  -- تجميع السطور المكرّرة، وتحقق من المنتج والمخزون
  for ln in
    select x.id, sum(greatest(1, least(99, coalesce(x.qty,1))))::int as qty
    from jsonb_to_recordset(p_lines) as x(id uuid, qty int)
    group by x.id
  loop
    v_qty := ln.qty;
    select * into pr from public.store_products
     where id = ln.id and store_id = st.id and is_active for update;
    if not found then raise exception 'product unavailable'; end if;
    if pr.stock is not null and pr.stock < v_qty then
      raise exception 'insufficient stock: %', coalesce(nullif(pr.name_ar,''), pr.name_en);
    end if;
    v_sub := v_sub + pr.price * v_qty;
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'id', pr.id, 'name', coalesce(nullif(pr.name_ar,''), pr.name_en),
      'price', pr.price, 'qty', v_qty));
  end loop;

  if v_sub < st.min_order then raise exception 'min order'; end if;

  if coalesce(trim(p_coupon),'') <> '' then
    v_cp := public._store_coupon_calc(st.id, p_coupon, v_sub);
    if not (v_cp->>'ok')::boolean then raise exception 'coupon: %', v_cp->>'reason'; end if;
    v_disc := (v_cp->>'discount')::numeric;
    v_code := v_cp->>'code';
  end if;

  if p_method = 'delivery' then
    v_fee := st.delivery_fee;
    if st.free_delivery_over is not null and (v_sub - v_disc) >= st.free_delivery_over then
      v_fee := 0; end if;
  end if;

  v_sub := round(v_sub, st.currency_decimals);
  v_tot := round(v_sub - v_disc + v_fee, st.currency_decimals);

  update public.stores set order_seq = order_seq + 1 where id = st.id
  returning order_seq into v_id;
  v_no := 'S' || lpad(v_id::text, 4, '0');

  insert into public.store_orders (store_id, order_no, customer_name, customer_phone, customer_email,
      delivery_method, city, address_text, customer_note, subtotal, discount, coupon_code,
      delivery_fee, total, currency_code, payment_method, status)
  values (st.id, v_no, trim(p_name), trim(p_phone), coalesce(trim(p_email),''),
      p_method, coalesce(trim(p_city),''), coalesce(trim(p_address),''), coalesce(trim(p_note),''),
      v_sub, v_disc, v_code, v_fee, v_tot, st.currency_code, p_payment,
      case when p_payment = 'whish' then 'awaiting_payment' else 'pending' end)
  returning id, token into v_id, v_tok;

  insert into public.store_order_items (order_id, product_id, name, unit_price, qty, line_total)
  select v_id, (i->>'id')::uuid, i->>'name', (i->>'price')::numeric, (i->>'qty')::int,
         round((i->>'price')::numeric * (i->>'qty')::int, st.currency_decimals)
  from jsonb_array_elements(v_items) i;

  update public.store_products p set stock = p.stock - (i->>'qty')::int
  from jsonb_array_elements(v_items) i
  where p.id = (i->>'id')::uuid and p.stock is not null;

  if v_code <> '' then
    update public.store_coupons set used_count = used_count + 1
     where store_id = st.id and code = v_code;
  end if;

  return jsonb_build_object(
    'order_id', v_id, 'order_no', v_no, 'token', v_tok,
    'subtotal', v_sub, 'discount', v_disc, 'delivery_fee', v_fee, 'total', v_tot,
    'currency_code', st.currency_code, 'currency_symbol', st.currency_symbol,
    'currency_decimals', st.currency_decimals, 'whatsapp', st.whatsapp);
end $$;

-- الطلب الملغي/الفاشل بيرجّع المخزون والكوبون تلقائياً
create or replace function public.store_orders_restock()
returns trigger language plpgsql security definer set search_path = public as $$
declare was_dead boolean; is_dead boolean;
begin
  was_dead := old.status in ('failed','cancelled');
  is_dead  := new.status in ('failed','cancelled');
  if is_dead and not was_dead then
    update public.store_products p set stock = p.stock + i.qty
    from public.store_order_items i
    where i.order_id = new.id and p.id = i.product_id and p.stock is not null;
    if coalesce(new.coupon_code,'') <> '' then
      update public.store_coupons set used_count = greatest(0, used_count - 1)
       where store_id = new.store_id and code = new.coupon_code;
    end if;
  elsif was_dead and not is_dead then
    update public.store_products p set stock = greatest(0, p.stock - i.qty)
    from public.store_order_items i
    where i.order_id = new.id and p.id = i.product_id and p.stock is not null;
  end if;
  return new;
end $$;
drop trigger if exists store_orders_restock_trg on public.store_orders;
create trigger store_orders_restock_trg after update of status on public.store_orders
  for each row execute function public.store_orders_restock();

-- حالة طلب لصفحة «تم الدفع» (بالرمز السري فقط)
create or replace function public.store_order_status(p_token text)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'order_no', o.order_no, 'status', o.status, 'total', o.total,
    'currency_code', o.currency_code, 'payment_method', o.payment_method,
    'currency_symbol', s.currency_symbol, 'currency_decimals', s.currency_decimals,
    'whatsapp', s.whatsapp)
  from public.store_orders o join public.stores s on s.id = o.store_id
  where o.token = p_token limit 1;
$$;

-- تحقق سريع
select 'store product' as item, exists (select 1 from public.products where code = 'store') as ok
union all
select 'store plan', exists (select 1 from public.plans where product_code = 'store')
union all
select 'stores table', to_regclass('public.stores') is not null;
