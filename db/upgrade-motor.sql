-- ============================================================
--  LibanApps — برنامج «اشتراكات المولّدات» (motorapp)   code = motor
--
--  بيضيف:
--   • منتج جديد motor (بادئة المفتاح MOTR) + باقة (غير منشورة لحين تحديد السعر من /super)
--   • جداول: المولّدات (المؤسسات)، أنواع الاشتراك، الموظفين (الجباة)، الزبائن،
--     قراءات العدادات، الفواتير، الإيصالات، حركات الصندوق (تسليم الجابي / Whish)
--   • دخول الموظفين باسم مستخدم وكلمة مرور (بدون حساب Supabase) — كلمات السر مشفّرة
--   • صاحب الاشتراك يدخل من حسابه على المنصة كمدير كامل
--   • كل العمليات عبر دوال security definer — الجداول مقفلة على المتصفح بالكامل
--
--  آمن للتشغيل أكثر من مرة — ما بيحذف ولا بيغيّر بيانات موجودة.
--  شرط مسبق: schema.sql + upgrade-apps-tenancy.sql + upgrade-portal-users.sql
--            + security-fixes-1.sql (فيها is_portal_user)
-- ============================================================

create extension if not exists "pgcrypto";

-- ============================================================
--  1) المنتج والباقة
-- ============================================================
insert into public.products (code, name_ar, name_en, prefix) values
  ('motor', 'اشتراكات المولّدات', 'LibanApps Motor', 'MOTR')
on conflict (code) do nothing;

alter table public.products add column if not exists trial_days integer;
update public.products set trial_days = 7 where code = 'motor' and trial_days is null;
alter table public.plans add column if not exists renew_price_usd numeric(10,2);

-- الباقة غير منشورة (is_active = false) لحين تحديد السعر من /super
insert into public.plans (product_code, name_ar, name_en, days, price_usd, renew_price_usd, badge_ar,
                          features_ar, features_en, sort, is_active)
select 'motor', 'اشتراكات المولّد — سنة', 'Generator subscriptions — 1 year', 365, 0, 0, 'جديد',
  array['ملف كامل لكل مشترك مع الباركود والموقع',
        'الجابي يقرأ العداد بمسح الباركود + صورة + الموقع الجغرافي',
        'فاتورة تلقائية حسب نوع الاشتراك وسعر الكيلوواط',
        'إرسال الفاتورة والإيصال عبر واتساب',
        'طباعة الإيصال على طابعة بلوتوث',
        'كشف حساب لكل مشترك ولكل جابي وكشف Whish',
        'استيراد المشتركين من Excel'],
  array['Full profile per subscriber with barcode and location',
        'Collector reads the meter by scanning the barcode + photo + GPS',
        'Automatic invoice by subscription type and kWh price',
        'Send invoices and receipts via WhatsApp',
        'Print receipts on a Bluetooth printer',
        'Statements per subscriber, per collector and for Whish',
        'Import subscribers from Excel'], 7, false
where not exists (select 1 from public.plans where product_code = 'motor');
-- السعر: 160$ سنوياً (أول سنة والتجديد) — يُطبَّق مرة وحدة فقط إذا كانت الباقة بعدها على صفر
update public.plans set price_usd = 160, renew_price_usd = 160, is_active = true,
       name_ar = 'اشتراكات المولّد — سنة'
 where product_code = 'motor' and price_usd = 0;

-- إعدادات البرنامج من لوحة /super
create or replace function public.admin_motor_product(
  p_price numeric, p_renew numeric, p_trial integer, p_active boolean default true
) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update public.products set trial_days = greatest(0, least(60, coalesce(p_trial, 7))) where code = 'motor';
  update public.plans set price_usd = greatest(0, coalesce(p_price, price_usd)),
                          renew_price_usd = greatest(0, coalesce(p_renew, renew_price_usd)),
                          is_active = coalesce(p_active, is_active)
   where product_code = 'motor';
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  2) الجداول
-- ============================================================
create table if not exists public.motor_sites (
  id              uuid primary key default gen_random_uuid(),
  client_id       uuid not null references public.clients(id) on delete cascade,
  slug            text unique not null,
  name            text not null default '',
  logo_url        text not null default '',
  phone           text not null default '',
  whatsapp        text not null default '',
  address         text not null default '',
  currency        text not null default 'USD' check (currency in ('USD','LBP')),
  lbp_rate        numeric(14,2) not null default 89500,
  show_second     boolean not null default true,
  kwh_price       numeric(14,4) not null default 0,
  round_step      numeric(14,2) not null default 0,     -- تقريب الفاتورة (0 = بدون)
  bill_period     text not null default to_char(now() at time zone 'Asia/Beirut', 'YYYY-MM'),
  max_distance_m  integer not null default 0,           -- 0 = تسجيل المسافة فقط بلا منع
  require_photo   boolean not null default true,
  require_gps     boolean not null default true,
  collector_sees_all boolean not null default true,
  barcode_prefix  text not null default 'M',
  invoice_note    text not null default '',
  default_lang    text not null default 'ar' check (default_lang in ('ar','en','fr')),
  cust_seq        integer not null default 0,
  invoice_seq     integer not null default 0,
  receipt_seq     integer not null default 0,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now()
);
create index if not exists motor_sites_client_idx on public.motor_sites (client_id);
-- أول قراءة لزبون بلا عداد سابق تُعتمد عداداً أولياً (بلا استهلاك) — مفيد بعد استيراد الزبائن من برنامج آخر
alter table public.motor_sites add column if not exists first_read_baseline boolean not null default true;
do $$ begin
  alter table public.motor_sites add constraint motor_sites_slug_format check (slug ~ '^[a-z0-9][a-z0-9-]{1,30}$');
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.motor_sites add constraint motor_sites_period_format check (bill_period ~ '^\d{4}-\d{2}$');
exception when duplicate_object then null; end $$;

create table if not exists public.motor_plans (
  id         uuid primary key default gen_random_uuid(),
  site_id    uuid not null references public.motor_sites(id) on delete cascade,
  name       text not null,
  amps       numeric(8,2) not null default 0,
  kind       text not null default 'meter' check (kind in ('meter','fixed')),  -- عدّاد / مقطوع
  fee        numeric(14,2) not null default 0,     -- قيمة الاشتراك الأساسي الشهري
  kwh_price  numeric(14,4),                        -- فاضي = سعر الكيلوواط العام
  is_active  boolean not null default true,
  sort       integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists motor_plans_site_idx on public.motor_plans (site_id);
create unique index if not exists motor_plans_name_uq on public.motor_plans (site_id, lower(name));

create table if not exists public.motor_staff (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references public.motor_sites(id) on delete cascade,
  name        text not null,
  username    text not null,
  phone       text not null default '',
  role        text not null default 'collector' check (role in ('admin','collector')),
  is_active   boolean not null default true,
  read_from   date,                 -- فترة أخذ العدادات المسموحة
  read_to     date,
  can_collect boolean not null default true,
  created_at  timestamptz not null default now()
);
create unique index if not exists motor_staff_user_uq on public.motor_staff (site_id, lower(username));

create table if not exists public.motor_staff_secrets (
  staff_id      uuid primary key references public.motor_staff(id) on delete cascade,
  password_hash text not null,
  failed_count  integer not null default 0,
  locked_until  timestamptz,
  updated_at    timestamptz not null default now()
);

create table if not exists public.motor_sessions (
  token_hash text primary key,
  staff_id   uuid not null references public.motor_staff(id) on delete cascade,
  site_id    uuid not null references public.motor_sites(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 days'
);
create index if not exists motor_sessions_staff_idx on public.motor_sessions (staff_id);

create table if not exists public.motor_customers (
  id              uuid primary key default gen_random_uuid(),
  site_id         uuid not null references public.motor_sites(id) on delete cascade,
  code            integer not null default 0,
  name            text not null,
  alt_name        text not null default '',
  plan_id         uuid references public.motor_plans(id) on delete set null,
  building        text not null default '',
  floor           text not null default '',
  side            text not null default '',
  box             text not null default '',          -- العلبة
  generator       text not null default '',          -- المولد / الكابل
  breaker_no      text not null default '',          -- رقم الدجنتير
  meter_no        text not null default '',          -- رقم العداد
  barcode         text not null default '',          -- باركود العداد
  location_name   text not null default '',
  location_code   text not null default '',
  lat             double precision,
  lng             double precision,
  area            text not null default '',
  area_code       text not null default '',
  zone            text not null default '',          -- النطاق
  category        text not null default '',
  category2       text not null default '',
  collector_id    uuid references public.motor_staff(id) on delete set null,
  collector_name  text not null default '',
  sub_date        date,
  is_active       boolean not null default true,
  stopped_at      timestamptz,
  stopped_by      text not null default '',
  credit_limit    numeric(14,2),
  charge_discount numeric(14,2) not null default 0,
  discount_desc   text not null default '',
  charge_addition numeric(14,2) not null default 0,
  addition_desc   text not null default '',
  initial_reading numeric(14,2) not null default 0,
  balance         numeric(14,2) not null default 0,  -- الدين الحالي (يتحدّث من الفواتير والإيصالات فقط)
  mobile          text not null default '',
  mobile_cc       text not null default '961',
  mobile2         text not null default '',
  phone           text not null default '',
  address         text not null default '',
  email           text not null default '',
  nationality     text not null default '',
  archived        boolean not null default false,
  collect_day     integer,
  notes           text not null default '',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists motor_customers_site_idx on public.motor_customers (site_id, name);
create unique index if not exists motor_customers_barcode_uq on public.motor_customers (site_id, lower(barcode)) where barcode <> '';

create table if not exists public.motor_readings (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references public.motor_sites(id) on delete cascade,
  customer_id uuid not null references public.motor_customers(id) on delete cascade,
  period      text not null,
  prev_value  numeric(14,2) not null default 0,
  value       numeric(14,2) not null,
  photo_url   text not null default '',
  lat         double precision,
  lng         double precision,
  accuracy    double precision,
  dist_m      integer,
  staff_id    uuid references public.motor_staff(id) on delete set null,
  staff_name  text not null default '',
  created_at  timestamptz not null default now()
);
create unique index if not exists motor_readings_once_uq on public.motor_readings (customer_id, period);
create index if not exists motor_readings_site_idx on public.motor_readings (site_id, period);

create table if not exists public.motor_invoices (
  id             uuid primary key default gen_random_uuid(),
  site_id        uuid not null references public.motor_sites(id) on delete cascade,
  no             integer not null default 0,
  customer_id    uuid not null references public.motor_customers(id) on delete cascade,
  period         text not null default '',
  kind           text not null default 'meter' check (kind in ('meter','fixed','opening','adjust')),
  reading_id     uuid references public.motor_readings(id) on delete set null,
  plan_name      text not null default '',
  prev_value     numeric(14,2),
  cur_value      numeric(14,2),
  kwh            numeric(14,2) not null default 0,
  kwh_price      numeric(14,4) not null default 0,
  fee            numeric(14,2) not null default 0,
  energy         numeric(14,2) not null default 0,
  discount       numeric(14,2) not null default 0,
  addition       numeric(14,2) not null default 0,
  amount         numeric(14,2) not null default 0,
  balance_before numeric(14,2) not null default 0,
  balance_after  numeric(14,2) not null default 0,
  note           text not null default '',
  staff_id       uuid references public.motor_staff(id) on delete set null,
  staff_name     text not null default '',
  voided         boolean not null default false,
  voided_at      timestamptz,
  voided_by      text not null default '',
  created_at     timestamptz not null default now()
);
create index if not exists motor_invoices_cust_idx on public.motor_invoices (customer_id, created_at);
create index if not exists motor_invoices_site_idx on public.motor_invoices (site_id, period);

create table if not exists public.motor_payments (
  id             uuid primary key default gen_random_uuid(),
  site_id        uuid not null references public.motor_sites(id) on delete cascade,
  no             integer not null default 0,
  customer_id    uuid not null references public.motor_customers(id) on delete cascade,
  amount         numeric(14,2) not null,               -- بالعملة الأساسية
  paid_currency  text not null default 'USD' check (paid_currency in ('USD','LBP')),
  paid_amount    numeric(16,2) not null default 0,     -- المبلغ كما قُبض
  rate           numeric(14,2) not null default 0,
  method         text not null default 'cash' check (method in ('cash','whish')),
  balance_before numeric(14,2) not null default 0,
  balance_after  numeric(14,2) not null default 0,
  note           text not null default '',
  lat            double precision,
  lng            double precision,
  staff_id       uuid references public.motor_staff(id) on delete set null,
  staff_name     text not null default '',
  voided         boolean not null default false,
  voided_at      timestamptz,
  voided_by      text not null default '',
  created_at     timestamptz not null default now()
);
create index if not exists motor_payments_cust_idx on public.motor_payments (customer_id, created_at);
create index if not exists motor_payments_site_idx on public.motor_payments (site_id, created_at);
create index if not exists motor_payments_staff_idx on public.motor_payments (staff_id, created_at);

-- حركات الحسابات: تسليم الجابي للمكتب، سحب/إيداع Whish، تسوية
create table if not exists public.motor_moves (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references public.motor_sites(id) on delete cascade,
  account     text not null check (account in ('collector','whish')),
  staff_id    uuid references public.motor_staff(id) on delete cascade,
  kind        text not null check (kind in ('handover','withdraw','deposit','adjust')),
  amount      numeric(14,2) not null,
  note        text not null default '',
  by_name     text not null default '',
  created_at  timestamptz not null default now()
);
create index if not exists motor_moves_site_idx on public.motor_moves (site_id, account, created_at);

-- ---------- إضافات v2 ----------
alter table public.motor_sites add column if not exists tagline        text not null default '';
alter table public.motor_sites add column if not exists cur_label      text not null default '';      -- مثلاً «د.أ» بدل $
alter table public.motor_sites add column if not exists wa_from_office boolean not null default true; -- واتساب يُرسَل من المكتب فقط

alter table public.motor_staff add column if not exists can_read     boolean not null default true;   -- أخذ العداد
alter table public.motor_staff add column if not exists can_cut      boolean not null default false;  -- فتح/قطع الاشتراك
alter table public.motor_staff add column if not exists totp_enabled boolean not null default false;
alter table public.motor_staff add column if not exists last_lat     double precision;
alter table public.motor_staff add column if not exists last_lng     double precision;
alter table public.motor_staff add column if not exists last_acc     double precision;
alter table public.motor_staff add column if not exists last_seen    timestamptz;

alter table public.motor_staff_secrets add column if not exists totp_secret  text;
alter table public.motor_staff_secrets add column if not exists totp_pending text;

alter table public.motor_invoices add column if not exists wa_sent_at timestamptz;
alter table public.motor_invoices add column if not exists wa_sent_by text not null default '';
alter table public.motor_payments add column if not exists wa_sent_at timestamptz;
alter table public.motor_payments add column if not exists wa_sent_by text not null default '';

-- الصندوق: account = cash (in / out / close / adjust)
alter table public.motor_moves add column if not exists extra jsonb not null default '{}'::jsonb;
alter table public.motor_moves drop constraint if exists motor_moves_account_check;
alter table public.motor_moves add constraint motor_moves_account_check check (account in ('collector','whish','cash'));
alter table public.motor_moves drop constraint if exists motor_moves_kind_check;
alter table public.motor_moves add constraint motor_moves_kind_check check (kind in ('handover','withdraw','deposit','adjust','in','out','close'));

-- ملاحظات الموظفين على الزبون
create table if not exists public.motor_notes (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references public.motor_sites(id) on delete cascade,
  customer_id uuid not null references public.motor_customers(id) on delete cascade,
  body        text not null,
  staff_id    uuid references public.motor_staff(id) on delete set null,
  staff_name  text not null default '',
  created_at  timestamptz not null default now()
);
create index if not exists motor_notes_cust_idx on public.motor_notes (customer_id, created_at desc);

-- سجل فتح/قطع الاشتراك
create table if not exists public.motor_switch_log (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references public.motor_sites(id) on delete cascade,
  customer_id uuid not null references public.motor_customers(id) on delete cascade,
  action      text not null check (action in ('cut','connect')),
  note        text not null default '',
  lat         double precision,
  lng         double precision,
  staff_id    uuid references public.motor_staff(id) on delete set null,
  staff_name  text not null default '',
  created_at  timestamptz not null default now()
);
create index if not exists motor_switch_cust_idx on public.motor_switch_log (customer_id, created_at desc);
create index if not exists motor_customers_upd_idx on public.motor_customers (site_id, updated_at);

-- كل الجداول مقفلة على المتصفح — الوصول عبر الدوال فقط
do $$
declare t text;
begin
  foreach t in array array['motor_sites','motor_plans','motor_staff','motor_staff_secrets','motor_sessions',
                           'motor_customers','motor_readings','motor_invoices','motor_payments','motor_moves',
                           'motor_notes','motor_switch_log']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ============================================================
--  3) الترخيص والإنشاء
-- ============================================================
create or replace function public.motor_license(p_site uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st public.motor_sites%rowtype; s public.subscriptions%rowtype;
begin
  select * into st from public.motor_sites where id = p_site;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select * into s from public.subscriptions
   where client_id = st.client_id and product_code = 'motor' and ref_slug = st.slug
   order by expires_at desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no_subscription'); end if;
  return jsonb_build_object(
    'ok',        (s.status = 'active' and s.expires_at > now()),
    'reason',    case when s.status <> 'active' then 'suspended'
                      when s.expires_at <= now() then 'expired' else 'active' end,
    'plan',      s.plan,
    'trial',     (s.plan = 'trial'),
    'expires_at', s.expires_at,
    'days_left', greatest(0, ceil(extract(epoch from (s.expires_at - now()))/86400))::int);
end $$;
revoke all on function public.motor_license(uuid) from public, anon, authenticated;

create or replace function public.motor_slug_available(p_slug text)
returns boolean language sql stable security definer set search_path = public as $$
  select lower(trim(coalesce(p_slug,''))) ~ '^[a-z0-9][a-z0-9-]{1,30}$'
     and not exists (select 1 from public.motor_sites where slug = lower(trim(p_slug)))
     and not exists (select 1 from public.subscriptions
                     where product_code = 'motor' and ref_slug = lower(trim(p_slug)));
$$;

create or replace function public._make_motor(p_client uuid, p_slug text, p_name text)
returns public.motor_sites language plpgsql security definer set search_path = public as $$
declare c public.clients%rowtype; st public.motor_sites;
begin
  select * into c from public.clients where id = p_client;
  insert into public.motor_sites (client_id, slug, name, phone, whatsapp)
  values (p_client, p_slug, coalesce(nullif(trim(p_name),''), p_slug),
          coalesce(c.phone,''), regexp_replace(coalesce(c.phone,''),'\D','','g'))
  returning * into st;
  insert into public.motor_plans (site_id, name, amps, kind, fee, sort) values
    (st.id, '5A',  5,  'meter', 0, 1),
    (st.id, '10A', 10, 'meter', 0, 2),
    (st.id, '15A', 15, 'meter', 0, 3),
    (st.id, '20A', 20, 'meter', 0, 4);
  return st;
end $$;
revoke all on function public._make_motor(uuid, text, text) from public, anon, authenticated;

create or replace function public.admin_new_motor(
  p_client uuid, p_slug text, p_biz text, p_days integer, p_price numeric default 0
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_slug text; st public.motor_sites; s public.subscriptions;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  v_slug := lower(trim(coalesce(p_slug,'')));
  if v_slug !~ '^[a-z0-9][a-z0-9-]{1,30}$' then raise exception 'invalid slug'; end if;
  if not public.motor_slug_available(v_slug) then raise exception 'slug taken'; end if;
  st := public._make_motor(p_client, v_slug, p_biz);
  insert into public.subscriptions (client_id, product_code, key, plan, expires_at, price_usd, ref_slug, notes)
  values (p_client, 'motor', public.gen_license_key('motor'),
          case when p_days <= 7 then 'trial' when p_days <= 31 then 'monthly' else 'yearly' end,
          now() + make_interval(days => greatest(1, p_days)),
          coalesce(p_price,0), v_slug, 'إصدار يدوي')
  returning * into s;
  return jsonb_build_object('ok', true, 'key', s.key, 'expires_at', s.expires_at, 'slug', v_slug);
end $$;

create or replace function public.start_motor_trial(p_slug text, p_biz text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare cid uuid; v_slug text; d integer; s public.subscriptions; st public.motor_sites;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select id into cid from public.clients where user_id = auth.uid();
  if cid is null then raise exception 'complete your profile first'; end if;
  if exists (select 1 from public.subscriptions where client_id = cid and product_code = 'motor') then
    return jsonb_build_object('ok', false, 'reason', 'لديك اشتراك أو تجربة سابقة لهذا البرنامج');
  end if;
  v_slug := lower(trim(coalesce(p_slug,'')));
  if v_slug !~ '^[a-z0-9][a-z0-9-]{1,30}$' then
    return jsonb_build_object('ok', false, 'reason', 'يجب أن يكون الرابط بأحرف إنكليزية وأرقام وشَرطة، بطول بين 2 و31 حرفًا');
  end if;
  if not public.motor_slug_available(v_slug) then
    return jsonb_build_object('ok', false, 'reason', 'هذا الرابط محجوز — اختر رابطًا آخر');
  end if;
  select coalesce(trial_days, 7) into d from public.products where code = 'motor';
  if coalesce(d,0) <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'التجربة المجانية غير متاحة حاليًا لهذا البرنامج');
  end if;
  st := public._make_motor(cid, v_slug, p_biz);
  insert into public.subscriptions (client_id, product_code, key, plan, expires_at, price_usd, ref_slug, notes)
  values (cid, 'motor', public.gen_license_key('motor'), 'trial',
          now() + make_interval(days => d), 0, v_slug, 'تجربة مجانية')
  returning * into s;
  return jsonb_build_object('ok', true, 'key', s.key, 'expires_at', s.expires_at,
                            'days', d, 'slug', v_slug, 'subscription_id', s.id);
end $$;

-- اشتراك motor انعمل من الشراء بدون مؤسسة — منبنيها أول ما يفتح صاحبها البرنامج
create or replace function public.ensure_motor(p_slug text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_slug text; st public.motor_sites; cid uuid; s public.subscriptions; bn text;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'reason', 'not_signed_in'); end if;
  v_slug := lower(trim(coalesce(p_slug,'')));
  select * into st from public.motor_sites where slug = v_slug;
  if found then return jsonb_build_object('ok', true, 'slug', st.slug); end if;
  if public.is_portal_user() then return jsonb_build_object('ok', false, 'reason', 'not_owner'); end if;
  cid := public.my_client_id();
  if cid is null then return jsonb_build_object('ok', false, 'reason', 'no_client'); end if;
  select * into s from public.subscriptions
   where client_id = cid and product_code = 'motor' and ref_slug = v_slug limit 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no_subscription'); end if;
  -- اسم المؤسسة كما كتبه وقت الشراء
  if to_regclass('public.purchases') is not null then
    execute 'select biz_name from public.purchases where client_id = $1 and product_code = ''motor'' and slug = $2 order by id desc limit 1'
       into bn using cid, v_slug;
  end if;
  st := public._make_motor(cid, v_slug, coalesce(bn, ''));
  return jsonb_build_object('ok', true, 'slug', st.slug);
end $$;

-- ============================================================
--  4) الهوية: مين عم يستعمل البرنامج؟
--     · رمز جلسة موظف (p_token)  → admin / collector
--     · أو صاحب الاشتراك بحساب المنصة (أو مشرف المنصة) → owner
-- ============================================================
create or replace function public._motor_err(p_code text, p_detail text default '')
returns void language plpgsql as $$
begin
  raise exception '%', 'MOTOR:' || p_code || case when coalesce(p_detail,'') <> '' then ':' || p_detail else '' end
    using errcode = 'P0001';
end $$;

create or replace function public._motor_who(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare st public.motor_sites%rowtype; sf public.motor_staff%rowtype; sid uuid; lic jsonb; cn text;
begin
  select * into st from public.motor_sites where slug = lower(trim(coalesce(p_slug,'')));
  if not found then perform public._motor_err('not_found'); end if;

  if coalesce(p_token,'') <> '' then
    select s.staff_id into sid from public.motor_sessions s
     where s.token_hash = encode(digest(p_token,'sha256'),'hex') and s.expires_at > now() and s.site_id = st.id;
    if sid is null then perform public._motor_err('auth'); end if;
    select * into sf from public.motor_staff where id = sid;
    if not found or not sf.is_active then perform public._motor_err('auth'); end if;
  elsif auth.uid() is not null and (public.is_admin()
        or (not public.is_portal_user() and st.client_id = public.my_client_id())) then
    sf := null;
  else
    perform public._motor_err('auth');
  end if;

  if not public.is_admin() then
    if not st.is_active then perform public._motor_err('inactive'); end if;
    lic := public.motor_license(st.id);
    if not coalesce((lic->>'ok')::boolean, false) then perform public._motor_err('license', lic->>'reason'); end if;
  end if;

  if sf.id is null then
    select coalesce(nullif(c.name,''), 'Owner') into cn from public.clients c where c.id = st.client_id;
    return jsonb_build_object('site_id', st.id, 'role', 'owner', 'staff_id', null, 'name', coalesce(cn,'Owner'),
                              'is_admin', true, 'can_collect', true, 'can_read', true, 'can_cut', true,
                              'totp_enabled', false, 'read_from', null, 'read_to', null);
  end if;
  return jsonb_build_object('site_id', st.id, 'role', sf.role, 'staff_id', sf.id, 'name', sf.name,
                            'is_admin', sf.role = 'admin',
                            'can_collect', sf.role = 'admin' or sf.can_collect,
                            'can_read', sf.role = 'admin' or sf.can_read,
                            'can_cut', sf.role = 'admin' or sf.can_cut,
                            'totp_enabled', sf.totp_enabled,
                            'read_from', sf.read_from, 'read_to', sf.read_to);
end $$;
revoke all on function public._motor_who(text, text) from public, anon, authenticated;

create or replace function public._motor_admin(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_who(p_slug, p_token);
  if not (w->>'is_admin')::boolean then perform public._motor_err('forbidden'); end if;
  return w;
end $$;
revoke all on function public._motor_admin(text, text) from public, anon, authenticated;

create or replace function public._motor_today()
returns date language sql stable as $$ select (now() at time zone 'Asia/Beirut')::date; $$;

create or replace function public._motor_round(p_site uuid, p_v numeric)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare st public.motor_sites%rowtype;
begin
  select * into st from public.motor_sites where id = p_site;
  if coalesce(st.round_step,0) > 0 then return round(p_v / st.round_step) * st.round_step; end if;
  if st.currency = 'LBP' then return round(p_v, 0); end if;
  return round(p_v, 2);
end $$;

-- إحداثيات صالحة؟ (القيم الوهمية 33.3333/33.3344 من البرامج القديمة = بلا موقع)
create or replace function public._motor_geo_ok(p_lat double precision, p_lng double precision)
returns boolean language sql immutable as $$
  select p_lat is not null and p_lng is not null and p_lat between -90 and 90 and p_lng between -180 and 180
     and not (p_lat = 0 and p_lng = 0)
     and not (round(p_lat::numeric,4) = 33.3333 and round(p_lng::numeric,4) = 33.3344);
$$;

create or replace function public._motor_dist(lat1 double precision, lng1 double precision,
                                              lat2 double precision, lng2 double precision)
returns integer language sql immutable as $$
  select round(2 * 6371000 * asin(sqrt(
           power(sin(radians(lat2 - lat1) / 2), 2) +
           cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))))::int;
$$;

-- ---------- TOTP (RFC 6238) للتحقق بخطوتين ----------
create or replace function public._motor_b32_decode(s text)
returns bytea language plpgsql immutable as $$
declare alphabet text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; bits text := ''; i int; idx int; o bytea := ''::bytea;
begin
  s := upper(regexp_replace(coalesce(s,''), '[^A-Za-z2-7]', '', 'g'));
  for i in 1..length(s) loop
    idx := strpos(alphabet, substr(s, i, 1)) - 1;
    if idx >= 0 then bits := bits || lpad(idx::bit(5)::text, 5, '0'); end if;
  end loop;
  i := 1;
  while i + 7 <= length(bits) loop
    o := o || set_byte('\x00'::bytea, 0, substr(bits, i, 8)::bit(8)::int);
    i := i + 8;
  end loop;
  return o;
end $$;

create or replace function public._motor_b32_encode(b bytea)
returns text language plpgsql immutable as $$
declare alphabet text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; bits text := ''; i int; o text := '';
begin
  for i in 0..length(b)-1 loop bits := bits || get_byte(b, i)::bit(8)::text; end loop;
  while length(bits) % 5 <> 0 loop bits := bits || '0'; end loop;
  i := 1;
  while i <= length(bits) loop
    o := o || substr(alphabet, substr(bits, i, 5)::bit(5)::int + 1, 1);
    i := i + 5;
  end loop;
  return o;
end $$;

create or replace function public._motor_totp_ok(p_secret text, p_code text)
returns boolean language plpgsql stable set search_path = public, extensions as $$
declare key bytea := public._motor_b32_decode(p_secret); w int; ctr bigint; msg bytea; h bytea; off int; bin bigint;
begin
  if p_code is null or p_code !~ '^\d{6}$' or length(key) = 0 then return false; end if;
  for w in -1..1 loop
    ctr := floor(extract(epoch from now()) / 30)::bigint + w;
    msg := decode(lpad(to_hex(ctr), 16, '0'), 'hex');
    h := hmac(msg, key, 'sha1');
    off := get_byte(h, 19) & 15;
    bin := ((get_byte(h, off) & 127)::bigint << 24) | (get_byte(h, off+1)::bigint << 16)
         | (get_byte(h, off+2)::bigint << 8) | get_byte(h, off+3)::bigint;
    if lpad((bin % 1000000)::text, 6, '0') = p_code then return true; end if;
  end loop;
  return false;
end $$;
revoke all on function public._motor_totp_ok(text, text) from public, anon, authenticated;

-- ============================================================
--  5) الصفحة العامة + الدخول والخروج
-- ============================================================
create or replace function public.motor_public(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st public.motor_sites%rowtype; lic jsonb;
begin
  select * into st from public.motor_sites where slug = lower(trim(coalesce(p_slug,'')));
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  lic := public.motor_license(st.id);
  return jsonb_build_object(
    'ok', st.is_active and coalesce((lic->>'ok')::boolean,false),
    'reason', case when not st.is_active then 'inactive' else lic->>'reason' end,
    'site', jsonb_build_object('name', st.name, 'logo_url', st.logo_url, 'slug', st.slug,
                               'default_lang', st.default_lang));
end $$;

drop function if exists public.motor_login(text, text, text);
create or replace function public.motor_login(p_slug text, p_username text, p_password text, p_totp text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare st public.motor_sites%rowtype; sf public.motor_staff%rowtype; sc public.motor_staff_secrets%rowtype;
        tok text; lic jsonb;
begin
  select * into st from public.motor_sites where slug = lower(trim(coalesce(p_slug,'')));
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  lic := public.motor_license(st.id);
  if not st.is_active or not coalesce((lic->>'ok')::boolean,false) then
    return jsonb_build_object('ok', false, 'reason', 'license');
  end if;
  select * into sf from public.motor_staff
   where site_id = st.id and lower(username) = lower(trim(coalesce(p_username,'')));
  if not found then perform pg_sleep(0.4); return jsonb_build_object('ok', false, 'reason', 'bad_login'); end if;
  select * into sc from public.motor_staff_secrets where staff_id = sf.id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'bad_login'); end if;
  if sc.locked_until is not null and sc.locked_until > now() then
    return jsonb_build_object('ok', false, 'reason', 'locked',
      'minutes', ceil(extract(epoch from (sc.locked_until - now()))/60)::int);
  end if;
  if sc.password_hash <> crypt(coalesce(p_password,''), sc.password_hash) then
    update public.motor_staff_secrets
       set failed_count = failed_count + 1,
           locked_until = case when failed_count + 1 >= 6 then now() + interval '15 minutes' end
     where staff_id = sf.id;
    return jsonb_build_object('ok', false, 'reason', 'bad_login');
  end if;
  if not sf.is_active then return jsonb_build_object('ok', false, 'reason', 'inactive_user'); end if;
  -- التحقق بخطوتين
  if sf.totp_enabled and coalesce(sc.totp_secret,'') <> '' then
    if coalesce(trim(p_totp),'') = '' then return jsonb_build_object('ok', false, 'need_totp', true); end if;
    if not public._motor_totp_ok(sc.totp_secret, trim(p_totp)) then
      update public.motor_staff_secrets
         set failed_count = failed_count + 1,
             locked_until = case when failed_count + 1 >= 6 then now() + interval '15 minutes' end
       where staff_id = sf.id;
      return jsonb_build_object('ok', false, 'need_totp', true, 'reason', 'bad_totp');
    end if;
  end if;
  update public.motor_staff_secrets set failed_count = 0, locked_until = null where staff_id = sf.id;
  delete from public.motor_sessions where staff_id = sf.id and expires_at < now();
  tok := encode(gen_random_bytes(24),'hex');
  insert into public.motor_sessions (token_hash, staff_id, site_id)
  values (encode(digest(tok,'sha256'),'hex'), sf.id, st.id);
  return jsonb_build_object('ok', true, 'token', tok, 'role', sf.role, 'name', sf.name);
end $$;

create or replace function public.motor_logout(p_token text)
returns void language sql security definer set search_path = public, extensions as $$
  delete from public.motor_sessions where token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex');
$$;

create or replace function public.motor_change_password(p_slug text, p_token text, p_old text, p_new text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare w jsonb; sc public.motor_staff_secrets%rowtype;
begin
  w := public._motor_who(p_slug, p_token);
  if w->>'staff_id' is null then perform public._motor_err('forbidden'); end if;
  select * into sc from public.motor_staff_secrets where staff_id = (w->>'staff_id')::uuid;
  if sc.password_hash <> crypt(coalesce(p_old,''), sc.password_hash) then perform public._motor_err('bad_old'); end if;
  if length(coalesce(p_new,'')) < 4 then perform public._motor_err('short_password'); end if;
  update public.motor_staff_secrets set password_hash = crypt(p_new, gen_salt('bf', 8)), updated_at = now()
   where staff_id = sc.staff_id;
  delete from public.motor_sessions where staff_id = sc.staff_id
    and token_hash <> encode(digest(p_token,'sha256'),'hex');
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  6) بيانات البداية: الهوية + الإعدادات + الأنواع + الموظفين
-- ============================================================
create or replace function public.motor_me(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; st public.motor_sites%rowtype; sid uuid; adm boolean;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid; adm := (w->>'is_admin')::boolean;
  select * into st from public.motor_sites where id = sid;
  return jsonb_build_object(
    'me', w,
    'today', public._motor_today(),
    'license', public.motor_license(sid),
    'site', to_jsonb(st) - 'client_id' - 'cust_seq' - 'invoice_seq' - 'receipt_seq',
    'plans', coalesce((select jsonb_agg(to_jsonb(p) - 'site_id' order by p.sort, p.name)
                         from public.motor_plans p where p.site_id = sid), '[]'::jsonb),
    'staff', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'role', s.role,
                         'username', case when adm then s.username end, 'phone', s.phone,
                         'is_active', s.is_active, 'read_from', s.read_from, 'read_to', s.read_to,
                         'can_collect', s.can_collect, 'can_read', s.can_read, 'can_cut', s.can_cut,
                         'totp_enabled', s.totp_enabled,
                         'last_lat', case when adm then s.last_lat end, 'last_lng', case when adm then s.last_lng end,
                         'last_acc', case when adm then s.last_acc end, 'last_seen', case when adm then s.last_seen end)
                         order by s.role, s.name)
                         from public.motor_staff s where s.site_id = sid
                          and (adm or s.id = (w->>'staff_id')::uuid)), '[]'::jsonb));
end $$;

-- ============================================================
--  7) الزبائن
-- ============================================================
-- القائمة الخفيفة (للبحث وقوائم «بعد ما انقرى» و«بعد ما دفع») — p_since: للتحديث المباشر
create or replace function public._motor_cust_rows(p_sid uuid, p_own uuid, p_since timestamptz)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'code', c.code, 'name', c.name, 'alt_name', c.alt_name, 'barcode', c.barcode,
      'meter_no', c.meter_no, 'box', c.box, 'area', c.area, 'location_name', c.location_name,
      'zone', c.zone, 'plan_id', c.plan_id, 'balance', c.balance, 'mobile', c.mobile, 'mobile_cc', c.mobile_cc,
      'is_active', c.is_active, 'archived', c.archived, 'collector_id', c.collector_id,
      'collector_name', coalesce(sf.name, c.collector_name),
      'last_value', coalesce(lr.value, c.initial_reading),
      'read_now', (rn.id is not null), 'read_now_value', rn.value,
      'last_note', nt.body, 'last_note_by', nt.staff_name, 'last_note_at', nt.created_at,
      'updated_at', c.updated_at) order by c.code, c.name), '[]'::jsonb)
  from public.motor_customers c
  join public.motor_sites st on st.id = c.site_id
  left join public.motor_staff sf on sf.id = c.collector_id
  left join lateral (select r.value from public.motor_readings r where r.customer_id = c.id
                     order by r.created_at desc limit 1) lr on true
  left join public.motor_readings rn on rn.customer_id = c.id and rn.period = st.bill_period
  left join lateral (select n.body, n.staff_name, n.created_at from public.motor_notes n where n.customer_id = c.id
                     order by n.created_at desc limit 1) nt on true
  where c.site_id = p_sid and (p_own is null or c.collector_id = p_own)
    and (p_since is null or c.updated_at > p_since);
$$;
revoke all on function public._motor_cust_rows(uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function public.motor_customers(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; own uuid;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if w->>'role' = 'collector' and not (select collector_sees_all from public.motor_sites where id = sid) then
    own := (w->>'staff_id')::uuid;
  end if;
  return public._motor_cust_rows(sid, own, null);
end $$;

-- التحديث المباشر: كل شي تغيّر من آخر مرة (كل 15 ثانية من كل جهاز)
create or replace function public.motor_changes(p_slug text, p_token text, p_since timestamptz)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; own uuid; t timestamptz := clock_timestamp(); st public.motor_sites%rowtype;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  if w->>'role' = 'collector' and not st.collector_sees_all then own := (w->>'staff_id')::uuid; end if;
  return jsonb_build_object('now', t, 'period', st.bill_period, 'lbp_rate', st.lbp_rate,
    'me', w,
    'customers', public._motor_cust_rows(sid, own, coalesce(p_since, t - interval '1 minute')),
    'wa_pending', case when (w->>'is_admin')::boolean then
        (select count(*) from public.motor_invoices i where i.site_id = sid and not i.voided and i.kind in ('meter','fixed')
            and i.wa_sent_at is null and i.created_at > now() - interval '60 days')
      + (select count(*) from public.motor_payments p where p.site_id = sid and not p.voided
            and p.wa_sent_at is null and p.created_at > now() - interval '60 days') end);
end $$;

create or replace function public.motor_customer_get(p_slug text, p_token text, p_id uuid, p_barcode text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype; st public.motor_sites%rowtype;
        lr public.motor_readings%rowtype; rn public.motor_readings%rowtype; pl public.motor_plans%rowtype; q text;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  if p_id is not null then
    select * into c from public.motor_customers where id = p_id and site_id = sid;
  else
    q := lower(trim(coalesce(p_barcode,'')));
    if q = '' then perform public._motor_err('not_found'); end if;
    select * into c from public.motor_customers where site_id = sid and lower(barcode) = q limit 1;
    if not found then
      select * into c from public.motor_customers where site_id = sid and lower(meter_no) = q limit 1;
    end if;
  end if;
  if c.id is null then perform public._motor_err('customer_not_found', coalesce(p_barcode,'')); end if;
  if w->>'role' = 'collector' and not st.collector_sees_all and c.collector_id is distinct from (w->>'staff_id')::uuid then
    perform public._motor_err('forbidden');
  end if;
  select * into pl from public.motor_plans where id = c.plan_id;
  select * into lr from public.motor_readings where customer_id = c.id order by created_at desc limit 1;
  select * into rn from public.motor_readings where customer_id = c.id and period = st.bill_period;
  return jsonb_build_object(
    'customer', to_jsonb(c) - 'site_id',
    'plan', case when pl.id is null then null else to_jsonb(pl) - 'site_id' end,
    'collector_name', coalesce((select name from public.motor_staff where id = c.collector_id), c.collector_name),
    'prev_value', coalesce(lr.value, c.initial_reading),
    'baseline', lr.id is null and st.first_read_baseline and coalesce(c.initial_reading,0) = 0,
    'last_reading', case when lr.id is null then null else to_jsonb(lr) - 'site_id' end,
    'period', st.bill_period,
    'read_now', case when rn.id is null then null else to_jsonb(rn) - 'site_id' end,
    'unpaid_invoice', (select to_jsonb(i) - 'site_id' from public.motor_invoices i
                        where i.customer_id = c.id and not i.voided and i.kind in ('meter','fixed')
                        order by i.created_at desc limit 1),
    'notes', coalesce((select jsonb_agg(jsonb_build_object('body', n.body, 'by', n.staff_name, 'at', n.created_at)
                        order by n.created_at desc) from (select * from public.motor_notes where customer_id = c.id
                        order by created_at desc limit 15) n), '[]'::jsonb),
    'switches', coalesce((select jsonb_agg(jsonb_build_object('action', x.action, 'note', x.note, 'by', x.staff_name, 'at', x.created_at)
                        order by x.created_at desc) from (select * from public.motor_switch_log where customer_id = c.id
                        order by created_at desc limit 10) x), '[]'::jsonb));
end $$;

-- p_data: حقول الزبون (id فاضي = جديد). balance لا يتغيّر من هنا — opening_balance للزبون الجديد فقط
create or replace function public.motor_customer_save(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype; d jsonb := coalesce(p_data,'{}'::jsonb);
        newc boolean; seq integer; ob numeric; pre text; was_active boolean;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(trim(d->>'name'),'') = '' then perform public._motor_err('name_required'); end if;
  newc := coalesce(d->>'id','') = '';
  if not newc then
    select * into c from public.motor_customers where id = (d->>'id')::uuid and site_id = sid for update;
    if not found then perform public._motor_err('customer_not_found'); end if;
    was_active := c.is_active;
  else
    update public.motor_sites set cust_seq = cust_seq + 1 where id = sid returning cust_seq, barcode_prefix into seq, pre;
    c.id := gen_random_uuid(); c.site_id := sid; c.code := seq; c.balance := 0; c.created_at := now();
    was_active := true;
  end if;
  if d ? 'plan_id' and nullif(d->>'plan_id','') is not null
     and not exists (select 1 from public.motor_plans where id = (d->>'plan_id')::uuid and site_id = sid) then
    perform public._motor_err('bad_plan');
  end if;
  if d ? 'collector_id' and nullif(d->>'collector_id','') is not null
     and not exists (select 1 from public.motor_staff where id = (d->>'collector_id')::uuid and site_id = sid) then
    perform public._motor_err('bad_staff');
  end if;

  c.name            := trim(d->>'name');
  c.alt_name        := coalesce(d->>'alt_name', c.alt_name, '');
  c.plan_id         := case when d ? 'plan_id' then nullif(d->>'plan_id','')::uuid else c.plan_id end;
  c.building        := coalesce(d->>'building', c.building, '');
  c.floor           := coalesce(d->>'floor', c.floor, '');
  c.side            := coalesce(d->>'side', c.side, '');
  c.box             := coalesce(d->>'box', c.box, '');
  c.generator       := coalesce(d->>'generator', c.generator, '');
  c.breaker_no      := coalesce(d->>'breaker_no', c.breaker_no, '');
  c.meter_no        := coalesce(d->>'meter_no', c.meter_no, '');
  c.barcode         := trim(coalesce(d->>'barcode', c.barcode, ''));
  c.location_name   := coalesce(d->>'location_name', c.location_name, '');
  c.location_code   := coalesce(d->>'location_code', c.location_code, '');
  c.lat             := case when d ? 'lat' then nullif(d->>'lat','')::double precision else c.lat end;
  c.lng             := case when d ? 'lng' then nullif(d->>'lng','')::double precision else c.lng end;
  c.area            := coalesce(d->>'area', c.area, '');
  c.area_code       := coalesce(d->>'area_code', c.area_code, '');
  c.zone            := coalesce(d->>'zone', c.zone, '');
  c.category        := coalesce(d->>'category', c.category, '');
  c.category2       := coalesce(d->>'category2', c.category2, '');
  c.collector_id    := case when d ? 'collector_id' then nullif(d->>'collector_id','')::uuid else c.collector_id end;
  c.collector_name  := coalesce(d->>'collector_name', c.collector_name, '');
  c.sub_date        := case when d ? 'sub_date' then nullif(d->>'sub_date','')::date else c.sub_date end;
  c.is_active       := coalesce((d->>'is_active')::boolean, c.is_active, true);
  c.credit_limit    := case when d ? 'credit_limit' then nullif(d->>'credit_limit','')::numeric else c.credit_limit end;
  c.charge_discount := coalesce(nullif(d->>'charge_discount','')::numeric, case when d ? 'charge_discount' then 0 end, c.charge_discount, 0);
  c.discount_desc   := coalesce(d->>'discount_desc', c.discount_desc, '');
  c.charge_addition := coalesce(nullif(d->>'charge_addition','')::numeric, case when d ? 'charge_addition' then 0 end, c.charge_addition, 0);
  c.addition_desc   := coalesce(d->>'addition_desc', c.addition_desc, '');
  c.initial_reading := coalesce(nullif(d->>'initial_reading','')::numeric, c.initial_reading, 0);
  c.mobile          := regexp_replace(coalesce(d->>'mobile', c.mobile, ''), '[^0-9]', '', 'g');
  c.mobile_cc       := coalesce(nullif(regexp_replace(coalesce(d->>'mobile_cc',''), '[^0-9]', '', 'g'),''), c.mobile_cc, '961');
  c.mobile2         := coalesce(d->>'mobile2', c.mobile2, '');
  c.phone           := coalesce(d->>'phone', c.phone, '');
  c.address         := coalesce(d->>'address', c.address, '');
  c.email           := coalesce(d->>'email', c.email, '');
  c.nationality     := coalesce(d->>'nationality', c.nationality, '');
  c.archived        := coalesce((d->>'archived')::boolean, c.archived, false);
  c.collect_day     := case when d ? 'collect_day' then nullif(d->>'collect_day','')::integer else c.collect_day end;
  c.notes           := coalesce(d->>'notes', c.notes, '');
  if was_active and not c.is_active then
    c.stopped_at := now(); c.stopped_by := w->>'name';
  elsif c.is_active then
    c.stopped_at := null; c.stopped_by := '';
  end if;
  -- الاستيراد: تاريخ التوقيف ومين أوقفه كما هم بالملف
  if not c.is_active and nullif(d->>'stopped_at','') is not null then
    begin
      c.stopped_at := (d->>'stopped_at')::timestamp at time zone 'Asia/Beirut';
    exception when others then null;
    end;
    c.stopped_by := coalesce(nullif(d->>'stopped_by',''), c.stopped_by, '');
  end if;
  if newc and c.barcode = '' then c.barcode := pre || '-' || lpad(seq::text, 5, '0'); end if;
  if c.barcode <> '' and exists (select 1 from public.motor_customers x where x.site_id = sid
        and lower(x.barcode) = lower(c.barcode) and x.id <> c.id) then
    perform public._motor_err('barcode_taken', c.barcode);
  end if;
  c.updated_at := now();

  if newc then
    insert into public.motor_customers values (c.*);
    ob := coalesce(nullif(d->>'opening_balance','')::numeric, 0);
    if ob <> 0 then
      update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
      insert into public.motor_invoices (site_id, no, customer_id, kind, amount, balance_before, balance_after, note, staff_id, staff_name)
      values (sid, seq, c.id, 'opening', ob, 0, ob, coalesce(d->>'opening_note','رصيد افتتاحي'),
              (w->>'staff_id')::uuid, w->>'name');
      update public.motor_customers set balance = ob where id = c.id;
      c.balance := ob;
    end if;
  else
    update public.motor_customers x set
      name = c.name, alt_name = c.alt_name, plan_id = c.plan_id, building = c.building, floor = c.floor, side = c.side,
      box = c.box, generator = c.generator, breaker_no = c.breaker_no, meter_no = c.meter_no, barcode = c.barcode,
      location_name = c.location_name, location_code = c.location_code, lat = c.lat, lng = c.lng, area = c.area,
      area_code = c.area_code, zone = c.zone, category = c.category, category2 = c.category2,
      collector_id = c.collector_id, collector_name = c.collector_name, sub_date = c.sub_date, is_active = c.is_active,
      stopped_at = c.stopped_at, stopped_by = c.stopped_by, credit_limit = c.credit_limit,
      charge_discount = c.charge_discount, discount_desc = c.discount_desc, charge_addition = c.charge_addition,
      addition_desc = c.addition_desc, initial_reading = c.initial_reading, mobile = c.mobile, mobile_cc = c.mobile_cc,
      mobile2 = c.mobile2, phone = c.phone, address = c.address, email = c.email, nationality = c.nationality,
      archived = c.archived, collect_day = c.collect_day, notes = c.notes, updated_at = c.updated_at
    where x.id = c.id;
  end if;
  return to_jsonb(c) - 'site_id';
end $$;

create or replace function public.motor_customer_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if exists (select 1 from public.motor_invoices where customer_id = p_id and kind <> 'opening')
     or exists (select 1 from public.motor_payments where customer_id = p_id)
     or exists (select 1 from public.motor_readings where customer_id = p_id) then
    perform public._motor_err('has_records');
  end if;
  delete from public.motor_customers where id = p_id and site_id = sid;
  return jsonb_build_object('ok', found);
end $$;

-- استيراد من Excel: p_rows مصفوفة كائنات بنفس أسماء حقول motor_customer_save
-- + service (اسم نوع الاشتراك) + collector_name + opening_balance
-- الزبون الموجود (نفس الباركود، أو نفس رقم العداد إذا ما في باركود) بيتحدّث بدون ما يمسّ رصيده
create or replace function public.motor_import(p_slug text, p_token text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; r jsonb; ex uuid; pid uuid; stid uuid; nm text; svc text; amps numeric;
        added int := 0; updated int := 0; skipped int := 0; plans_new int := 0; errs jsonb := '[]'::jsonb; i int := 0;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if jsonb_typeof(p_rows) <> 'array' then perform public._motor_err('bad_data'); end if;
  if jsonb_array_length(p_rows) > 5000 then perform public._motor_err('too_many'); end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    nm := trim(coalesce(r->>'name',''));
    if nm = '' then skipped := skipped + 1; continue; end if;
    begin
      -- نوع الاشتراك من عمود «الخدمة» (6A، 10A …) — بينعمل تلقائياً إذا مش موجود
      pid := null; svc := upper(trim(coalesce(r->>'service','')));
      if svc <> '' then
        select id into pid from public.motor_plans where site_id = sid and lower(name) = lower(svc);
        if pid is null then
          amps := nullif(regexp_replace(svc, '[^0-9.]', '', 'g'), '')::numeric;
          insert into public.motor_plans (site_id, name, amps, kind, fee, sort)
          values (sid, svc, coalesce(amps,0), 'meter', 0, coalesce(amps,0)::int)
          returning id into pid;
          plans_new := plans_new + 1;
        end if;
        r := r || jsonb_build_object('plan_id', pid);
      end if;
      -- الجابي حسب الاسم (إذا موجود كموظف)
      stid := null;
      if coalesce(trim(r->>'collector_name'),'') <> '' then
        select id into stid from public.motor_staff where site_id = sid and lower(trim(name)) = lower(trim(r->>'collector_name')) limit 1;
        if stid is not null then r := r || jsonb_build_object('collector_id', stid); end if;
      end if;
      -- المواقع الوهمية → بلا موقع
      if not public._motor_geo_ok(nullif(r->>'lat','')::double precision, nullif(r->>'lng','')::double precision) then
        r := r || jsonb_build_object('lat', '', 'lng', '');
      end if;
      ex := null;
      if coalesce(trim(r->>'barcode'),'') <> '' then
        select id into ex from public.motor_customers where site_id = sid and lower(barcode) = lower(trim(r->>'barcode'));
      elsif coalesce(trim(r->>'meter_no'),'') <> '' then
        select id into ex from public.motor_customers where site_id = sid and meter_no = trim(r->>'meter_no') limit 1;
      end if;
      if ex is not null then
        perform public.motor_customer_save(p_slug, p_token, (r - 'opening_balance') || jsonb_build_object('id', ex));
        updated := updated + 1;
      else
        perform public.motor_customer_save(p_slug, p_token, (r - 'id') || jsonb_build_object('opening_note', 'رصيد سابق (استيراد)'));
        added := added + 1;
      end if;
    exception when others then
      skipped := skipped + 1;
      if jsonb_array_length(errs) < 30 then
        errs := errs || jsonb_build_object('row', i, 'name', nm, 'error', sqlerrm);
      end if;
    end;
  end loop;
  return jsonb_build_object('ok', true, 'added', added, 'updated', updated, 'skipped', skipped,
                            'plans_new', plans_new, 'errors', errs);
end $$;

-- ============================================================
--  8) كشف حساب الزبون (فيه العداد السابق والحالي لكل فاتورة)
-- ============================================================
create or replace function public.motor_statement(p_slug text, p_token text, p_customer uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype; st public.motor_sites%rowtype;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  select * into c from public.motor_customers where id = p_customer and site_id = sid;
  if not found then perform public._motor_err('customer_not_found'); end if;
  if w->>'role' = 'collector' and not st.collector_sees_all and c.collector_id is distinct from (w->>'staff_id')::uuid then
    perform public._motor_err('forbidden');
  end if;
  return jsonb_build_object(
    'customer', jsonb_build_object('id', c.id, 'code', c.code, 'name', c.name, 'barcode', c.barcode,
                 'meter_no', c.meter_no, 'balance', c.balance, 'mobile', c.mobile, 'mobile_cc', c.mobile_cc,
                 'box', c.box, 'area', c.area, 'plan_name', (select name from public.motor_plans where id = c.plan_id)),
    'rows', coalesce((select jsonb_agg(x order by x->>'at', x->>'t') from (
        select jsonb_build_object('t','inv','id',i.id,'no',i.no,'at',i.created_at,'kind',i.kind,'period',i.period,
               'prev_value',i.prev_value,'cur_value',i.cur_value,'kwh',i.kwh,'kwh_price',i.kwh_price,'fee',i.fee,
               'energy',i.energy,'discount',i.discount,'addition',i.addition,'debit',i.amount,'credit',0,
               'note',i.note,'staff',i.staff_name,'voided',i.voided,
               'photo', (select r.photo_url from public.motor_readings r where r.id = i.reading_id)) as x
          from public.motor_invoices i where i.customer_id = c.id
        union all
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'method',p.method,
               'paid_currency',p.paid_currency,'paid_amount',p.paid_amount,'rate',p.rate,
               'debit',0,'credit',p.amount,'note',p.note,'staff',p.staff_name,'voided',p.voided)
          from public.motor_payments p where p.customer_id = c.id
      ) q), '[]'::jsonb));
end $$;

-- ============================================================
--  9) أخذ العداد → قراءة + فاتورة بعملية واحدة
-- ============================================================
create or replace function public.motor_read(p_slug text, p_token text, p_customer uuid, p_value numeric,
  p_photo text, p_lat double precision, p_lng double precision, p_accuracy double precision default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; st public.motor_sites%rowtype; c public.motor_customers%rowtype;
        pl public.motor_plans%rowtype; prev numeric; d integer; rid uuid; seq integer;
        kwh numeric; price numeric; fee numeric; energy numeric; amt numeric; inv public.motor_invoices%rowtype;
        today date := public._motor_today(); baseline boolean := false;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid for update;   -- يرتّب الأرقام المتسلسلة
  select * into c from public.motor_customers where id = p_customer and site_id = sid for update;
  if not found then perform public._motor_err('customer_not_found'); end if;
  if not (w->>'can_read')::boolean then perform public._motor_err('forbidden'); end if;
  if w->>'role' = 'collector' then
    if not st.collector_sees_all and c.collector_id is distinct from (w->>'staff_id')::uuid then
      perform public._motor_err('forbidden');
    end if;
    if w->>'read_from' is null or w->>'read_to' is null then perform public._motor_err('no_window'); end if;
    if today < (w->>'read_from')::date or today > (w->>'read_to')::date then
      perform public._motor_err('out_of_window', (w->>'read_from') || '|' || (w->>'read_to'));
    end if;
  end if;
  if not c.is_active then perform public._motor_err('customer_inactive'); end if;
  if exists (select 1 from public.motor_readings where customer_id = c.id and period = st.bill_period) then
    perform public._motor_err('already_read', st.bill_period);
  end if;
  if p_value is null or p_value < 0 then perform public._motor_err('bad_value'); end if;
  if st.require_photo and coalesce(p_photo,'') = '' then perform public._motor_err('photo_required'); end if;
  if coalesce(p_photo,'') <> '' and p_photo !~ ('^/img/motor/' || sid::text || '/') then
    perform public._motor_err('bad_photo');
  end if;
  if st.require_gps and not public._motor_geo_ok(p_lat, p_lng) then perform public._motor_err('gps_required'); end if;

  select value into prev from public.motor_readings where customer_id = c.id order by created_at desc limit 1;
  if not found then
    prev := coalesce(c.initial_reading, 0);
    baseline := st.first_read_baseline and coalesce(c.initial_reading, 0) = 0;
  end if;
  if baseline then prev := p_value; end if;     -- أول قراءة = عداد أولي، بلا استهلاك
  if p_value < prev then perform public._motor_err('lower_than_prev', prev::text); end if;

  d := null;
  if public._motor_geo_ok(p_lat, p_lng) and public._motor_geo_ok(c.lat, c.lng) then
    d := public._motor_dist(c.lat, c.lng, p_lat, p_lng);
    if st.max_distance_m > 0 and d > st.max_distance_m then perform public._motor_err('too_far', d::text); end if;
  end if;

  insert into public.motor_readings (site_id, customer_id, period, prev_value, value, photo_url, lat, lng, accuracy,
                                     dist_m, staff_id, staff_name)
  values (sid, c.id, st.bill_period, prev, p_value, coalesce(p_photo,''), p_lat, p_lng, p_accuracy, d,
          (w->>'staff_id')::uuid, w->>'name')
  returning id into rid;

  -- أول قراءة لزبون بلا موقع: منثبّت موقعه
  if not public._motor_geo_ok(c.lat, c.lng) and public._motor_geo_ok(p_lat, p_lng) then
    update public.motor_customers set lat = p_lat, lng = p_lng where id = c.id;
  end if;

  select * into pl from public.motor_plans where id = c.plan_id;
  kwh := p_value - prev;
  fee := coalesce(pl.fee, 0);
  if coalesce(pl.kind,'meter') = 'meter' then
    price := coalesce(pl.kwh_price, st.kwh_price, 0);
    energy := kwh * price;
  else
    price := 0; energy := 0;
  end if;
  amt := public._motor_round(sid, fee + energy - coalesce(c.charge_discount,0) + coalesce(c.charge_addition,0));

  update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
  insert into public.motor_invoices (site_id, no, customer_id, period, kind, reading_id, plan_name, prev_value, cur_value,
         kwh, kwh_price, fee, energy, discount, addition, amount, balance_before, balance_after, staff_id, staff_name)
  values (sid, seq, c.id, st.bill_period, coalesce(pl.kind,'meter'), rid, coalesce(pl.name,''), prev, p_value,
          kwh, price, fee, round(energy,2), coalesce(c.charge_discount,0), coalesce(c.charge_addition,0), amt,
          c.balance, c.balance + amt, (w->>'staff_id')::uuid, w->>'name')
  returning * into inv;
  if baseline then update public.motor_invoices set note = 'قراءة أولى (عداد أولي)' where id = inv.id; inv.note := 'قراءة أولى (عداد أولي)'; end if;
  update public.motor_customers set balance = balance + amt, updated_at = now() where id = c.id;

  return jsonb_build_object('ok', true, 'invoice', to_jsonb(inv) - 'site_id', 'dist_m', d, 'reading_id', rid, 'baseline', baseline);
end $$;

-- فواتير الاشتراك المقطوع (بلا عداد) لدورة الفوترة الحالية — دفعة وحدة
create or replace function public.motor_bill_fixed(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; st public.motor_sites%rowtype; c record; amt numeric; seq integer; n int := 0;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid for update;
  for c in select cu.*, pl.fee as pfee, pl.name as pname from public.motor_customers cu
             join public.motor_plans pl on pl.id = cu.plan_id
            where cu.site_id = sid and cu.is_active and not cu.archived and pl.kind = 'fixed'
              and not exists (select 1 from public.motor_invoices i where i.customer_id = cu.id
                               and i.period = st.bill_period and i.kind in ('meter','fixed') and not i.voided)
            for update of cu
  loop
    amt := public._motor_round(sid, c.pfee - coalesce(c.charge_discount,0) + coalesce(c.charge_addition,0));
    update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
    insert into public.motor_invoices (site_id, no, customer_id, period, kind, plan_name, fee, discount, addition,
           amount, balance_before, balance_after, staff_id, staff_name)
    values (sid, seq, c.id, st.bill_period, 'fixed', c.pname, c.pfee, coalesce(c.charge_discount,0),
            coalesce(c.charge_addition,0), amt, c.balance, c.balance + amt, (w->>'staff_id')::uuid, w->>'name');
    update public.motor_customers set balance = balance + amt, updated_at = now() where id = c.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'count', n, 'period', st.bill_period);
end $$;

-- إلغاء فاتورة (والقراءة المربوطة فيها بتنحذف حتى ينعاد أخذ العداد)
create or replace function public.motor_invoice_void(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; i public.motor_invoices%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into i from public.motor_invoices where id = p_id and site_id = sid for update;
  if not found then perform public._motor_err('not_found'); end if;
  if i.voided then return jsonb_build_object('ok', true); end if;
  update public.motor_invoices set voided = true, voided_at = now(), voided_by = w->>'name', reading_id = null where id = i.id;
  if i.reading_id is not null then delete from public.motor_readings where id = i.reading_id; end if;
  update public.motor_customers set balance = balance - i.amount, updated_at = now() where id = i.customer_id;
  return jsonb_build_object('ok', true);
end $$;

-- قيد يدوي على الزبون (موجب = دين عليه، سالب = له)
create or replace function public.motor_adjust(p_slug text, p_token text, p_customer uuid, p_amount numeric, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype; seq integer; inv public.motor_invoices%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(p_amount,0) = 0 then perform public._motor_err('bad_amount'); end if;
  select * into c from public.motor_customers where id = p_customer and site_id = sid for update;
  if not found then perform public._motor_err('customer_not_found'); end if;
  update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
  insert into public.motor_invoices (site_id, no, customer_id, kind, amount, balance_before, balance_after, note, staff_id, staff_name)
  values (sid, seq, c.id, 'adjust', p_amount, c.balance, c.balance + p_amount, coalesce(p_note,''),
          (w->>'staff_id')::uuid, w->>'name')
  returning * into inv;
  update public.motor_customers set balance = balance + p_amount, updated_at = now() where id = c.id;
  return jsonb_build_object('ok', true, 'invoice', to_jsonb(inv) - 'site_id');
end $$;

-- ============================================================
--  10) القبض
-- ============================================================
create or replace function public.motor_pay(p_slug text, p_token text, p_customer uuid, p_paid numeric,
  p_currency text, p_method text, p_note text default '', p_lat double precision default null, p_lng double precision default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; st public.motor_sites%rowtype; c public.motor_customers%rowtype; amt numeric; seq integer;
        pay public.motor_payments%rowtype; cur text := upper(coalesce(p_currency,'')); m text := lower(coalesce(p_method,'cash'));
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not (w->>'can_collect')::boolean then perform public._motor_err('forbidden'); end if;
  select * into st from public.motor_sites where id = sid for update;
  select * into c from public.motor_customers where id = p_customer and site_id = sid for update;
  if not found then perform public._motor_err('customer_not_found'); end if;
  if w->>'role' = 'collector' and not st.collector_sees_all and c.collector_id is distinct from (w->>'staff_id')::uuid then
    perform public._motor_err('forbidden');
  end if;
  if cur = '' then cur := st.currency; end if;
  if cur not in ('USD','LBP') then perform public._motor_err('bad_currency'); end if;
  if m not in ('cash','whish') then perform public._motor_err('bad_method'); end if;
  if coalesce(p_paid,0) <= 0 then perform public._motor_err('bad_amount'); end if;
  if cur = st.currency then amt := p_paid;
  elsif coalesce(st.lbp_rate,0) <= 0 then perform public._motor_err('no_rate');
  elsif cur = 'LBP' then amt := round(p_paid / st.lbp_rate, 2);      -- أساسي دولار، مقبوض ليرة
  else amt := round(p_paid * st.lbp_rate, 0);                         -- أساسي ليرة، مقبوض دولار
  end if;
  update public.motor_sites set receipt_seq = receipt_seq + 1 where id = sid returning receipt_seq into seq;
  insert into public.motor_payments (site_id, no, customer_id, amount, paid_currency, paid_amount, rate, method,
         balance_before, balance_after, note, lat, lng, staff_id, staff_name)
  values (sid, seq, c.id, amt, cur, p_paid, case when cur = st.currency then 0 else st.lbp_rate end, m,
          c.balance, c.balance - amt, coalesce(p_note,''), p_lat, p_lng, (w->>'staff_id')::uuid, w->>'name')
  returning * into pay;
  update public.motor_customers set balance = balance - amt, updated_at = now() where id = c.id;
  return jsonb_build_object('ok', true, 'payment', to_jsonb(pay) - 'site_id',
    'invoice', (select to_jsonb(i) - 'site_id' from public.motor_invoices i
                 where i.customer_id = c.id and not i.voided and i.kind in ('meter','fixed')
                 order by i.created_at desc limit 1));
end $$;

create or replace function public.motor_payment_void(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; p public.motor_payments%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into p from public.motor_payments where id = p_id and site_id = sid for update;
  if not found then perform public._motor_err('not_found'); end if;
  if p.voided then return jsonb_build_object('ok', true); end if;
  if p.method = 'cash' and p.created_at <= coalesce((select max(created_at) from public.motor_moves
        where site_id = sid and account = 'cash' and kind = 'close'), '-infinity'::timestamptz) then
    perform public._motor_err('closed_period');
  end if;
  update public.motor_payments set voided = true, voided_at = now(), voided_by = w->>'name' where id = p.id;
  update public.motor_customers set balance = balance + p.amount, updated_at = now() where id = p.customer_id;
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  11) جدول عدادات الشهر
-- ============================================================
create or replace function public.motor_month(p_slug text, p_token text, p_period text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; per text; mine boolean;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  per := coalesce(nullif(p_period,''), (select bill_period from public.motor_sites where id = sid));
  mine := w->>'role' = 'collector';
  return jsonb_build_object('period', per, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'at', r.created_at, 'customer_id', c.id, 'code', c.code, 'name', c.name, 'barcode', c.barcode,
      'box', c.box, 'area', c.area, 'prev_value', r.prev_value, 'value', r.value, 'kwh', r.value - r.prev_value,
      'photo', r.photo_url, 'lat', r.lat, 'lng', r.lng, 'accuracy', r.accuracy, 'dist_m', r.dist_m,
      'staff_id', r.staff_id, 'staff', r.staff_name,
      'invoice_id', i.id, 'invoice_no', i.no, 'amount', i.amount, 'balance_after', i.balance_after)
      order by r.created_at desc)
    from public.motor_readings r
    join public.motor_customers c on c.id = r.customer_id
    left join public.motor_invoices i on i.reading_id = r.id
    where r.site_id = sid and r.period = per and (not mine or r.staff_id = (w->>'staff_id')::uuid)), '[]'::jsonb),
    'total_active', (select count(*) from public.motor_customers where site_id = sid and is_active and not archived),
    'total_read', (select count(*) from public.motor_readings where site_id = sid and period = per));
end $$;

-- ============================================================
--  12) الإعدادات / أنواع الاشتراك / الموظفين  (المدير فقط)
-- ============================================================
create or replace function public.motor_settings_save(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; d jsonb := coalesce(p_data,'{}'::jsonb); st public.motor_sites%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if d ? 'bill_period' and (d->>'bill_period') !~ '^\d{4}-(0[1-9]|1[0-2])$' then perform public._motor_err('bad_period'); end if;
  if d ? 'currency' and (d->>'currency') not in ('USD','LBP') then perform public._motor_err('bad_currency'); end if;
  update public.motor_sites set
    name           = coalesce(nullif(trim(d->>'name'),''), name),
    logo_url       = coalesce(d->>'logo_url', logo_url),
    phone          = coalesce(d->>'phone', phone),
    whatsapp       = coalesce(regexp_replace(d->>'whatsapp','[^0-9]','','g'), whatsapp),
    address        = coalesce(d->>'address', address),
    currency       = coalesce(d->>'currency', currency),
    lbp_rate       = coalesce(nullif(d->>'lbp_rate','')::numeric, lbp_rate),
    show_second    = coalesce((d->>'show_second')::boolean, show_second),
    kwh_price      = coalesce(nullif(d->>'kwh_price','')::numeric, kwh_price),
    round_step     = coalesce(nullif(d->>'round_step','')::numeric, round_step),
    bill_period    = coalesce(d->>'bill_period', bill_period),
    max_distance_m = coalesce(nullif(d->>'max_distance_m','')::integer, max_distance_m),
    require_photo  = coalesce((d->>'require_photo')::boolean, require_photo),
    require_gps    = coalesce((d->>'require_gps')::boolean, require_gps),
    first_read_baseline = coalesce((d->>'first_read_baseline')::boolean, first_read_baseline),
    collector_sees_all = coalesce((d->>'collector_sees_all')::boolean, collector_sees_all),
    barcode_prefix = coalesce(nullif(upper(regexp_replace(d->>'barcode_prefix','[^A-Za-z0-9]','','g')),''), barcode_prefix),
    invoice_note   = coalesce(d->>'invoice_note', invoice_note),
    tagline        = coalesce(d->>'tagline', tagline),
    cur_label      = coalesce(left(trim(d->>'cur_label'), 10), cur_label),
    wa_from_office = coalesce((d->>'wa_from_office')::boolean, wa_from_office),
    default_lang   = case when d->>'default_lang' in ('ar','en','fr') then d->>'default_lang' else default_lang end
  where id = sid returning * into st;
  return to_jsonb(st) - 'client_id' - 'cust_seq' - 'invoice_seq' - 'receipt_seq';
end $$;

create or replace function public.motor_plan_save(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; d jsonb := coalesce(p_data,'{}'::jsonb); p public.motor_plans%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(trim(d->>'name'),'') = '' then perform public._motor_err('name_required'); end if;
  if coalesce(d->>'kind','meter') not in ('meter','fixed') then perform public._motor_err('bad_kind'); end if;
  if exists (select 1 from public.motor_plans x where x.site_id = sid and lower(x.name) = lower(trim(d->>'name'))
             and x.id::text <> coalesce(d->>'id','')) then
    perform public._motor_err('name_taken');
  end if;
  if coalesce(d->>'id','') = '' then
    insert into public.motor_plans (site_id, name, amps, kind, fee, kwh_price, is_active, sort)
    values (sid, trim(d->>'name'), coalesce(nullif(d->>'amps','')::numeric,0), coalesce(d->>'kind','meter'),
            coalesce(nullif(d->>'fee','')::numeric,0), nullif(d->>'kwh_price','')::numeric,
            coalesce((d->>'is_active')::boolean,true), coalesce(nullif(d->>'sort','')::int,0))
    returning * into p;
  else
    update public.motor_plans set name = trim(d->>'name'), amps = coalesce(nullif(d->>'amps','')::numeric,0),
           kind = coalesce(d->>'kind','meter'), fee = coalesce(nullif(d->>'fee','')::numeric,0),
           kwh_price = nullif(d->>'kwh_price','')::numeric, is_active = coalesce((d->>'is_active')::boolean,true),
           sort = coalesce(nullif(d->>'sort','')::int, sort)
     where id = (d->>'id')::uuid and site_id = sid returning * into p;
    if p.id is null then perform public._motor_err('not_found'); end if;
  end if;
  return to_jsonb(p) - 'site_id';
end $$;

create or replace function public.motor_plan_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if exists (select 1 from public.motor_customers where plan_id = p_id) then perform public._motor_err('plan_in_use'); end if;
  delete from public.motor_plans where id = p_id and site_id = sid;
  return jsonb_build_object('ok', true);
end $$;

-- p_password فاضي = ما تتغيّر (إلزامي للموظف الجديد)
create or replace function public.motor_staff_save(p_slug text, p_token text, p_data jsonb, p_password text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare w jsonb; sid uuid; d jsonb := coalesce(p_data,'{}'::jsonb); s public.motor_staff%rowtype; u text;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  u := lower(trim(coalesce(d->>'username','')));
  if coalesce(trim(d->>'name'),'') = '' then perform public._motor_err('name_required'); end if;
  if u !~ '^[a-z0-9._-]{2,30}$' then perform public._motor_err('bad_username'); end if;
  if coalesce(d->>'role','collector') not in ('admin','collector') then perform public._motor_err('bad_role'); end if;
  if exists (select 1 from public.motor_staff x where x.site_id = sid and lower(x.username) = u
             and x.id::text <> coalesce(d->>'id','')) then perform public._motor_err('username_taken'); end if;
  if nullif(d->>'read_from','') is not null and nullif(d->>'read_to','') is not null
     and (d->>'read_from')::date > (d->>'read_to')::date then perform public._motor_err('bad_window'); end if;
  if coalesce(d->>'id','') = '' then
    if length(coalesce(p_password,'')) < 4 then perform public._motor_err('short_password'); end if;
    insert into public.motor_staff (site_id, name, username, phone, role, is_active, read_from, read_to, can_collect, can_read, can_cut)
    values (sid, trim(d->>'name'), u, coalesce(d->>'phone',''), coalesce(d->>'role','collector'),
            coalesce((d->>'is_active')::boolean,true), nullif(d->>'read_from','')::date, nullif(d->>'read_to','')::date,
            coalesce((d->>'can_collect')::boolean,true), coalesce((d->>'can_read')::boolean,true), coalesce((d->>'can_cut')::boolean,false))
    returning * into s;
  else
    -- الموظف ما بيقدر يشيل صلاحية المدير عن حالو
    if (d->>'id') = w->>'staff_id' and coalesce(d->>'role','collector') <> 'admin' then perform public._motor_err('self_demote'); end if;
    if (d->>'id') = w->>'staff_id' and not coalesce((d->>'is_active')::boolean,true) then perform public._motor_err('self_demote'); end if;
    update public.motor_staff set name = trim(d->>'name'), username = u, phone = coalesce(d->>'phone',''),
           role = coalesce(d->>'role','collector'), is_active = coalesce((d->>'is_active')::boolean,true),
           read_from = nullif(d->>'read_from','')::date, read_to = nullif(d->>'read_to','')::date,
           can_collect = coalesce((d->>'can_collect')::boolean,true),
           can_read = coalesce((d->>'can_read')::boolean,true), can_cut = coalesce((d->>'can_cut')::boolean,false)
     where id = (d->>'id')::uuid and site_id = sid returning * into s;
    if s.id is null then perform public._motor_err('not_found'); end if;
    if length(coalesce(p_password,'')) between 1 and 3 then perform public._motor_err('short_password'); end if;
    if not s.is_active then delete from public.motor_sessions where staff_id = s.id; end if;
  end if;
  if length(coalesce(p_password,'')) >= 4 then
    insert into public.motor_staff_secrets (staff_id, password_hash) values (s.id, crypt(p_password, gen_salt('bf', 8)))
    on conflict (staff_id) do update set password_hash = excluded.password_hash, failed_count = 0, locked_until = null, updated_at = now();
    delete from public.motor_sessions where staff_id = s.id
      and token_hash <> encode(digest(coalesce(p_token,''),'sha256'),'hex');
  end if;
  return to_jsonb(s) - 'site_id' - 'last_lat' - 'last_lng' - 'last_acc';
end $$;

-- فترة أخذ العدادات لكل الجباة دفعة وحدة
create or replace function public.motor_window_all(p_slug text, p_token text, p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; n int;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_from is not null and p_to is not null and p_from > p_to then perform public._motor_err('bad_window'); end if;
  update public.motor_staff set read_from = p_from, read_to = p_to where site_id = sid and role = 'collector';
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'count', n);
end $$;

create or replace function public.motor_staff_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_id::text = w->>'staff_id' then perform public._motor_err('self_demote'); end if;
  if exists (select 1 from public.motor_payments where staff_id = p_id)
     or exists (select 1 from public.motor_readings where staff_id = p_id)
     or exists (select 1 from public.motor_moves where staff_id = p_id) then
    -- عندو حركات: منوقّفو بدل الحذف حتى يضل كشف حسابو
    update public.motor_staff set is_active = false where id = p_id and site_id = sid;
    delete from public.motor_sessions where staff_id = p_id;
    return jsonb_build_object('ok', true, 'deactivated', true);
  end if;
  delete from public.motor_staff where id = p_id and site_id = sid;
  return jsonb_build_object('ok', true, 'deleted', true);
end $$;

-- ============================================================
--  13) كشف حساب الجابي  (له: المقبوض نقداً — عليه: ما سلّمه للمكتب)
-- ============================================================
create or replace function public.motor_collector_statement(p_slug text, p_token text, p_staff uuid,
  p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sf public.motor_staff%rowtype; opening numeric; f date; t date;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not (w->>'is_admin')::boolean and p_staff::text is distinct from w->>'staff_id' then perform public._motor_err('forbidden'); end if;
  select * into sf from public.motor_staff where id = p_staff and site_id = sid;
  if not found then perform public._motor_err('not_found'); end if;
  f := coalesce(p_from, date '2000-01-01'); t := coalesce(p_to, date '2999-12-31');
  -- رصيد ما قبل الفترة
  opening := coalesce((select sum(amount) from public.motor_payments where staff_id = sf.id and method = 'cash'
                         and not voided and (created_at at time zone 'Asia/Beirut')::date < f), 0)
           - coalesce((select sum(amount) from public.motor_moves where staff_id = sf.id and account = 'collector'
                         and (created_at at time zone 'Asia/Beirut')::date < f), 0);
  return jsonb_build_object(
    'staff', jsonb_build_object('id', sf.id, 'name', sf.name, 'role', sf.role),
    'opening', opening,
    'balance_now', coalesce((select sum(amount) from public.motor_payments where staff_id = sf.id and method = 'cash' and not voided), 0)
                 - coalesce((select sum(amount) from public.motor_moves where staff_id = sf.id and account = 'collector'), 0),
    'readings', (select count(*) from public.motor_readings where staff_id = sf.id
                   and (created_at at time zone 'Asia/Beirut')::date between f and t),
    'whish_total', coalesce((select sum(amount) from public.motor_payments where staff_id = sf.id and method = 'whish'
                   and not voided and (created_at at time zone 'Asia/Beirut')::date between f and t), 0),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'customer',c.name,'code',c.code,
               'method',p.method,'paid_currency',p.paid_currency,'paid_amount',p.paid_amount,
               'debit', case when p.method = 'cash' then p.amount else 0 end, 'credit', 0, 'amount', p.amount,
               'note', p.note, 'voided', p.voided) as x
          from public.motor_payments p join public.motor_customers c on c.id = p.customer_id
         where p.staff_id = sf.id and (p.created_at at time zone 'Asia/Beirut')::date between f and t
        union all
        select jsonb_build_object('t','move','id',m.id,'at',m.created_at,'kind',m.kind,'debit',
               case when m.amount < 0 then -m.amount else 0 end,'credit', case when m.amount > 0 then m.amount else 0 end,
               'note',m.note,'by',m.by_name)
          from public.motor_moves m
         where m.staff_id = sf.id and m.account = 'collector' and (m.created_at at time zone 'Asia/Beirut')::date between f and t
      ) q), '[]'::jsonb));
end $$;

-- ============================================================
--  14) كشف حساب Whish  (له: المقبوض عبر Whish — عليه: السحوبات)
-- ============================================================
create or replace function public.motor_whish_statement(p_slug text, p_token text, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; f date; t date; opening numeric;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  f := coalesce(p_from, date '2000-01-01'); t := coalesce(p_to, date '2999-12-31');
  opening := coalesce((select sum(amount) from public.motor_payments where site_id = sid and method = 'whish' and not voided
                         and (created_at at time zone 'Asia/Beirut')::date < f), 0)
           + coalesce((select sum(case when kind = 'withdraw' then -abs(amount) else amount end) from public.motor_moves
                         where site_id = sid and account = 'whish' and (created_at at time zone 'Asia/Beirut')::date < f), 0);
  return jsonb_build_object('opening', opening,
    'balance_now', coalesce((select sum(amount) from public.motor_payments where site_id = sid and method = 'whish' and not voided), 0)
                 + coalesce((select sum(case when kind = 'withdraw' then -abs(amount) else amount end) from public.motor_moves
                              where site_id = sid and account = 'whish'), 0),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'customer',c.name,'code',c.code,
               'debit',0,'credit',p.amount,'paid_currency',p.paid_currency,'paid_amount',p.paid_amount,
               'staff',p.staff_name,'note',p.note,'voided',p.voided) as x
          from public.motor_payments p join public.motor_customers c on c.id = p.customer_id
         where p.site_id = sid and p.method = 'whish' and (p.created_at at time zone 'Asia/Beirut')::date between f and t
        union all
        select jsonb_build_object('t','move','id',m.id,'at',m.created_at,'kind',m.kind,
               'debit', case when m.kind = 'withdraw' then abs(m.amount) when m.amount < 0 then -m.amount else 0 end,
               'credit', case when m.kind = 'withdraw' then 0 when m.amount > 0 then m.amount else 0 end,
               'note',m.note,'staff',m.by_name)
          from public.motor_moves m
         where m.site_id = sid and m.account = 'whish' and (m.created_at at time zone 'Asia/Beirut')::date between f and t
      ) q), '[]'::jsonb));
end $$;

-- حركة: تسليم جابي (handover, amount > 0) / سحب أو إيداع Whish / تسوية
create or replace function public.motor_move_add(p_slug text, p_token text, p_account text, p_staff uuid,
  p_kind text, p_amount numeric, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; m public.motor_moves%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_account not in ('collector','whish','cash') then perform public._motor_err('bad_account'); end if;
  if coalesce(p_amount,0) = 0 then perform public._motor_err('bad_amount'); end if;
  if p_account = 'collector' then
    if p_kind not in ('handover','adjust') then perform public._motor_err('bad_kind'); end if;
    if not exists (select 1 from public.motor_staff where id = p_staff and site_id = sid) then perform public._motor_err('bad_staff'); end if;
  elsif p_account = 'whish' then
    if p_kind not in ('withdraw','deposit','adjust') then perform public._motor_err('bad_kind'); end if;
    p_staff := null;
  else
    if p_kind not in ('in','out','adjust') then perform public._motor_err('bad_kind'); end if;
    p_staff := null;
  end if;
  insert into public.motor_moves (site_id, account, staff_id, kind, amount, note, by_name)
  values (sid, p_account, p_staff, p_kind, case when p_kind in ('handover','withdraw','deposit','in','out') then abs(p_amount) else p_amount end,
          coalesce(p_note,''), w->>'name')
  returning * into m;
  return jsonb_build_object('ok', true, 'move', to_jsonb(m) - 'site_id');
end $$;

create or replace function public.motor_move_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  if exists (select 1 from public.motor_moves m where m.id = p_id and (m.kind = 'close'
       or ((m.account = 'cash' or (m.account = 'collector' and m.kind = 'handover')) and m.created_at <= coalesce((select max(created_at)
            from public.motor_moves where site_id = m.site_id and account = 'cash' and kind = 'close'), '-infinity'::timestamptz)))) then
    perform public._motor_err('closed_period');
  end if;
  delete from public.motor_moves where id = p_id and site_id = (w->>'site_id')::uuid;
  return jsonb_build_object('ok', found);
end $$;

-- ============================================================
--  15) الصندوق (المكتب)
--      له: القبض النقدي من المدير/صاحب الاشتراك + تسليمات الجباة + إيداع
--      عليه: مصاريف/سحب + السحب عند الإقفال
-- ============================================================
create or replace function public._motor_cash_bal(p_sid uuid, p_before timestamptz default null)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select sum(p.amount) from public.motor_payments p left join public.motor_staff s on s.id = p.staff_id
                    where p.site_id = p_sid and p.method = 'cash' and not p.voided and (p.staff_id is null or s.role = 'admin')
                      and (p_before is null or p.created_at < p_before)), 0)
       + coalesce((select sum(m.amount) from public.motor_moves m where m.site_id = p_sid and m.account = 'collector' and m.kind = 'handover'
                      and (p_before is null or m.created_at < p_before)), 0)
       + coalesce((select sum(case when m.kind in ('out','close') then -abs(m.amount) else m.amount end)
                     from public.motor_moves m where m.site_id = p_sid and m.account = 'cash'
                      and (p_before is null or m.created_at < p_before)), 0);
$$;
revoke all on function public._motor_cash_bal(uuid, timestamptz) from public, anon, authenticated;

create or replace function public.motor_cash_statement(p_slug text, p_token text, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; f date; t date;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  f := coalesce(p_from, date '2000-01-01'); t := coalesce(p_to, date '2999-12-31');
  return jsonb_build_object(
    'opening', public._motor_cash_bal(sid, (f::timestamp at time zone 'Asia/Beirut')),
    'balance_now', public._motor_cash_bal(sid, null),
    'last_close', (select jsonb_build_object('at', m.created_at, 'by', m.by_name, 'extra', m.extra, 'amount', m.amount)
                     from public.motor_moves m where m.site_id = sid and m.account = 'cash' and m.kind = 'close'
                     order by m.created_at desc limit 1),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'customer',c.name,'code',c.code,
               'credit',p.amount,'debit',0,'paid_currency',p.paid_currency,'paid_amount',p.paid_amount,
               'staff',p.staff_name,'note',p.note,'voided',p.voided) as x
          from public.motor_payments p join public.motor_customers c on c.id = p.customer_id
          left join public.motor_staff s on s.id = p.staff_id
         where p.site_id = sid and p.method = 'cash' and (p.staff_id is null or s.role = 'admin')
           and (p.created_at at time zone 'Asia/Beirut')::date between f and t
        union all
        select jsonb_build_object('t','move','id',m.id,'at',m.created_at,'kind', case when m.account = 'collector' then 'handover' else m.kind end,
               'credit', case when m.account = 'collector' or m.kind = 'in' or (m.kind = 'adjust' and m.amount > 0) then abs(m.amount) else 0 end,
               'debit',  case when m.kind in ('out','close') or (m.kind = 'adjust' and m.amount < 0) then abs(m.amount) else 0 end,
               'staff', case when m.account = 'collector' then (select name from public.motor_staff where id = m.staff_id) else m.by_name end,
               'by', m.by_name, 'note', m.note, 'extra', m.extra)
          from public.motor_moves m
         where m.site_id = sid and (m.account = 'cash' or (m.account = 'collector' and m.kind = 'handover'))
           and (m.created_at at time zone 'Asia/Beirut')::date between f and t
      ) q), '[]'::jsonb));
end $$;

-- إقفال الصندوق (المدير فقط): المعدود فعلياً + المسحوب. الفرق بينسجّل تسوية، والباقي بيكمّل للفترة الجاية
create or replace function public.motor_cash_close(p_slug text, p_token text, p_counted numeric, p_withdraw numeric, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; expct numeric; diff numeric;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  perform 1 from public.motor_sites where id = sid for update;
  if p_counted is null or p_counted < 0 or coalesce(p_withdraw,0) < 0 or coalesce(p_withdraw,0) > p_counted then
    perform public._motor_err('bad_amount');
  end if;
  expct := public._motor_cash_bal(sid, null);
  diff := p_counted - expct;
  if diff <> 0 then
    insert into public.motor_moves (site_id, account, kind, amount, note, by_name, created_at)
    values (sid, 'cash', 'adjust', diff, 'فرق الإقفال', w->>'name', clock_timestamp());
  end if;
  insert into public.motor_moves (site_id, account, kind, amount, note, by_name, extra, created_at)
  values (sid, 'cash', 'close', coalesce(p_withdraw,0), coalesce(p_note,''), w->>'name',
          jsonb_build_object('expected', expct, 'counted', p_counted, 'diff', diff, 'carried', p_counted - coalesce(p_withdraw,0)),
          clock_timestamp() + interval '1 millisecond');
  return jsonb_build_object('ok', true, 'expected', expct, 'counted', p_counted, 'diff', diff,
                            'carried', p_counted - coalesce(p_withdraw,0));
end $$;

-- ============================================================
--  16) فتح/قطع الاشتراك + ملاحظات الموظفين
-- ============================================================
create or replace function public.motor_set_active(p_slug text, p_token text, p_customer uuid, p_active boolean,
  p_note text default '', p_lat double precision default null, p_lng double precision default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not (w->>'can_cut')::boolean then perform public._motor_err('forbidden'); end if;
  select * into c from public.motor_customers where id = p_customer and site_id = sid for update;
  if not found then perform public._motor_err('customer_not_found'); end if;
  if c.is_active = coalesce(p_active,false) then return jsonb_build_object('ok', true, 'is_active', c.is_active); end if;
  update public.motor_customers set is_active = p_active,
         stopped_at = case when p_active then null else now() end,
         stopped_by = case when p_active then '' else w->>'name' end,
         updated_at = now()
   where id = c.id;
  insert into public.motor_switch_log (site_id, customer_id, action, note, lat, lng, staff_id, staff_name)
  values (sid, c.id, case when p_active then 'connect' else 'cut' end, coalesce(p_note,''), p_lat, p_lng,
          (w->>'staff_id')::uuid, w->>'name');
  return jsonb_build_object('ok', true, 'is_active', p_active);
end $$;

create or replace function public.motor_note_add(p_slug text, p_token text, p_customer uuid, p_body text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(trim(p_body),'') = '' then perform public._motor_err('bad_data'); end if;
  if not exists (select 1 from public.motor_customers where id = p_customer and site_id = sid) then
    perform public._motor_err('customer_not_found');
  end if;
  insert into public.motor_notes (site_id, customer_id, body, staff_id, staff_name)
  values (sid, p_customer, left(trim(p_body), 500), (w->>'staff_id')::uuid, w->>'name');
  update public.motor_customers set updated_at = now() where id = p_customer;
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  17) مواقع الموظفين على الخريطة
-- ============================================================
create or replace function public.motor_ping(p_slug text, p_token text, p_lat double precision, p_lng double precision,
  p_acc double precision default null)
returns void language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_who(p_slug, p_token);
  if w->>'staff_id' is null or not public._motor_geo_ok(p_lat, p_lng) then return; end if;
  update public.motor_staff set last_lat = p_lat, last_lng = p_lng, last_acc = p_acc, last_seen = now()
   where id = (w->>'staff_id')::uuid;
end $$;

create or replace function public.motor_staff_map(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return jsonb_build_object('staff', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'role', s.role,
           'lat', s.last_lat, 'lng', s.last_lng, 'acc', s.last_acc, 'seen', s.last_seen, 'is_active', s.is_active,
           'reads_today', (select count(*) from public.motor_readings r where r.staff_id = s.id
                             and (r.created_at at time zone 'Asia/Beirut')::date = public._motor_today()),
           'pays_today', (select count(*) from public.motor_payments p where p.staff_id = s.id and not p.voided
                             and (p.created_at at time zone 'Asia/Beirut')::date = public._motor_today())))
         from public.motor_staff s where s.site_id = sid and s.last_lat is not null), '[]'::jsonb),
    'readings', coalesce((select jsonb_agg(jsonb_build_object('lat', r.lat, 'lng', r.lng, 'name', c.name, 'staff', r.staff_name, 'at', r.created_at))
         from public.motor_readings r join public.motor_customers c on c.id = r.customer_id
         where r.site_id = sid and r.lat is not null and (r.created_at at time zone 'Asia/Beirut')::date = public._motor_today()), '[]'::jsonb));
end $$;

-- ============================================================
--  18) التحقق بخطوتين للموظفين
-- ============================================================
create or replace function public.motor_2fa_setup(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare w jsonb; sec text; st public.motor_sites%rowtype; u text;
begin
  w := public._motor_who(p_slug, p_token);
  if w->>'staff_id' is null then perform public._motor_err('forbidden'); end if;
  sec := public._motor_b32_encode(gen_random_bytes(20));
  update public.motor_staff_secrets set totp_pending = sec where staff_id = (w->>'staff_id')::uuid;
  select * into st from public.motor_sites where id = (w->>'site_id')::uuid;
  select username into u from public.motor_staff where id = (w->>'staff_id')::uuid;
  return jsonb_build_object('secret', sec,
    'uri', 'otpauth://totp/' || replace(coalesce(nullif(st.name,''), st.slug),' ','%20') || ':' || u ||
           '?secret=' || sec || '&issuer=LibanApps%20Motor&digits=6&period=30');
end $$;

create or replace function public.motor_2fa_enable(p_slug text, p_token text, p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sc public.motor_staff_secrets%rowtype;
begin
  w := public._motor_who(p_slug, p_token);
  if w->>'staff_id' is null then perform public._motor_err('forbidden'); end if;
  select * into sc from public.motor_staff_secrets where staff_id = (w->>'staff_id')::uuid;
  if coalesce(sc.totp_pending,'') = '' or not public._motor_totp_ok(sc.totp_pending, trim(coalesce(p_code,''))) then
    perform public._motor_err('bad_totp');
  end if;
  update public.motor_staff_secrets set totp_secret = totp_pending, totp_pending = null where staff_id = sc.staff_id;
  update public.motor_staff set totp_enabled = true where id = sc.staff_id;
  return jsonb_build_object('ok', true);
end $$;

-- الموظف يلغي 2FA عن حالو (بالرمز) — أو المدير يلغيه لأي موظف (p_staff)
create or replace function public.motor_2fa_disable(p_slug text, p_token text, p_code text default null, p_staff uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; target uuid; sc public.motor_staff_secrets%rowtype;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_staff is not null and p_staff::text is distinct from w->>'staff_id' then
    if not (w->>'is_admin')::boolean then perform public._motor_err('forbidden'); end if;
    if not exists (select 1 from public.motor_staff where id = p_staff and site_id = sid) then perform public._motor_err('bad_staff'); end if;
    target := p_staff;
  else
    target := (w->>'staff_id')::uuid;
    if target is null then perform public._motor_err('forbidden'); end if;
    select * into sc from public.motor_staff_secrets where staff_id = target;
    if not public._motor_totp_ok(sc.totp_secret, trim(coalesce(p_code,''))) then perform public._motor_err('bad_totp'); end if;
  end if;
  update public.motor_staff_secrets set totp_secret = null, totp_pending = null where staff_id = target;
  update public.motor_staff set totp_enabled = false where id = target;
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  19) واتساب من المكتب: الفواتير والإيصالات يلّي بعد ما انبعتت
-- ============================================================
create or replace function public.motor_wa_outbox(p_slug text, p_token text, p_days integer default 60)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return coalesce((select jsonb_agg(x order by x->>'at') from (
      select jsonb_build_object('t','inv','id',i.id,'at',i.created_at,'inv',to_jsonb(i) - 'site_id',
             'customer', jsonb_build_object('id',c.id,'code',c.code,'name',c.name,'mobile',c.mobile,'mobile_cc',c.mobile_cc,'box',c.box)) as x
        from public.motor_invoices i join public.motor_customers c on c.id = i.customer_id
       where i.site_id = sid and not i.voided and i.kind in ('meter','fixed') and i.wa_sent_at is null
         and i.created_at > now() - make_interval(days => greatest(1, coalesce(p_days,60)))
      union all
      select jsonb_build_object('t','pay','id',p.id,'at',p.created_at,'pay',to_jsonb(p) - 'site_id',
             'inv', (select to_jsonb(i) - 'site_id' from public.motor_invoices i where i.customer_id = p.customer_id
                      and not i.voided and i.kind in ('meter','fixed') and i.created_at <= p.created_at
                      order by i.created_at desc limit 1),
             'customer', jsonb_build_object('id',c.id,'code',c.code,'name',c.name,'mobile',c.mobile,'mobile_cc',c.mobile_cc,'box',c.box))
        from public.motor_payments p join public.motor_customers c on c.id = p.customer_id
       where p.site_id = sid and not p.voided and p.wa_sent_at is null
         and p.created_at > now() - make_interval(days => greatest(1, coalesce(p_days,60)))
    ) q), '[]'::jsonb);
end $$;

create or replace function public.motor_wa_mark(p_slug text, p_token text, p_kind text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_kind = 'inv' then
    update public.motor_invoices set wa_sent_at = now(), wa_sent_by = w->>'name' where id = p_id and site_id = sid;
  elsif p_kind = 'pay' then
    update public.motor_payments set wa_sent_at = now(), wa_sent_by = w->>'name' where id = p_id and site_id = sid;
  else perform public._motor_err('bad_kind'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  20) لوحة سريعة
-- ============================================================
create or replace function public.motor_dashboard(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; st public.motor_sites%rowtype; mine boolean; me uuid; m0 date; today date := public._motor_today();
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid; mine := not (w->>'is_admin')::boolean; me := (w->>'staff_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  m0 := date_trunc('month', today)::date;
  return jsonb_build_object(
    'period', st.bill_period, 'lbp_rate', st.lbp_rate,
    'customers_active', (select count(*) from public.motor_customers where site_id = sid and is_active and not archived),
    'customers_total', (select count(*) from public.motor_customers where site_id = sid),
    'read_period', (select count(*) from public.motor_readings where site_id = sid and period = st.bill_period
                     and (not mine or staff_id = me)),
    'billed_period', coalesce((select sum(amount) from public.motor_invoices where site_id = sid and period = st.bill_period
                     and kind in ('meter','fixed') and not voided and (not mine or staff_id = me)), 0),
    'unpaid_count', (select count(*) from public.motor_customers where site_id = sid and balance > 0 and not archived),
    'debt_total', case when mine then null else coalesce((select sum(balance) from public.motor_customers
                     where site_id = sid and balance > 0), 0) end,
    'cash_box', case when mine then null else public._motor_cash_bal(sid, null) end,
    'whish_box', case when mine then null else
                   coalesce((select sum(amount) from public.motor_payments where site_id = sid and method = 'whish' and not voided), 0)
                 + coalesce((select sum(case when kind = 'withdraw' then -abs(amount) else amount end) from public.motor_moves
                              where site_id = sid and account = 'whish'), 0) end,
    'wa_pending', case when mine then null else
        (select count(*) from public.motor_invoices i where i.site_id = sid and not i.voided and i.kind in ('meter','fixed')
            and i.wa_sent_at is null and i.created_at > now() - interval '60 days')
      + (select count(*) from public.motor_payments p where p.site_id = sid and not p.voided
            and p.wa_sent_at is null and p.created_at > now() - interval '60 days') end,
    'cash_today', coalesce((select sum(amount) from public.motor_payments where site_id = sid and method = 'cash' and not voided
                     and (created_at at time zone 'Asia/Beirut')::date = today and (not mine or staff_id = me)), 0),
    'whish_today', coalesce((select sum(amount) from public.motor_payments where site_id = sid and method = 'whish' and not voided
                     and (created_at at time zone 'Asia/Beirut')::date = today and (not mine or staff_id = me)), 0),
    'collected_month', coalesce((select sum(amount) from public.motor_payments where site_id = sid and not voided
                     and (created_at at time zone 'Asia/Beirut')::date >= m0 and (not mine or staff_id = me)), 0),
    'my_cash_in_hand', case when me is null or not mine then null else
                     coalesce((select sum(amount) from public.motor_payments where staff_id = me and method = 'cash' and not voided), 0)
                   - coalesce((select sum(amount) from public.motor_moves where staff_id = me and account = 'collector'), 0) end);
end $$;

-- ============================================================
--  21) رفع صورة العداد — تستدعيها الـWorker (/api/motor-photo) قبل الرفع
-- ============================================================
create or replace function public.motor_upload_ok(p_slug text, p_token text)
returns uuid language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_who(p_slug, p_token);
  return (w->>'site_id')::uuid;
end $$;

do $$ begin
  insert into storage.buckets (id, name, public) values ('motor','motor', true)
  on conflict (id) do nothing;
exception when others then raise notice 'bucket skipped: %', sqlerrm;
end $$;

-- ============================================================
--  22) صلاحيات التنفيذ
-- ============================================================
do $$
declare f text;
begin
  foreach f in array array[
    'motor_public(text)', 'motor_logout(text)',
    'motor_change_password(text,text,text,text)', 'motor_me(text,text)', 'motor_customers(text,text)',
    'motor_customer_get(text,text,uuid,text)', 'motor_customer_save(text,text,jsonb)',
    'motor_customer_delete(text,text,uuid)', 'motor_import(text,text,jsonb)', 'motor_statement(text,text,uuid)',
    'motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision)',
    'motor_bill_fixed(text,text)', 'motor_invoice_void(text,text,uuid)', 'motor_adjust(text,text,uuid,numeric,text)',
    'motor_pay(text,text,uuid,numeric,text,text,text,double precision,double precision)',
    'motor_payment_void(text,text,uuid)', 'motor_month(text,text,text)', 'motor_settings_save(text,text,jsonb)',
    'motor_plan_save(text,text,jsonb)', 'motor_plan_delete(text,text,uuid)', 'motor_staff_save(text,text,jsonb,text)',
    'motor_window_all(text,text,date,date)', 'motor_staff_delete(text,text,uuid)',
    'motor_collector_statement(text,text,uuid,date,date)', 'motor_whish_statement(text,text,date,date)',
    'motor_move_add(text,text,text,uuid,text,numeric,text)', 'motor_move_delete(text,text,uuid)',
    'motor_dashboard(text,text)', 'motor_upload_ok(text,text)', 'motor_slug_available(text)',
    'motor_login(text,text,text,text)', 'motor_changes(text,text,timestamptz)',
    'motor_cash_statement(text,text,date,date)', 'motor_cash_close(text,text,numeric,numeric,text)',
    'motor_set_active(text,text,uuid,boolean,text,double precision,double precision)',
    'motor_note_add(text,text,uuid,text)', 'motor_ping(text,text,double precision,double precision,double precision)',
    'motor_staff_map(text,text)', 'motor_2fa_setup(text,text)', 'motor_2fa_enable(text,text,text)',
    'motor_2fa_disable(text,text,text,uuid)', 'motor_wa_outbox(text,text,integer)', 'motor_wa_mark(text,text,text,uuid)']
  loop
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;

revoke all on function public.admin_new_motor(uuid, text, text, integer, numeric) from public, anon;
revoke all on function public.ensure_motor(text) from public, anon;
revoke all on function public.start_motor_trial(text, text) from public, anon;
revoke all on function public.admin_motor_product(numeric, numeric, integer, boolean) from public, anon;
grant execute on function public.admin_new_motor(uuid, text, text, integer, numeric) to authenticated;
grant execute on function public.ensure_motor(text) to authenticated;
grant execute on function public.start_motor_trial(text, text) to authenticated;
grant execute on function public.admin_motor_product(numeric, numeric, integer, boolean) to authenticated;
revoke all on function public._motor_round(uuid, numeric) from public, anon, authenticated;

-- تحقق سريع
select 'motor product' as item, exists (select 1 from public.products where code = 'motor') as ok
union all select 'motor plan', exists (select 1 from public.plans where product_code = 'motor')
union all select 'motor tables', to_regclass('public.motor_customers') is not null and to_regclass('public.motor_moves') is not null
union all select 'portal link ok', pg_get_functiondef('public.my_client_id()'::regprocedure) like '%portal_users%'
union all select 'read function', to_regprocedure('public.motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision)') is not null;
