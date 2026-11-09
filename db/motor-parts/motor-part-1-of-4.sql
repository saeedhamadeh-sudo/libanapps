-- motorapp — الجزء 1 من 4 (شغّل الأجزاء بالترتيب)
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

-- ---------- إضافات v3 ----------
alter table public.motor_sites add column if not exists whish_qr_url text not null default '';   -- صورة QR الخاصة بـ Whish
alter table public.motor_sites add column if not exists whish_phone  text not null default '';   -- رقم Whish تحت الـQR

-- حساب دخول للزبون (يرى فواتيره وكشف حسابه)
alter table public.motor_customers add column if not exists username text not null default '';
create unique index if not exists motor_customers_user_uq on public.motor_customers (site_id, lower(username)) where username <> '';
create table if not exists public.motor_customer_secrets (
  customer_id   uuid primary key references public.motor_customers(id) on delete cascade,
  password_hash text not null,
  failed_count  integer not null default 0,
  locked_until  timestamptz,
  updated_at    timestamptz not null default now()
);
-- ---------- v4: سلة المحذوفات ----------
alter table public.motor_customers add column if not exists deleted_at timestamptz;
alter table public.motor_customers add column if not exists next_prev numeric(14,2);   -- عداد سابق يحدده المدير للقراءة الجاية
alter table public.motor_invoices  add column if not exists voided_reading jsonb;   -- القراءة الملغاة (لإرجاعها من السلة)
create table if not exists public.motor_trash (
  id         uuid primary key default gen_random_uuid(),
  site_id    uuid not null references public.motor_sites(id) on delete cascade,
  kind       text not null,          -- customer / invoice / payment / move / plan / staff / note
  ref_id     uuid,
  label      text not null default '',
  data       jsonb not null default '{}'::jsonb,
  deleted_by text not null default '',
  deleted_at timestamptz not null default now()
);
create index if not exists motor_trash_site_idx on public.motor_trash (site_id, deleted_at desc);

-- ---------- v5: قفل الجهاز، المعاشات، المصاريف، المخزون، إقفال اليومية ----------
alter table public.motor_sites add column if not exists voucher_seq integer not null default 0;
alter table public.motor_staff add column if not exists is_main      boolean not null default false;  -- المدير الأساسي
alter table public.motor_staff add column if not exists salary       numeric(14,2) not null default 0;
alter table public.motor_staff add column if not exists device_id    text;
alter table public.motor_staff add column if not exists device_label text not null default '';
alter table public.motor_staff add column if not exists device_at    timestamptz;
alter table public.motor_moves add column if not exists category  text not null default '';
alter table public.motor_moves add column if not exists vno       integer;          -- رقم سند الصرف
alter table public.motor_moves add column if not exists pay_staff uuid;             -- معاش لموظف
alter table public.motor_moves add column if not exists period    text not null default '';
create table if not exists public.motor_stock (
  id         uuid primary key default gen_random_uuid(),
  site_id    uuid not null references public.motor_sites(id) on delete cascade,
  name       text not null,
  category   text not null default '',
  qty        numeric(14,2) not null default 0,
  unit_price numeric(14,2) not null default 0,
  notes      text not null default '',
  updated_by text not null default '',
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists motor_stock_site_idx on public.motor_stock (site_id, name);
create table if not exists public.motor_day_closes (
  id        uuid primary key default gen_random_uuid(),
  site_id   uuid not null references public.motor_sites(id) on delete cascade,
  day       date not null,
  totals    jsonb not null default '{}'::jsonb,
  closed_by text not null default '',
  closed_at timestamptz not null default now(),
  unique (site_id, day)
);

create table if not exists public.motor_csessions (
  token_hash  text primary key,
  customer_id uuid not null references public.motor_customers(id) on delete cascade,
  site_id     uuid not null references public.motor_sites(id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '60 days'
);

-- كل الجداول مقفلة على المتصفح — الوصول عبر الدوال فقط
do $$
declare t text;
begin
  foreach t in array array['motor_sites','motor_plans','motor_staff','motor_staff_secrets','motor_sessions',
                           'motor_customers','motor_readings','motor_invoices','motor_payments','motor_moves',
                           'motor_notes','motor_switch_log','motor_customer_secrets','motor_csessions','motor_trash',
                           'motor_stock','motor_day_closes']
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

create or replace function public._motor_hash(p text)
returns text language sql volatile security definer set search_path = public, extensions as $$
  select crypt(p, gen_salt('bf', 8));
$$;
revoke all on function public._motor_hash(text) from public, anon, authenticated;

-- مستخدم المدير الافتراضي: ADMIN / 0000 (يغيّره من داخل البرنامج)
create or replace function public._motor_default_admin(p_site uuid)
returns void language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  if exists (select 1 from public.motor_staff where site_id = p_site and role = 'admin') then return; end if;
  if exists (select 1 from public.motor_staff where site_id = p_site and lower(username) = 'admin') then return; end if;
  insert into public.motor_staff (site_id, name, username, role, can_read, can_collect, can_cut, is_main)
  values (p_site, 'المدير', 'admin', 'admin', true, true, true, true) returning id into sid;
  insert into public.motor_staff_secrets (staff_id, password_hash) values (sid, public._motor_hash('0000'));
end $$;
revoke all on function public._motor_default_admin(uuid) from public, anon, authenticated;

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
  perform public._motor_default_admin(st.id);
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

-- دورة الفوترة تلقائية: من 26 الشهر لآخره = هالشهر، ومن 1 لـ 25 = الشهر الماضي (قراءات متأخرة)
create or replace function public._motor_period(d date)
returns text language sql immutable as $$
  select to_char(case when extract(day from d) >= 26 then d else (d - interval '1 month')::date end, 'YYYY-MM');
$$;

create or replace function public._motor_who(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare st public.motor_sites%rowtype; sf public.motor_staff%rowtype; sid uuid; lic jsonb; cn text;
begin
  select * into st from public.motor_sites where slug = lower(trim(coalesce(p_slug,'')));
  if not found then perform public._motor_err('not_found'); end if;
  if st.bill_period <> public._motor_period(public._motor_today()) then
    update public.motor_sites set bill_period = public._motor_period(public._motor_today()) where id = st.id;
  end if;

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
                              'is_admin', true, 'is_main', true, 'can_collect', true, 'can_read', true, 'can_cut', true,
                              'totp_enabled', false, 'read_from', null, 'read_to', null);
  end if;
  return jsonb_build_object('site_id', st.id, 'role', sf.role, 'staff_id', sf.id, 'name', sf.name,
                            'is_admin', sf.role = 'admin', 'is_main', sf.is_main,
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
  -- ±4 دقائق: ساعة الهاتف كثيراً ما تكون متقدّمة أو متأخرة دقيقة أو دقيقتين
  for w in -8..8 loop
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
drop function if exists public.motor_login(text, text, text, text);
create or replace function public.motor_login(p_slug text, p_username text, p_password text, p_totp text default null,
  p_device text default null, p_device_label text default '')
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare st public.motor_sites%rowtype; sf public.motor_staff%rowtype; sc public.motor_staff_secrets%rowtype;
        tok text; lic jsonb; cu public.motor_customers%rowtype; cs public.motor_customer_secrets%rowtype;
begin
  select * into st from public.motor_sites where slug = lower(trim(coalesce(p_slug,'')));
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  lic := public.motor_license(st.id);
  if not st.is_active or not coalesce((lic->>'ok')::boolean,false) then
    return jsonb_build_object('ok', false, 'reason', 'license');
  end if;
  select * into sf from public.motor_staff
   where site_id = st.id and lower(username) = lower(trim(coalesce(p_username,'')));
  if not found then
    -- حساب زبون؟
    select * into cu from public.motor_customers
     where site_id = st.id and username <> '' and lower(username) = lower(trim(coalesce(p_username,'')));
    if not found then perform pg_sleep(0.4); return jsonb_build_object('ok', false, 'reason', 'bad_login'); end if;
    select * into cs from public.motor_customer_secrets where customer_id = cu.id for update;
    if not found then return jsonb_build_object('ok', false, 'reason', 'bad_login'); end if;
    if cs.locked_until is not null and cs.locked_until > now() then
      return jsonb_build_object('ok', false, 'reason', 'locked', 'minutes', ceil(extract(epoch from (cs.locked_until - now()))/60)::int);
    end if;
    if cs.password_hash <> crypt(coalesce(p_password,''), cs.password_hash) then
      update public.motor_customer_secrets set failed_count = failed_count + 1,
             locked_until = case when failed_count + 1 >= 6 then now() + interval '15 minutes' end where customer_id = cu.id;
      return jsonb_build_object('ok', false, 'reason', 'bad_login');
    end if;
    update public.motor_customer_secrets set failed_count = 0, locked_until = null where customer_id = cu.id;
    delete from public.motor_csessions where customer_id = cu.id and expires_at < now();
    tok := encode(gen_random_bytes(24),'hex');
    insert into public.motor_csessions (token_hash, customer_id, site_id) values (encode(digest(tok,'sha256'),'hex'), cu.id, st.id);
    return jsonb_build_object('ok', true, 'token', tok, 'kind', 'customer', 'name', cu.name);
  end if;
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
  -- قفل الجهاز: كل مستخدم (إلا المدير الأساسي) على جهاز واحد فقط
  if not sf.is_main then
    if coalesce(p_device,'') !~ '^[A-Za-z0-9-]{16,64}$' then return jsonb_build_object('ok', false, 'reason', 'device'); end if;
    if sf.device_id is null then
      update public.motor_staff set device_id = p_device, device_label = left(coalesce(p_device_label,''), 120), device_at = now() where id = sf.id;
    elsif sf.device_id <> p_device then
      return jsonb_build_object('ok', false, 'reason', 'device');
    end if;
  end if;
  update public.motor_staff_secrets set failed_count = 0, locked_until = null where staff_id = sf.id;
  delete from public.motor_sessions where staff_id = sf.id and expires_at < now();
  tok := encode(gen_random_bytes(24),'hex');
  insert into public.motor_sessions (token_hash, staff_id, site_id)
  values (encode(digest(tok,'sha256'),'hex'), sf.id, st.id);
  return jsonb_build_object('ok', true, 'token', tok, 'kind', 'staff', 'role', sf.role, 'name', sf.name);
end $$;

create or replace function public.motor_logout(p_token text)
returns void language sql security definer set search_path = public, extensions as $$
  delete from public.motor_sessions where token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex');
  delete from public.motor_csessions where token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex');
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

