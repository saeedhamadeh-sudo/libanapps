-- ============================================================
--  LibanApps / itech — SCHEMA v2  (كامل)
--
--  آمن للتشغيل أكثر من مرة: كل شي مكتوب بصيغة
--  IF NOT EXISTS / CREATE OR REPLACE.
--  ما بيحذف ولا جدول ولا صف ولا زبون قديم.
--  كل مرة منضيف شي، بتاخد الملف كامل ومنشغّله من أوله.
--
--  بيشمل:
--   أ) نظام الزبائن والتراخيص الموحّد للبرامج الثلاثة
--      (منيو المطاعم / برنامج الألمنيوم / برنامج التجارة)
--   ب) منصة المنيو الكاملة
-- ============================================================

create extension if not exists "pgcrypto";

-- ============================================================
--  القسم أ — الزبائن والتراخيص (مشترك بين كل البرامج)
-- ============================================================

-- ---------- المنتجات ----------
create table if not exists public.products (
  code       text primary key,           -- menu | alum | trade
  name_ar    text not null,
  name_en    text not null,
  prefix     text not null,              -- بادئة مفتاح التفعيل
  is_active  boolean not null default true
);

insert into public.products (code, name_ar, name_en, prefix) values
  ('menu',  'منيو المطاعم',      'LibanApps Menu',    'MENU'),
  ('alum',  'محاسبة الألمنيوم',  'itech Accounting',  'ALUM'),
  ('trade', 'محاسبة التجارة',    'itech Trade',       'TRAD')
on conflict (code) do nothing;

-- ---------- الزبائن ----------
create table if not exists public.clients (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  business   text default '',
  phone      text default '',
  city       text default '',
  notes      text default '',
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists clients_name_idx on public.clients (name);

-- ---------- الاشتراكات / مفاتيح التفعيل ----------
create table if not exists public.subscriptions (
  id            uuid primary key default gen_random_uuid(),
  client_id     uuid not null references public.clients(id) on delete cascade,
  product_code  text not null references public.products(code),
  key           text unique not null,
  plan          text not null default 'yearly',   -- trial | monthly | yearly | custom
  starts_at     timestamptz not null default now(),
  expires_at    timestamptz not null,
  price_usd     numeric(10,2) default 0,
  status        text not null default 'active',   -- active | suspended
  device_id     text,                             -- يُربط عند أول تفعيل
  device_name   text default '',
  activated_at  timestamptz,
  last_seen_at  timestamptz,
  ref_slug      text default '',                  -- للمنيو: slug المطعم
  notes         text default '',
  created_at    timestamptz not null default now()
);
create index if not exists subs_client_idx  on public.subscriptions (client_id);
create index if not exists subs_product_idx on public.subscriptions (product_code, expires_at desc);
create index if not exists subs_key_idx     on public.subscriptions (key);

-- ---------- توليد مفتاح ----------
create or replace function public.gen_license_key(p_product text)
returns text language plpgsql as $$
declare
  pre text; k text; alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; i int;
begin
  select prefix into pre from public.products where code = p_product;
  if pre is null then pre := 'GEN'; end if;
  loop
    k := pre || '-';
    for i in 1..12 loop
      k := k || substr(alphabet, 1 + floor(random()*length(alphabet))::int, 1);
      if i = 4 or i = 8 then k := k || '-'; end if;
    end loop;
    exit when not exists (select 1 from public.subscriptions s where s.key = k);
  end loop;
  return k;
end $$;

-- ---------- إنشاء اشتراك (من لوحة التحكم) ----------
create or replace function public.new_subscription(
  p_client uuid, p_product text, p_plan text, p_days integer,
  p_price numeric default 0, p_slug text default '', p_notes text default ''
) returns public.subscriptions
language plpgsql security definer set search_path = public as $$
declare s public.subscriptions;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  insert into public.subscriptions (client_id, product_code, key, plan, expires_at,
                                    price_usd, ref_slug, notes)
  values (p_client, p_product, public.gen_license_key(p_product), p_plan,
          now() + make_interval(days => greatest(1, p_days)),
          coalesce(p_price,0), coalesce(p_slug,''), coalesce(p_notes,''))
  returning * into s;
  return s;
end $$;

-- ---------- تمديد اشتراك ----------
create or replace function public.extend_subscription(p_id uuid, p_days integer)
returns public.subscriptions
language plpgsql security definer set search_path = public as $$
declare s public.subscriptions;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update public.subscriptions
     set expires_at = greatest(expires_at, now()) + make_interval(days => p_days)
   where id = p_id
  returning * into s;
  return s;
end $$;

-- ---------- فك ربط الجهاز (الزبون غيّر كمبيوتر) ----------
create or replace function public.reset_device(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update public.subscriptions
     set device_id = null, device_name = '', activated_at = null
   where id = p_id;
end $$;

-- ---------- التحقق من الترخيص (تناديها البرامج نفسها) ----------
--  عامة عن قصد: البرنامج عند الزبون بيناديها بمفتاح anon
--  ما بترجّع ولا معلومة عن زبون تاني.
create or replace function public.activate_license(
  p_key text, p_device text, p_device_name text default '', p_product text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.subscriptions; c public.clients;
begin
  select * into s from public.subscriptions
   where upper(trim(key)) = upper(trim(p_key));

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  if p_product is not null and s.product_code <> p_product then
    return jsonb_build_object('ok', false, 'reason', 'wrong_product');
  end if;

  if s.status <> 'active' then
    return jsonb_build_object('ok', false, 'reason', 'suspended');
  end if;

  -- ربط الجهاز عند أول تفعيل
  if s.device_id is null then
    update public.subscriptions
       set device_id = p_device, device_name = coalesce(p_device_name,''),
           activated_at = now(), last_seen_at = now()
     where id = s.id returning * into s;
  elsif s.device_id <> p_device then
    return jsonb_build_object('ok', false, 'reason', 'device_mismatch');
  else
    update public.subscriptions set last_seen_at = now() where id = s.id;
  end if;

  select * into c from public.clients where id = s.client_id;

  if s.expires_at < now() then
    return jsonb_build_object('ok', false, 'reason', 'expired',
      'expires_at', s.expires_at, 'client', c.name);
  end if;

  return jsonb_build_object(
    'ok', true,
    'product', s.product_code,
    'plan', s.plan,
    'client', c.name,
    'business', c.business,
    'expires_at', s.expires_at,
    'days_left', greatest(0, ceil(extract(epoch from (s.expires_at - now()))/86400))::int,
    'slug', s.ref_slug
  );
end $$;

-- ============================================================
--  القسم ب — منصة المنيو
-- ============================================================

create table if not exists public.restaurants (
  id                uuid primary key default gen_random_uuid(),
  slug              text unique not null,
  name_ar           text not null,
  name_en           text not null,
  tagline_ar        text default '',
  tagline_en        text default '',
  logo_url          text default '',
  phone             text default '',
  whatsapp          text default '',
  address_ar        text default '',
  address_en        text default '',
  maps_url          text default '',
  exchange_rate     numeric(12,2) not null default 89500,
  lbp_rounding      integer not null default 1000,
  show_lbp          boolean not null default true,
  dinein_enabled    boolean not null default true,
  delivery_enabled  boolean not null default true,
  delivery_fee_usd  numeric(10,2) not null default 0,
  min_order_usd     numeric(10,2) not null default 0,
  require_location  boolean not null default true,
  theme             text not null default 'flame',
  primary_color     text default '',
  default_lang      text not null default 'ar',
  order_seq         integer not null default 0,
  is_active         boolean not null default true,
  notes_ar          text default '',
  notes_en          text default '',
  created_at        timestamptz not null default now()
);

-- أعمدة تُضاف لاحقاً بأمان
alter table public.restaurants add column if not exists client_id uuid references public.clients(id) on delete set null;
alter table public.restaurants add column if not exists whish_enabled boolean not null default false;
alter table public.restaurants add column if not exists working_hours jsonb default '{}'::jsonb;

do $$ begin
  alter table public.restaurants add constraint slug_format
    check (slug ~ '^[a-z0-9][a-z0-9-]{1,30}$');
exception when duplicate_object then null; end $$;

create index if not exists restaurants_slug_idx on public.restaurants (slug);

-- الترخيص القديم للمنيو (محفوظ كما هو — لا يُحذف)
create table if not exists public.licenses (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  plan          text not null default 'trial',
  key           text unique not null default upper(encode(gen_random_bytes(6),'hex')),
  starts_at     timestamptz not null default now(),
  expires_at    timestamptz not null,
  price_usd     numeric(10,2) default 0,
  note          text default '',
  created_at    timestamptz not null default now()
);
create index if not exists licenses_rest_idx on public.licenses (restaurant_id, expires_at desc);

-- ---------- صلاحية المطعم: الأبعد بين الجدول القديم والاشتراكات ----------
create or replace function public.license_until(rid uuid)
returns timestamptz language sql stable security definer set search_path = public as $$
  select greatest(
    coalesce((select max(l.expires_at) from public.licenses l where l.restaurant_id = rid), 'epoch'::timestamptz),
    coalesce((select max(s.expires_at) from public.subscriptions s
               join public.restaurants r on r.slug = s.ref_slug
              where r.id = rid and s.product_code = 'menu' and s.status = 'active'), 'epoch'::timestamptz)
  );
$$;

create or replace function public.menu_live(rid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.restaurants r
    where r.id = rid and r.is_active
      and public.license_until(rid) > now() - interval '3 days'
  );
$$;

create or replace function public.license_active(rid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.license_until(rid) > now();
$$;

-- ---------- صاحب المطعم يشوف اشتراكه هو فقط ----------
create or replace function public.my_license(rid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v timestamptz;
begin
  if not public.is_member(rid) then raise exception 'not allowed'; end if;
  v := public.license_until(rid);
  return jsonb_build_object(
    'expires_at', v,
    'days_left', greatest(0, ceil(extract(epoch from (v - now()))/86400))::int,
    'active', v > now()
  );
end $$;

-- ---------- الصلاحيات ----------
create table if not exists public.platform_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.restaurant_users (
  user_id       uuid not null references auth.users(id) on delete cascade,
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  role          text not null default 'owner',
  created_at    timestamptz not null default now(),
  primary key (user_id, restaurant_id)
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.platform_admins where user_id = auth.uid());
$$;

create or replace function public.is_member(rid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists (
    select 1 from public.restaurant_users
    where user_id = auth.uid() and restaurant_id = rid
  );
$$;

-- ---------- محتوى المنيو ----------
create table if not exists public.categories (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  name_ar       text not null,
  name_en       text not null,
  sort          integer not null default 0,
  is_active     boolean not null default true
);
create index if not exists categories_rest_idx on public.categories (restaurant_id, sort);

create table if not exists public.items (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  category_id   uuid references public.categories(id) on delete set null,
  name_ar       text not null,
  name_en       text not null,
  desc_ar       text default '',
  desc_en       text default '',
  price_usd     numeric(10,2) not null default 0,
  image_url     text default '',
  is_available  boolean not null default true,
  is_featured   boolean not null default false,
  sort          integer not null default 0
);
create index if not exists items_rest_idx on public.items (restaurant_id, category_id, sort);

create table if not exists public.banners (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  image_url     text not null,
  caption_ar    text default '',
  caption_en    text default '',
  sort          integer not null default 0,
  is_active     boolean not null default true
);

create table if not exists public.promos (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  title_ar      text default '',
  title_en      text default '',
  body_ar       text default '',
  body_en       text default '',
  image_url     text default '',
  starts_at     timestamptz default now(),
  ends_at       timestamptz,
  show_once     boolean not null default true,
  is_active     boolean not null default true
);

-- ---------- الطلبات ----------
create table if not exists public.orders (
  id              bigint generated always as identity primary key,
  restaurant_id   uuid not null references public.restaurants(id) on delete cascade,
  order_no        text not null,
  token           text unique not null default encode(gen_random_bytes(9),'base64'),
  order_type      text not null check (order_type in ('dine_in','delivery')),
  customer_name   text not null,
  customer_phone  text not null,
  table_no        text default '',
  address_text    text default '',
  lat             double precision,
  lng             double precision,
  customer_note   text default '',
  subtotal_usd    numeric(10,2) not null,
  delivery_usd    numeric(10,2) not null default 0,
  total_usd       numeric(10,2) not null,
  exchange_rate   numeric(12,2) not null,
  total_lbp       numeric(14,0) not null,
  payment_method  text not null default 'cash' check (payment_method in ('cash','whish')),
  status          text not null default 'pending'
                  check (status in ('pending','awaiting_payment','paid','confirmed','failed','cancelled')),
  whish_currency  text,
  whish_txn_id    text,
  paid_at         timestamptz,
  invoice_pdf_url text default '',
  created_at      timestamptz not null default now()
);
create index if not exists orders_rest_idx  on public.orders (restaurant_id, created_at desc);
create index if not exists orders_token_idx on public.orders (token);

create table if not exists public.order_items (
  id         uuid primary key default gen_random_uuid(),
  order_id   bigint not null references public.orders(id) on delete cascade,
  item_id    uuid references public.items(id) on delete set null,
  name_ar    text not null,
  name_en    text not null,
  price_usd  numeric(10,2) not null,
  qty        integer not null check (qty > 0),
  line_usd   numeric(10,2) not null
);
create index if not exists order_items_idx on public.order_items (order_id);

-- ---------- بيانات الدفع (لا تُقرأ من المتصفح أبداً) ----------
create table if not exists public.payment_credentials (
  restaurant_id  uuid primary key references public.restaurants(id) on delete cascade,
  whish_enabled  boolean not null default false,
  whish_channel  text default '',
  whish_secret   text default '',
  whish_currency text not null default 'USD' check (whish_currency in ('USD','LBP')),
  website_url    text default 'https://libanapps.com',
  fee_on         text not null default 'restaurant' check (fee_on in ('restaurant','customer')),
  updated_at     timestamptz not null default now()
);

create or replace function public.set_whish_credentials(
  rid uuid, p_enabled boolean, p_channel text, p_secret text, p_currency text, p_fee_on text
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_member(rid) then raise exception 'not allowed'; end if;
  insert into public.payment_credentials (restaurant_id, whish_enabled, whish_channel,
                                          whish_secret, whish_currency, fee_on, updated_at)
  values (rid, p_enabled, p_channel, p_secret, p_currency, p_fee_on, now())
  on conflict (restaurant_id) do update set
    whish_enabled  = excluded.whish_enabled,
    whish_channel  = excluded.whish_channel,
    whish_secret   = case when excluded.whish_secret = '' then payment_credentials.whish_secret
                          else excluded.whish_secret end,
    whish_currency = excluded.whish_currency,
    fee_on         = excluded.fee_on,
    updated_at     = now();
  update public.restaurants set whish_enabled = p_enabled where id = rid;
end $$;

create or replace function public.whish_status(rid uuid)
returns table (enabled boolean, channel_hint text, has_secret boolean, currency text, fee_on text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_member(rid) then raise exception 'not allowed'; end if;
  return query
    select c.whish_enabled,
           case when c.whish_channel = '' then '' else '••••' || right(c.whish_channel, 4) end,
           c.whish_secret <> '', c.whish_currency, c.fee_on
    from public.payment_credentials c where c.restaurant_id = rid;
end $$;

-- ---------- تسجيل الطلب (الأسعار تُحسب هنا) ----------
create or replace function public.place_order(
  p_slug text, p_type text, p_name text, p_phone text, p_table text,
  p_address text, p_lat double precision, p_lng double precision,
  p_note text, p_payment text, p_lines jsonb
) returns table (order_id bigint, order_no text, token text, total_usd numeric, total_lbp numeric)
language plpgsql security definer set search_path = public as $$
declare
  r public.restaurants%rowtype;
  v_sub numeric(10,2) := 0; v_del numeric(10,2) := 0;
  v_tot numeric(10,2); v_lbp numeric(14,0);
  v_no text; v_id bigint; v_tok text;
  ln jsonb; it public.items%rowtype; v_qty integer;
begin
  select * into r from public.restaurants where slug = p_slug;
  if not found or not public.menu_live(r.id) then raise exception 'restaurant unavailable'; end if;
  if p_type = 'dine_in'  and not r.dinein_enabled   then raise exception 'dine-in disabled'; end if;
  if p_type = 'delivery' and not r.delivery_enabled then raise exception 'delivery disabled'; end if;
  if length(trim(p_name)) < 2 or length(regexp_replace(p_phone,'\D','','g')) < 7 then
    raise exception 'invalid customer details'; end if;
  if p_type = 'delivery' and r.require_location and (p_lat is null or p_lng is null) then
    raise exception 'location required'; end if;
  if jsonb_array_length(p_lines) = 0 or jsonb_array_length(p_lines) > 60 then
    raise exception 'invalid cart'; end if;

  r.order_seq := r.order_seq + 1;
  update public.restaurants set order_seq = r.order_seq where id = r.id;
  v_no := upper(left(r.slug, 2)) || '-' || (1000 + r.order_seq);

  insert into public.orders (restaurant_id, order_no, order_type, customer_name, customer_phone,
                             table_no, address_text, lat, lng, customer_note,
                             subtotal_usd, delivery_usd, total_usd, exchange_rate, total_lbp,
                             payment_method, status)
  values (r.id, v_no, p_type, trim(p_name), trim(p_phone),
          coalesce(p_table,''), coalesce(p_address,''), p_lat, p_lng, coalesce(p_note,''),
          0, 0, 0, r.exchange_rate, 0, p_payment,
          case when p_payment = 'whish' then 'awaiting_payment' else 'pending' end)
  returning id, token into v_id, v_tok;

  for ln in select * from jsonb_array_elements(p_lines) loop
    v_qty := greatest(1, least(50, (ln->>'qty')::int));
    select * into it from public.items
      where id = (ln->>'item_id')::uuid and restaurant_id = r.id and is_available;
    if found then
      insert into public.order_items (order_id, item_id, name_ar, name_en, price_usd, qty, line_usd)
      values (v_id, it.id, it.name_ar, it.name_en, it.price_usd, v_qty, it.price_usd * v_qty);
      v_sub := v_sub + it.price_usd * v_qty;
    end if;
  end loop;

  if v_sub = 0 then delete from public.orders where id = v_id; raise exception 'empty cart'; end if;
  if p_type = 'delivery' then
    if v_sub < r.min_order_usd then
      delete from public.orders where id = v_id; raise exception 'below minimum order'; end if;
    v_del := r.delivery_fee_usd;
  end if;

  v_tot := v_sub + v_del;
  v_lbp := round(v_tot * r.exchange_rate / r.lbp_rounding) * r.lbp_rounding;
  update public.orders set subtotal_usd = v_sub, delivery_usd = v_del,
         total_usd = v_tot, total_lbp = v_lbp where id = v_id;

  return query select v_id, v_no, v_tok, v_tot, v_lbp;
end $$;

create or replace function public.get_order(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders%rowtype; r public.restaurants%rowtype;
begin
  select * into o from public.orders where token = p_token;
  if not found then raise exception 'not found'; end if;
  select * into r from public.restaurants where id = o.restaurant_id;
  return jsonb_build_object(
    'order', to_jsonb(o) - 'restaurant_id',
    'restaurant', jsonb_build_object('name_ar',r.name_ar,'name_en',r.name_en,'logo_url',r.logo_url,
                                     'phone',r.phone,'slug',r.slug,'theme',r.theme,
                                     'default_lang',r.default_lang),
    'items', coalesce((select jsonb_agg(to_jsonb(oi) - 'order_id' - 'id')
                       from public.order_items oi where oi.order_id = o.id), '[]'::jsonb)
  );
end $$;

-- ---------- إنشاء مطعم كامل بضغطة (من لوحة التحكم) ----------
create or replace function public.new_restaurant(
  p_client uuid, p_slug text, p_name_ar text, p_name_en text,
  p_phone text, p_whatsapp text, p_theme text, p_days integer, p_price numeric default 0
) returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.restaurants%rowtype; s public.subscriptions;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  insert into public.restaurants (client_id, slug, name_ar, name_en, phone, whatsapp, theme)
  values (p_client, lower(trim(p_slug)), p_name_ar, coalesce(nullif(p_name_en,''), p_name_ar),
          p_phone, regexp_replace(coalesce(p_whatsapp,''),'\D','','g'), coalesce(p_theme,'flame'))
  returning * into r;

  insert into public.subscriptions (client_id, product_code, key, plan, expires_at, price_usd, ref_slug)
  values (p_client, 'menu', public.gen_license_key('menu'),
          case when p_days <= 7 then 'trial' when p_days <= 31 then 'monthly' else 'yearly' end,
          now() + make_interval(days => greatest(1,p_days)), coalesce(p_price,0), r.slug)
  returning * into s;

  insert into public.categories (restaurant_id, name_ar, name_en, sort) values
    (r.id,'الأصناف','Menu',1) on conflict do nothing;

  return jsonb_build_object('restaurant_id', r.id, 'slug', r.slug,
                            'key', s.key, 'expires_at', s.expires_at);
end $$;

-- ============================================================
--  القسم ج — RLS
-- ============================================================
alter table public.products            enable row level security;
alter table public.clients             enable row level security;
alter table public.subscriptions       enable row level security;
alter table public.restaurants         enable row level security;
alter table public.licenses            enable row level security;
alter table public.platform_admins     enable row level security;
alter table public.restaurant_users    enable row level security;
alter table public.categories          enable row level security;
alter table public.items               enable row level security;
alter table public.banners             enable row level security;
alter table public.promos              enable row level security;
alter table public.orders              enable row level security;
alter table public.order_items         enable row level security;
alter table public.payment_credentials enable row level security;

-- الزبائن والاشتراكات: أنت فقط
drop policy if exists adm_clients on public.clients;
create policy adm_clients on public.clients for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists adm_subs on public.subscriptions;
create policy adm_subs on public.subscriptions for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists pub_products on public.products;
create policy pub_products on public.products for select to anon, authenticated using (true);

-- المنيو العام
drop policy if exists pub_restaurants on public.restaurants;
create policy pub_restaurants on public.restaurants for select to anon, authenticated
  using (public.menu_live(id));

drop policy if exists pub_categories on public.categories;
create policy pub_categories on public.categories for select to anon, authenticated
  using (is_active and public.menu_live(restaurant_id));

drop policy if exists pub_items on public.items;
create policy pub_items on public.items for select to anon, authenticated
  using (public.menu_live(restaurant_id));

drop policy if exists pub_banners on public.banners;
create policy pub_banners on public.banners for select to anon, authenticated
  using (is_active and public.menu_live(restaurant_id));

drop policy if exists pub_promos on public.promos;
create policy pub_promos on public.promos for select to anon, authenticated
  using (is_active and public.menu_live(restaurant_id)
         and (starts_at is null or starts_at <= now())
         and (ends_at is null or ends_at >= now()));

-- لوحة صاحب المطعم
drop policy if exists own_restaurants on public.restaurants;
create policy own_restaurants on public.restaurants for update to authenticated
  using (public.is_member(id)) with check (public.is_member(id));

drop policy if exists own_categories on public.categories;
create policy own_categories on public.categories for all to authenticated
  using (public.is_member(restaurant_id)) with check (public.is_member(restaurant_id));

drop policy if exists own_items on public.items;
create policy own_items on public.items for all to authenticated
  using (public.is_member(restaurant_id)) with check (public.is_member(restaurant_id));

drop policy if exists own_banners on public.banners;
create policy own_banners on public.banners for all to authenticated
  using (public.is_member(restaurant_id)) with check (public.is_member(restaurant_id));

drop policy if exists own_promos on public.promos;
create policy own_promos on public.promos for all to authenticated
  using (public.is_member(restaurant_id)) with check (public.is_member(restaurant_id));

drop policy if exists own_orders on public.orders;
create policy own_orders on public.orders for select to authenticated
  using (public.is_member(restaurant_id));

drop policy if exists own_orders_upd on public.orders;
create policy own_orders_upd on public.orders for update to authenticated
  using (public.is_member(restaurant_id)) with check (public.is_member(restaurant_id));

drop policy if exists own_order_items on public.order_items;
create policy own_order_items on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o
                 where o.id = order_id and public.is_member(o.restaurant_id)));

drop policy if exists own_license_read on public.licenses;
create policy own_license_read on public.licenses for select to authenticated
  using (public.is_member(restaurant_id));

drop policy if exists own_membership on public.restaurant_users;
create policy own_membership on public.restaurant_users for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- أنت: كل شي
drop policy if exists adm_restaurants on public.restaurants;
create policy adm_restaurants on public.restaurants for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists adm_licenses on public.licenses;
create policy adm_licenses on public.licenses for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists adm_users on public.restaurant_users;
create policy adm_users on public.restaurant_users for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists adm_admins on public.platform_admins;
create policy adm_admins on public.platform_admins for select to authenticated
  using (public.is_admin());

-- payment_credentials: بدون أي سياسة قراءة أو كتابة — عمداً.
-- الكتابة عبر set_whish_credentials() فقط، والقراءة عبر service_role فقط.

-- ============================================================
--  القسم د — التخزين (بعد إنشاء الـbuckets من الواجهة)
--  buckets: logos, items, banners, invoices   (كلها Public)
-- ============================================================
do $$ begin
  execute 'drop policy if exists "libanapps read media" on storage.objects';
  execute 'create policy "libanapps read media" on storage.objects for select to anon, authenticated
           using (bucket_id in (''logos'',''items'',''banners'',''invoices''))';
  execute 'drop policy if exists "libanapps write media" on storage.objects';
  execute 'create policy "libanapps write media" on storage.objects for insert to authenticated
           with check (bucket_id in (''logos'',''items'',''banners''))';
  execute 'drop policy if exists "libanapps update media" on storage.objects';
  execute 'create policy "libanapps update media" on storage.objects for update to authenticated
           using (bucket_id in (''logos'',''items'',''banners''))';
exception when others then
  raise notice 'storage policies skipped: %', sqlerrm;
end $$;

-- ============================================================
--  القسم هـ — أول تشغيل
-- ============================================================
-- 1) سجّل حسابك بالتطبيق، ثم من Authentication > Users انسخ الـUUID:
--    insert into public.platform_admins (user_id) values ('<UUID>')
--    on conflict do nothing;
--
-- 2) بعدها كل شي بينعمل من لوحة super.html
