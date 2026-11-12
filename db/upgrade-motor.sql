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
alter table public.motor_sessions add column if not exists impersonated_by text;   -- دخول المدير الأساسي على حساب موظف

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
-- ---------- v6: حركات المخزون، الموردون والمشتريات، استحقاقات المعاشات ----------
alter table public.motor_sites add column if not exists purchase_seq integer not null default 0;
alter table public.motor_moves add column if not exists supplier_id uuid;
create table if not exists public.motor_stock_moves (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references public.motor_sites(id) on delete cascade,
  item_id     uuid not null,
  item_name   text not null default '',
  kind        text not null check (kind in ('out','in','purchase','adjust','void')),
  qty         numeric(14,2) not null,                 -- موجب = دخول، سالب = خروج
  unit_price  numeric(14,2) not null default 0,
  taker       text not null default '',               -- مين سحب
  staff_id    uuid,
  purchase_id uuid,
  note        text not null default '',
  by_name     text not null default '',
  created_at  timestamptz not null default now()
);
create index if not exists motor_stock_moves_idx on public.motor_stock_moves (site_id, created_at desc);
create index if not exists motor_stock_moves_item_idx on public.motor_stock_moves (item_id, created_at desc);
create table if not exists public.motor_suppliers (
  id         uuid primary key default gen_random_uuid(),
  site_id    uuid not null references public.motor_sites(id) on delete cascade,
  name       text not null,
  phone      text not null default '',
  notes      text not null default '',
  created_at timestamptz not null default now()
);
create table if not exists public.motor_purchases (
  id          uuid primary key default gen_random_uuid(),
  site_id     uuid not null references public.motor_sites(id) on delete cascade,
  supplier_id uuid not null references public.motor_suppliers(id) on delete restrict,
  no          integer not null,
  ref         text not null default '',                -- رقم فاتورة المورد
  day         date not null,
  items       jsonb not null default '[]'::jsonb,
  total       numeric(14,2) not null default 0,
  to_stock    boolean not null default true,
  note        text not null default '',
  by_name     text not null default '',
  voided      boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists motor_purchases_idx on public.motor_purchases (site_id, supplier_id, day);
create table if not exists public.motor_salary_dues (
  id         uuid primary key default gen_random_uuid(),
  site_id    uuid not null references public.motor_sites(id) on delete cascade,
  staff_id   uuid not null references public.motor_staff(id) on delete cascade,
  period     text not null,
  amount     numeric(14,2) not null,
  note       text not null default '',
  by_name    text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists motor_salary_dues_idx on public.motor_salary_dues (staff_id, period);

-- ---------- v7: استيراد فواتير البرنامج السابق ----------
alter table public.motor_invoices add column if not exists imported boolean not null default false;
alter table public.motor_readings add column if not exists imported boolean not null default false;
alter table public.motor_readings add column if not exists remote boolean not null default false;   -- قراءة عن بعد (صورة من الزبون)

-- ---------- v8: التأمينات ----------
create table if not exists public.motor_insurance (
  id           uuid primary key default gen_random_uuid(),
  site_id      uuid not null references public.motor_sites(id) on delete cascade,
  customer_id  uuid references public.motor_customers(id) on delete set null,
  name         text not null default '',             -- اسم المشترك كما هو
  kind         text not null check (kind in ('in','out')),   -- in = قبض تأمين، out = إعادة تأمين
  amount       numeric(14,2) not null,
  account      text not null default '',             -- cash / whish ('' = مستورد)
  ref_no       text not null default '',
  service      text not null default '',
  note         text not null default '',
  move_id      uuid,
  by_name      text not null default '',
  imported     boolean not null default false,
  created_at   timestamptz not null default now()
);
create index if not exists motor_insurance_idx on public.motor_insurance (site_id, created_at);
create index if not exists motor_insurance_cust_idx on public.motor_insurance (customer_id);

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
                           'motor_stock','motor_day_closes','motor_stock_moves','motor_suppliers','motor_purchases','motor_salary_dues','motor_insurance']
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
                         'totp_enabled', s.totp_enabled, 'is_main', s.is_main,
                         'salary', case when adm then s.salary end,
                         'device_set', s.device_id is not null, 'device_label', case when adm then s.device_label end,
                         'device_at', case when adm then s.device_at end,
                         'last_lat', case when coalesce((w->>'is_main')::boolean,false) then s.last_lat end, 'last_lng', case when coalesce((w->>'is_main')::boolean,false) then s.last_lng end,
                         'last_acc', case when coalesce((w->>'is_main')::boolean,false) then s.last_acc end, 'last_seen', case when coalesce((w->>'is_main')::boolean,false) then s.last_seen end)
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
      'last_value', coalesce(c.next_prev, lr.value, c.initial_reading),
      'read_now', (rn.id is not null), 'read_now_value', rn.value, 'read_now_prev', rn.prev_value,
      'last_note', nt.body, 'last_note_by', nt.staff_name, 'last_note_at', nt.created_at,
      'updated_at', c.updated_at, 'deleted', c.deleted_at is not null) order by c.code, c.name), '[]'::jsonb)
  from public.motor_customers c
  join public.motor_sites st on st.id = c.site_id
  left join public.motor_staff sf on sf.id = c.collector_id
  left join lateral (select r.value from public.motor_readings r where r.customer_id = c.id
                     order by r.created_at desc limit 1) lr on true
  left join public.motor_readings rn on rn.customer_id = c.id and rn.period = st.bill_period
  left join lateral (select n.body, n.staff_name, n.created_at from public.motor_notes n where n.customer_id = c.id
                     order by n.created_at desc limit 1) nt on true
  where c.site_id = p_sid and (p_own is null or c.collector_id = p_own)
    and (p_since is null or c.updated_at > p_since)
    and (c.deleted_at is null or p_since is not null);
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
    'wa_inv', case when (w->>'is_admin')::boolean then
        (select count(*) from public.motor_invoices i where i.site_id = sid and not i.voided and i.kind in ('meter','fixed')
            and i.wa_sent_at is null and i.created_at > now() - interval '60 days') end,
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
  if c.id is null or c.deleted_at is not null then perform public._motor_err('customer_not_found', coalesce(p_barcode,'')); end if;
  if w->>'role' = 'collector' and not st.collector_sees_all and c.collector_id is distinct from (w->>'staff_id')::uuid then
    perform public._motor_err('forbidden');
  end if;
  select * into pl from public.motor_plans where id = c.plan_id;
  select * into lr from public.motor_readings where customer_id = c.id order by created_at desc limit 1;
  select * into rn from public.motor_readings where customer_id = c.id and period = st.bill_period;
  return jsonb_build_object(
    'customer', to_jsonb(c) - 'site_id',
    'has_login', exists (select 1 from public.motor_customer_secrets x where x.customer_id = c.id) and c.username <> '',
    'insurance', coalesce((select sum(case when kind = 'in' then amount else -amount end) from public.motor_insurance where customer_id = c.id), 0),
    'plan', case when pl.id is null then null else to_jsonb(pl) - 'site_id' end,
    'collector_name', coalesce((select name from public.motor_staff where id = c.collector_id), c.collector_name),
    'prev_value', coalesce(c.next_prev, lr.value, c.initial_reading),
    'baseline', lr.id is null and st.first_read_baseline and coalesce(c.initial_reading,0) = 0 and c.next_prev is null,
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
    c.id := gen_random_uuid(); c.site_id := sid; c.code := seq; c.balance := 0; c.created_at := now(); c.username := '';
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
declare w jsonb; sid uuid; c public.motor_customers%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into c from public.motor_customers where id = p_id and site_id = sid and deleted_at is null for update;
  if not found then perform public._motor_err('customer_not_found'); end if;
  update public.motor_customers set deleted_at = now(), updated_at = now() where id = c.id;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  values (sid, 'customer', c.id, '#' || c.code || ' ' || c.name, jsonb_build_object('balance', c.balance, 'barcode', c.barcode), w->>'name');
  return jsonb_build_object('ok', true, 'trash', true);
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
        update public.motor_customers set deleted_at = null where id = ex and deleted_at is not null;
        delete from public.motor_trash where kind = 'customer' and ref_id = ex;
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
               'energy',i.energy,'discount',i.discount,'addition',i.addition,
               'debit',greatest(i.amount,0),'credit',greatest(-i.amount,0),'balance_before',i.balance_before,'balance_after',i.balance_after,
               'note',i.note,'staff',i.staff_name,'voided',i.voided,
               'photo', (select r.photo_url from public.motor_readings r where r.id = i.reading_id)) as x
          from public.motor_invoices i where i.customer_id = c.id
        union all
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'method',p.method,
               'paid_currency',p.paid_currency,'paid_amount',p.paid_amount,'rate',p.rate,
               'balance_before',p.balance_before,'balance_after',p.balance_after,
               'debit',0,'credit',p.amount,'note',p.note,'staff',p.staff_name,'voided',p.voided)
          from public.motor_payments p where p.customer_id = c.id
      ) q), '[]'::jsonb));
end $$;

-- ============================================================
--  9) أخذ العداد → قراءة + فاتورة بعملية واحدة
-- ============================================================
drop function if exists public.motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision);
create or replace function public.motor_read(p_slug text, p_token text, p_customer uuid, p_value numeric,
  p_photo text, p_lat double precision, p_lng double precision, p_accuracy double precision default null,
  p_remote boolean default false)
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
    -- فترة أخذ العداد ثابتة: من 26 لآخر يوم بالشهر (شباط 28 أو 29)
    if extract(day from today) < 26 then
      perform public._motor_err('out_of_window', to_char(today, 'YYYY-MM') || '-26');
    end if;
  end if;
  if not c.is_active then perform public._motor_err('customer_inactive'); end if;
  if exists (select 1 from public.motor_readings where customer_id = c.id and period = st.bill_period) then
    perform public._motor_err('already_read', st.bill_period);
  end if;
  if p_value is null or p_value < 0 then perform public._motor_err('bad_value'); end if;
  if st.require_photo and coalesce(p_photo,'') = '' and not (w->>'is_admin')::boolean then perform public._motor_err('photo_required'); end if;
  if coalesce(p_photo,'') <> '' and p_photo !~ ('^/img/motor/' || sid::text || '/') then
    perform public._motor_err('bad_photo');
  end if;
  -- قراءة عن بعد: الزبون بعت صورة العداد — لا موقع ولا فحص مسافة
  if coalesce(p_remote, false) then p_lat := null; p_lng := null; p_accuracy := null; end if;
  if st.require_gps and not coalesce(p_remote, false) and not public._motor_geo_ok(p_lat, p_lng) and not (w->>'is_admin')::boolean then perform public._motor_err('gps_required'); end if;

  select value into prev from public.motor_readings where customer_id = c.id order by created_at desc limit 1;
  if not found then
    prev := coalesce(c.initial_reading, 0);
    baseline := st.first_read_baseline and coalesce(c.initial_reading, 0) = 0 and c.next_prev is null;
  end if;
  if c.next_prev is not null then prev := c.next_prev; end if;   -- المدير حدّد العداد السابق
  if baseline then prev := p_value; end if;     -- أول قراءة = عداد أولي، بلا استهلاك
  if p_value < prev then perform public._motor_err('lower_than_prev', prev::text); end if;

  d := null;
  if public._motor_geo_ok(p_lat, p_lng) and public._motor_geo_ok(c.lat, c.lng) then
    d := public._motor_dist(c.lat, c.lng, p_lat, p_lng);   -- تسجيل المسافة فقط، بلا منع
  end if;

  insert into public.motor_readings (site_id, customer_id, period, prev_value, value, photo_url, lat, lng, accuracy,
                                     dist_m, staff_id, staff_name, remote)
  values (sid, c.id, st.bill_period, prev, p_value, coalesce(p_photo,''), p_lat, p_lng, p_accuracy, d,
          (w->>'staff_id')::uuid, w->>'name', coalesce(p_remote, false))
  returning id into rid;

  -- أول قراءة ميدانية لزبون بلا موقع: منثبّت موقعه (الدقة لازم تكون منيحة)
  if not public._motor_geo_ok(c.lat, c.lng) and public._motor_geo_ok(p_lat, p_lng) and coalesce(p_accuracy, 0) <= 60 then
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
  update public.motor_customers set balance = balance + amt, next_prev = null, updated_at = now() where id = c.id;

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
            where cu.site_id = sid and cu.is_active and not cu.archived and cu.deleted_at is null and pl.kind = 'fixed'
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
  update public.motor_invoices set voided = true, voided_at = now(), voided_by = w->>'name', reading_id = null,
         voided_reading = (select to_jsonb(r) from public.motor_readings r where r.id = i.reading_id) where id = i.id;
  if i.reading_id is not null then delete from public.motor_readings where id = i.reading_id; end if;
  update public.motor_customers set balance = balance - i.amount, updated_at = now() where id = i.customer_id;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  values (sid, 'invoice', i.id, 'فاتورة #' || i.no || coalesce(' ' || nullif(i.period,''), '') || ' — ' ||
          (select name from public.motor_customers where id = i.customer_id), jsonb_build_object('amount', i.amount), w->>'name');
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
  if m = 'whish' and not (w->>'is_admin')::boolean then perform public._motor_err('whish_admin'); end if;
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
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into p from public.motor_payments where id = p_id and site_id = sid for update;
  if not found then perform public._motor_err('not_found'); end if;
  if p.voided then return jsonb_build_object('ok', true); end if;
  -- الجابي بيلغي إيصالو هوّي بس، قبل ما يسلّم المصاري (قبل إقفال صندوقو أو أي تسليم للمكتب)
  if not (w->>'is_admin')::boolean then
    if not coalesce((w->>'can_collect')::boolean, false) or p.staff_id is distinct from (w->>'staff_id')::uuid then perform public._motor_err('forbidden'); end if;
    if p.created_at <= coalesce((select max(created_at) from public.motor_moves where staff_id = p.staff_id and account = 'collector'), '-infinity'::timestamptz) then
      perform public._motor_err('handed_over');
    end if;
  end if;
  if p.method = 'cash' and p.created_at <= coalesce((select max(created_at) from public.motor_moves
        where site_id = sid and account = 'cash' and kind = 'close'), '-infinity'::timestamptz) then
    perform public._motor_err('closed_period');
  end if;
  if exists (select 1 from public.motor_day_closes where site_id = sid and day = (p.created_at at time zone 'Asia/Beirut')::date) then
    perform public._motor_err('day_closed');
  end if;
  update public.motor_payments set voided = true, voided_at = now(), voided_by = w->>'name' where id = p.id;
  update public.motor_customers set balance = balance + p.amount, updated_at = now() where id = p.customer_id;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  values (sid, 'payment', p.id, 'إيصال #' || p.no || ' — ' || (select name from public.motor_customers where id = p.customer_id),
          jsonb_build_object('amount', p.amount), w->>'name');
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
      'photo', r.photo_url, 'lat', r.lat, 'lng', r.lng, 'accuracy', r.accuracy, 'dist_m', r.dist_m, 'remote', r.remote,
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
    whish_qr_url   = coalesce(d->>'whish_qr_url', whish_qr_url),
    whish_phone    = coalesce(d->>'whish_phone', whish_phone),
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
  if exists (select 1 from public.motor_customers where plan_id = p_id and deleted_at is null) then perform public._motor_err('plan_in_use'); end if;
  update public.motor_customers set plan_id = null where plan_id = p_id;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  select sid, 'plan', x.id, x.name, to_jsonb(x), w->>'name' from public.motor_plans x where x.id = p_id and x.site_id = sid;
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
  if not coalesce((w->>'is_main')::boolean,false) and ((coalesce(d->>'role','collector') = 'admin' and coalesce(d->>'id','') <> coalesce(w->>'staff_id',''))
       or exists (select 1 from public.motor_staff x where x.id::text = coalesce(d->>'id','') and x.role = 'admin' and x.id::text <> coalesce(w->>'staff_id',''))) then
    perform public._motor_err('main_only');
  end if;
  if nullif(d->>'read_from','') is not null and nullif(d->>'read_to','') is not null
     and (d->>'read_from')::date > (d->>'read_to')::date then perform public._motor_err('bad_window'); end if;
  if coalesce(d->>'id','') = '' then
    if length(coalesce(p_password,'')) < 4 then perform public._motor_err('short_password'); end if;
    insert into public.motor_staff (site_id, name, username, phone, role, is_active, read_from, read_to, can_collect, can_read, can_cut)
    values (sid, trim(d->>'name'), u, coalesce(d->>'phone',''), coalesce(d->>'role','collector'),
            coalesce((d->>'is_active')::boolean,true), nullif(d->>'read_from','')::date, nullif(d->>'read_to','')::date,
            coalesce((d->>'can_collect')::boolean,true), coalesce((d->>'can_read')::boolean,true), coalesce((d->>'can_cut')::boolean,false))
    returning * into s;
    update public.motor_staff set salary = coalesce(nullif(d->>'salary','')::numeric, 0) where id = s.id returning * into s;
  else
    -- الموظف ما بيقدر يشيل صلاحية المدير عن حالو
    if (d->>'id') = w->>'staff_id' and coalesce(d->>'role','collector') <> 'admin' then perform public._motor_err('self_demote'); end if;
    if (d->>'id') = w->>'staff_id' and not coalesce((d->>'is_active')::boolean,true) then perform public._motor_err('self_demote'); end if;
    update public.motor_staff set name = trim(d->>'name'), username = u, phone = coalesce(d->>'phone',''),
           role = coalesce(d->>'role','collector'), is_active = coalesce((d->>'is_active')::boolean,true),
           read_from = nullif(d->>'read_from','')::date, read_to = nullif(d->>'read_to','')::date,
           can_collect = coalesce((d->>'can_collect')::boolean,true),
           can_read = coalesce((d->>'can_read')::boolean,true), can_cut = coalesce((d->>'can_cut')::boolean,false),
           salary = coalesce(nullif(d->>'salary','')::numeric, salary)
     where id = (d->>'id')::uuid and site_id = sid returning * into s;
    -- المدير الأساسي يضل مدير ومفعّل
    if s.is_main and (s.role <> 'admin' or not s.is_active) then perform public._motor_err('self_demote'); end if;
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
  if exists (select 1 from public.motor_staff where id = p_id and (is_main or (role = 'admin' and not coalesce((w->>'is_main')::boolean,false)))) then
    perform public._motor_err('main_only');
  end if;
  if exists (select 1 from public.motor_payments where staff_id = p_id)
     or exists (select 1 from public.motor_readings where staff_id = p_id)
     or exists (select 1 from public.motor_moves where staff_id = p_id) then
    -- عندو حركات: منوقّفو بدل الحذف حتى يضل كشف حسابو
    update public.motor_staff set is_active = false where id = p_id and site_id = sid;
    delete from public.motor_sessions where staff_id = p_id;
    return jsonb_build_object('ok', true, 'deactivated', true);
  end if;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  select sid, 'staff', x.id, x.name || ' (' || x.username || ')', to_jsonb(x), w->>'name' from public.motor_staff x where x.id = p_id and x.site_id = sid;
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
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'customer',c.name,'code',c.code,'customer_id',c.id,
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
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'customer',c.name,'code',c.code,'customer_id',c.id,
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
  if exists (select 1 from public.motor_moves m join public.motor_day_closes dc on dc.site_id = m.site_id
              and dc.day = (m.created_at at time zone 'Asia/Beirut')::date where m.id = p_id) then
    perform public._motor_err('day_closed');
  end if;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  select m.site_id, 'move', m.id, m.account || ' / ' || m.kind || ' — ' || m.amount, to_jsonb(m), w->>'name'
    from public.motor_moves m where m.id = p_id and m.site_id = (w->>'site_id')::uuid;
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
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'customer',c.name,'code',c.code,'customer_id',c.id,
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
  if not coalesce((w->>'is_main')::boolean, false) then perform public._motor_err('forbidden'); end if;
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
  -- نفس المفتاح إذا ضغط «تفعيل» أكثر من مرة (حتى ما يصير الـQR الممسوح قديم)
  select totp_pending into sec from public.motor_staff_secrets where staff_id = (w->>'staff_id')::uuid;
  if coalesce(sec,'') = '' then
    sec := public._motor_b32_encode(gen_random_bytes(20));
    update public.motor_staff_secrets set totp_pending = sec where staff_id = (w->>'staff_id')::uuid;
  end if;
  select * into st from public.motor_sites where id = (w->>'site_id')::uuid;
  select username into u from public.motor_staff where id = (w->>'staff_id')::uuid;
  -- الرابط بأحرف إنكليزية فقط (الأحرف العربية كانت تخرب الـQR)
  return jsonb_build_object('secret', sec,
    'uri', 'otpauth://totp/LibanApps%20Motor:' || st.slug || '-' || regexp_replace(u, '[^a-z0-9._-]', '', 'g') ||
           '?secret=' || sec || '&issuer=LibanApps%20Motor&algorithm=SHA1&digits=6&period=30');
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
    if exists (select 1 from public.motor_staff where id = p_staff and role = 'admin') and not coalesce((w->>'is_main')::boolean,false) then
      perform public._motor_err('main_only');
    end if;
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
-- الفواتير المتراكمة حسب كشف الحساب: الدفعات تسدّد الأقدم أولاً، فالباقي = أحدث الفواتير لحد ما يكمل الرصيد
create or replace function public._motor_due_info(p_cust uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare bal numeric; acc numeric := 0; r record; per text[] := '{}'; n int := 0; rest numeric;
begin
  select balance into bal from public.motor_customers where id = p_cust;
  bal := coalesce(bal, 0);
  if bal > 0 then
    for r in select period, amount from public.motor_invoices where customer_id = p_cust and not voided and amount > 0
               and kind in ('meter','fixed') and period <> ''
              order by created_at desc loop
      exit when acc >= bal - 0.005;
      acc := acc + r.amount; n := n + 1;
      if not (r.period = any(per)) then per := r.period || per; end if;
    end loop;
  end if;
  rest := greatest(bal - acc, 0);
  return jsonb_build_object('balance', bal, 'count', n, 'periods', to_jsonb(per), 'older', rest > 0.005);
end $$;
revoke all on function public._motor_due_info(uuid) from public, anon, authenticated;

create or replace function public.motor_wa_outbox(p_slug text, p_token text, p_days integer default 60)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return coalesce((select jsonb_agg(x order by x->>'at') from (
      select jsonb_build_object('t','inv','id',i.id,'at',i.created_at,'inv',to_jsonb(i) - 'site_id',
             'due', public._motor_due_info(c.id),
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
    'customers_active', (select count(*) from public.motor_customers where site_id = sid and is_active and not archived and deleted_at is null),
    'customers_total', (select count(*) from public.motor_customers where site_id = sid and deleted_at is null),
    'read_period', (select count(*) from public.motor_readings where site_id = sid and period = st.bill_period
                     and (not mine or staff_id = me)),
    'billed_period', coalesce((select sum(amount) from public.motor_invoices where site_id = sid and period = st.bill_period
                     and kind in ('meter','fixed') and not voided and (not mine or staff_id = me)), 0),
    'unpaid_count', (select count(*) from public.motor_customers where site_id = sid and balance > 0 and not archived and deleted_at is null),
    'debt_total', case when mine then null else coalesce((select sum(balance) from public.motor_customers
                     where site_id = sid and balance > 0 and deleted_at is null), 0) end,
    'trash_count', case when mine then null else (select count(*) from public.motor_trash where site_id = sid) end,
    'cash_box', case when mine then null else public._motor_cash_bal(sid, null) end,
    'whish_box', case when mine then null else
                   coalesce((select sum(amount) from public.motor_payments where site_id = sid and method = 'whish' and not voided), 0)
                 + coalesce((select sum(case when kind = 'withdraw' then -abs(amount) else amount end) from public.motor_moves
                              where site_id = sid and account = 'whish'), 0) end,
    'wa_inv', case when mine then null else
        (select count(*) from public.motor_invoices i where i.site_id = sid and not i.voided and i.kind in ('meter','fixed')
            and i.wa_sent_at is null and i.created_at > now() - interval '60 days') end,
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
--  20b) تعديل قراءة العداد (المدير فقط — بلا صورة ولا موقع) + حساب دخول الزبون + صفحة الزبون
-- ============================================================
create or replace function public.motor_reading_edit(p_slug text, p_token text, p_reading uuid, p_value numeric, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; r public.motor_readings%rowtype; i public.motor_invoices%rowtype; st public.motor_sites%rowtype;
        v_kwh numeric; v_energy numeric; amt numeric; delta numeric;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  select * into r from public.motor_readings where id = p_reading and site_id = sid for update;
  if not found then perform public._motor_err('not_found'); end if;
  if exists (select 1 from public.motor_readings x where x.customer_id = r.customer_id and x.created_at > r.created_at) then
    perform public._motor_err('not_latest');
  end if;
  if p_value is null or p_value < r.prev_value then perform public._motor_err('lower_than_prev', r.prev_value::text); end if;
  update public.motor_readings set value = p_value where id = r.id;
  select * into i from public.motor_invoices where reading_id = r.id and not voided for update;
  if found then
    v_kwh := p_value - coalesce(i.prev_value, r.prev_value);
    v_energy := case when i.kind = 'meter' then round(v_kwh * i.kwh_price, 2) else 0 end;
    amt := public._motor_round(sid, i.fee + v_energy - i.discount + i.addition);
    delta := amt - i.amount;
    update public.motor_invoices set cur_value = p_value, kwh = v_kwh, energy = v_energy, amount = amt,
           balance_after = balance_after + delta,
           note = trim(both ' ' from note || case when coalesce(p_note,'') <> '' then ' ' || p_note else '' end || ' (عُدّلت القراءة بواسطة ' || (w->>'name') || ')')
     where id = i.id;
    update public.motor_customers set balance = balance + delta, updated_at = now() where id = r.customer_id;
  else
    update public.motor_customers set updated_at = now() where id = r.customer_id;
  end if;
  return jsonb_build_object('ok', true, 'delta', coalesce(delta, 0));
end $$;

-- اسم مستخدم وكلمة مرور للزبون (فاضي = إلغاء الدخول)
create or replace function public.motor_customer_set_login(p_slug text, p_token text, p_customer uuid, p_username text, p_password text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; u text := lower(trim(coalesce(p_username,'')));
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not exists (select 1 from public.motor_customers where id = p_customer and site_id = sid) then perform public._motor_err('customer_not_found'); end if;
  if u = '' then
    update public.motor_customers set username = '' where id = p_customer;
    delete from public.motor_customer_secrets where customer_id = p_customer;
    delete from public.motor_csessions where customer_id = p_customer;
    return jsonb_build_object('ok', true, 'removed', true);
  end if;
  if u !~ '^[a-z0-9._-]{2,30}$' then perform public._motor_err('bad_username'); end if;
  if exists (select 1 from public.motor_staff where site_id = sid and lower(username) = u)
     or exists (select 1 from public.motor_customers where site_id = sid and lower(username) = u and id <> p_customer) then
    perform public._motor_err('username_taken');
  end if;
  if not exists (select 1 from public.motor_customer_secrets where customer_id = p_customer) and length(coalesce(p_password,'')) < 4 then
    perform public._motor_err('short_password');
  end if;
  if length(coalesce(p_password,'')) between 1 and 3 then perform public._motor_err('short_password'); end if;
  update public.motor_customers set username = u where id = p_customer;
  if length(coalesce(p_password,'')) >= 4 then
    insert into public.motor_customer_secrets (customer_id, password_hash) values (p_customer, public._motor_hash(p_password))
    on conflict (customer_id) do update set password_hash = excluded.password_hash, failed_count = 0, locked_until = null, updated_at = now();
    delete from public.motor_csessions where customer_id = p_customer;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- صفحة الزبون: رصيده وفواتيره وكشف حسابه (للقراءة فقط)
create or replace function public.motor_cust_me(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare st public.motor_sites%rowtype; cid uuid; c public.motor_customers%rowtype; lic jsonb;
begin
  select * into st from public.motor_sites where slug = lower(trim(coalesce(p_slug,'')));
  if not found then perform public._motor_err('not_found'); end if;
  select s.customer_id into cid from public.motor_csessions s
   where s.token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex') and s.expires_at > now() and s.site_id = st.id;
  if cid is null then perform public._motor_err('auth'); end if;
  lic := public.motor_license(st.id);
  if not st.is_active or not coalesce((lic->>'ok')::boolean,false) then perform public._motor_err('license'); end if;
  select * into c from public.motor_customers where id = cid;
  return jsonb_build_object(
    'site', jsonb_build_object('name', st.name, 'logo_url', st.logo_url, 'tagline', st.tagline, 'phone', st.phone, 'whatsapp', st.whatsapp,
             'currency', st.currency, 'lbp_rate', st.lbp_rate, 'show_second', st.show_second, 'cur_label', st.cur_label,
             'whish_qr_url', st.whish_qr_url, 'whish_phone', st.whish_phone, 'bill_period', st.bill_period, 'default_lang', st.default_lang,
             'invoice_note', st.invoice_note),
    'customer', jsonb_build_object('id', c.id, 'code', c.code, 'name', c.name, 'barcode', c.barcode, 'meter_no', c.meter_no,
             'box', c.box, 'balance', c.balance, 'is_active', c.is_active, 'mobile', c.mobile, 'mobile_cc', c.mobile_cc,
             'plan_name', (select name from public.motor_plans where id = c.plan_id)),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
        select jsonb_build_object('t','inv','id',i.id,'no',i.no,'at',i.created_at,'created_at',i.created_at,'kind',i.kind,'period',i.period,
               'prev_value',i.prev_value,'cur_value',i.cur_value,'kwh',i.kwh,'kwh_price',i.kwh_price,'fee',i.fee,
               'energy',i.energy,'discount',i.discount,'addition',i.addition,'amount',i.amount,'debit',i.amount,'credit',0,
               'balance_before',i.balance_before,'balance_after',i.balance_after,'note',i.note,
               'photo', (select r.photo_url from public.motor_readings r where r.id = i.reading_id)) as x
          from public.motor_invoices i where i.customer_id = c.id and not i.voided
        union all
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'created_at',p.created_at,'method',p.method,
               'paid_currency',p.paid_currency,'paid_amount',p.paid_amount,'amount',p.amount,'debit',0,'credit',p.amount,
               'balance_before',p.balance_before,'balance_after',p.balance_after,'staff_name',p.staff_name)
          from public.motor_payments p where p.customer_id = c.id and not p.voided
      ) q), '[]'::jsonb));
end $$;

-- ============================================================
--  20c) تعديلات المدير: الفاتورة والدفعة، الباركود، الكشف الشهري العام، النسخة الاحتياطية
-- ============================================================
create or replace function public.motor_invoice_edit(p_slug text, p_token text, p_id uuid, p_amount numeric, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; i public.motor_invoices%rowtype; delta numeric;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into i from public.motor_invoices where id = p_id and site_id = sid for update;
  if not found or i.voided then perform public._motor_err('not_found'); end if;
  if p_amount is null then perform public._motor_err('bad_amount'); end if;
  delta := p_amount - i.amount;
  update public.motor_invoices set amount = p_amount, balance_after = balance_after + delta,
         note = trim(both ' ' from coalesce(p_note, note) || case when delta <> 0 then ' (عدّلها ' || (w->>'name') || ')' else '' end)
   where id = i.id;
  update public.motor_customers set balance = balance + delta, updated_at = now() where id = i.customer_id;
  return jsonb_build_object('ok', true, 'delta', delta);
end $$;

create or replace function public.motor_payment_edit(p_slug text, p_token text, p_id uuid, p_paid numeric, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; p public.motor_payments%rowtype; st public.motor_sites%rowtype; amt numeric; delta numeric;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  select * into p from public.motor_payments where id = p_id and site_id = sid for update;
  if not found or p.voided then perform public._motor_err('not_found'); end if;
  if coalesce(p_paid,0) <= 0 then perform public._motor_err('bad_amount'); end if;
  if p.method = 'cash' and p.created_at <= coalesce((select max(created_at) from public.motor_moves
        where site_id = sid and account = 'cash' and kind = 'close'), '-infinity'::timestamptz) then
    perform public._motor_err('closed_period');
  end if;
  if exists (select 1 from public.motor_day_closes where site_id = sid and day = (p.created_at at time zone 'Asia/Beirut')::date) then
    perform public._motor_err('day_closed');
  end if;
  if p.paid_currency = st.currency then amt := p_paid;
  elsif p.paid_currency = 'LBP' then amt := round(p_paid / nullif(p.rate,0), 2);
  else amt := round(p_paid * p.rate, 0); end if;
  delta := amt - p.amount;
  update public.motor_payments set paid_amount = p_paid, amount = amt, balance_after = balance_after - delta,
         note = trim(both ' ' from coalesce(p_note, note) || case when delta <> 0 then ' (عدّلها ' || (w->>'name') || ')' else '' end)
   where id = p.id;
  update public.motor_customers set balance = balance - delta, updated_at = now() where id = p.customer_id;
  return jsonb_build_object('ok', true, 'delta', delta);
end $$;

-- باركود لكل زبون ما عندو (البادئة + رقم الزبون)
create or replace function public.motor_fill_barcodes(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; pre text; n int := 0; r record; code text;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select barcode_prefix into pre from public.motor_sites where id = sid;
  for r in select id, code from public.motor_customers where site_id = sid and barcode = '' order by code loop
    code := pre || '-' || lpad(r.code::text, 5, '0');
    while exists (select 1 from public.motor_customers where site_id = sid and lower(barcode) = lower(code)) loop
      code := code || 'X';
    end loop;
    update public.motor_customers set barcode = code, updated_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'count', n);
end $$;

-- كشف شهري عام: سطر لكل زبون للشهر المختار
create or replace function public.motor_month_report(p_slug text, p_token text, p_period text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; per text; f timestamptz; t timestamptz;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  per := coalesce(nullif(p_period,''), (select bill_period from public.motor_sites where id = sid));
  if per !~ '^\d{4}-\d{2}$' then perform public._motor_err('bad_period'); end if;
  f := (per || '-01')::timestamp at time zone 'Asia/Beirut';
  t := ((per || '-01')::date + interval '1 month')::timestamp at time zone 'Asia/Beirut';
  return jsonb_build_object('period', per, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'code', c.code, 'name', c.name, 'barcode', c.barcode, 'box', c.box, 'area', c.area,
      'plan', pl.name, 'collector', coalesce(sf.name, c.collector_name), 'is_active', c.is_active,
      'prev_value', r.prev_value, 'cur_value', r.value, 'kwh', case when r.id is null then null else r.value - r.prev_value end,
      'invoiced', coalesce((select sum(i.amount) from public.motor_invoices i where i.customer_id = c.id and not i.voided
                             and i.kind in ('meter','fixed') and i.period = per), 0),
      -- المقبوض بالشهر: إيصالات هالبرنامج + إيصالات البرنامج السابق (مستوردة من كشف الحساب) بتاريخها
      'paid', coalesce((select sum(p.amount) from public.motor_payments p where p.customer_id = c.id and not p.voided
                         and p.created_at >= f and p.created_at < t), 0)
            - coalesce((select sum(i.amount) from public.motor_invoices i where i.customer_id = c.id and not i.voided
                         and i.imported and i.kind = 'adjust' and i.amount < 0 and i.note like 'ايصال%' and i.period = per), 0),
      'paid_whish', coalesce((select sum(p.amount) from public.motor_payments p where p.customer_id = c.id and not p.voided
                         and p.method = 'whish' and p.created_at >= f and p.created_at < t), 0)
            - coalesce((select sum(i.amount) from public.motor_invoices i where i.customer_id = c.id and not i.voided
                         and i.imported and i.kind = 'adjust' and i.amount < 0 and i.note like 'ايصال%' and i.period = per
                         and (i.note ilike '%whish%' or i.note like '%ويش%')), 0),
      -- الرصيد آخر الشهر: الفاتورة بتنحسب بشهرها (period) مش بتاريخ إدخالها — مهم للفواتير المستوردة
      'balance_end', coalesce((select sum(i.amount) from public.motor_invoices i where i.customer_id = c.id and not i.voided
                     and (case when i.period <> '' then i.period else to_char(i.created_at at time zone 'Asia/Beirut','YYYY-MM') end) <= per), 0)
          - coalesce((select sum(p.amount) from public.motor_payments p where p.customer_id = c.id and not p.voided and p.created_at < t), 0),
      'other', coalesce((select sum(i.amount) from public.motor_invoices i where i.customer_id = c.id and not i.voided and i.kind not in ('meter','fixed')
                     and not (i.imported and i.kind = 'adjust' and i.amount < 0 and i.note like 'ايصال%')
                     and (case when i.period <> '' then i.period else to_char(i.created_at at time zone 'Asia/Beirut','YYYY-MM') end) = per), 0),
      'balance_start', coalesce((select sum(i.amount) from public.motor_invoices i where i.customer_id = c.id and not i.voided
                     and (case when i.period <> '' then i.period else to_char(i.created_at at time zone 'Asia/Beirut','YYYY-MM') end) < per), 0)
          - coalesce((select sum(p.amount) from public.motor_payments p where p.customer_id = c.id and not p.voided and p.created_at < f), 0),
      'balance_now', c.balance) order by c.code)
    from public.motor_customers c
    left join public.motor_plans pl on pl.id = c.plan_id
    left join public.motor_staff sf on sf.id = c.collector_id
    left join public.motor_readings r on r.customer_id = c.id and r.period = per
    where c.site_id = sid and not c.archived and c.deleted_at is null), '[]'::jsonb));
end $$;


-- نسخة احتياطية كاملة (تُنزَّل كملف Excel عند الخروج)
create or replace function public.motor_backup(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return jsonb_build_object(
    'at', now(),
    'site', (select to_jsonb(s) - 'client_id' from public.motor_sites s where s.id = sid),
    'plans', coalesce((select jsonb_agg(to_jsonb(x) - 'site_id') from public.motor_plans x where x.site_id = sid), '[]'),
    'staff', coalesce((select jsonb_agg(jsonb_build_object('name', x.name, 'username', x.username, 'role', x.role, 'phone', x.phone,
               'can_read', x.can_read, 'can_collect', x.can_collect, 'can_cut', x.can_cut, 'is_active', x.is_active))
               from public.motor_staff x where x.site_id = sid), '[]'),
    'customers', coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.code) from public.motor_customers x where x.site_id = sid), '[]'),
    'readings', coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.created_at) from public.motor_readings x where x.site_id = sid), '[]'),
    'invoices', coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.created_at) from public.motor_invoices x where x.site_id = sid), '[]'),
    'payments', coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.created_at) from public.motor_payments x where x.site_id = sid), '[]'),
    'moves', coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.created_at) from public.motor_moves x where x.site_id = sid), '[]'));
end $$;

-- ============================================================
--  20d) سلة المحذوفات (المدير): إرجاع أو حذف نهائي
-- ============================================================
create or replace function public.motor_trash_list(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'kind', t.kind, 'label', t.label, 'by', t.deleted_by,
           'at', t.deleted_at, 'amount', t.data->'amount') order by t.deleted_at desc)
         from public.motor_trash t where t.site_id = (w->>'site_id')::uuid), '[]'::jsonb);
end $$;

create or replace function public.motor_trash_restore(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; tr public.motor_trash%rowtype; i public.motor_invoices%rowtype; p public.motor_payments%rowtype;
        r public.motor_readings%rowtype; nid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into tr from public.motor_trash where id = p_id and site_id = sid for update;
  if not found then perform public._motor_err('not_found'); end if;
  if tr.kind = 'customer' then
    update public.motor_customers set deleted_at = null, updated_at = now() where id = tr.ref_id and site_id = sid;
  elsif tr.kind = 'invoice' then
    select * into i from public.motor_invoices where id = tr.ref_id and site_id = sid for update;
    if found and i.voided then
      if i.voided_reading is not null then
        r := jsonb_populate_record(null::public.motor_readings, i.voided_reading);
        if exists (select 1 from public.motor_readings where customer_id = r.customer_id and period = r.period) then
          perform public._motor_err('already_read', r.period);
        end if;
        insert into public.motor_readings values (r.*) returning id into nid;
      end if;
      update public.motor_invoices set voided = false, voided_at = null, voided_by = '', reading_id = nid, voided_reading = null where id = i.id;
      update public.motor_customers set balance = balance + i.amount, updated_at = now() where id = i.customer_id;
    end if;
  elsif tr.kind = 'payment' then
    select * into p from public.motor_payments where id = tr.ref_id and site_id = sid for update;
    if found and p.voided then
      update public.motor_payments set voided = false, voided_at = null, voided_by = '' where id = p.id;
      update public.motor_customers set balance = balance - p.amount, updated_at = now() where id = p.customer_id;
    end if;
  elsif tr.kind = 'move' then
    insert into public.motor_moves select (jsonb_populate_record(null::public.motor_moves, tr.data)).*;
  elsif tr.kind = 'plan' then
    insert into public.motor_plans select (jsonb_populate_record(null::public.motor_plans, tr.data)).*;
  elsif tr.kind = 'staff' then
    insert into public.motor_staff select (jsonb_populate_record(null::public.motor_staff, tr.data)).*;
  elsif tr.kind = 'insurance' then
    insert into public.motor_insurance select (jsonb_populate_record(null::public.motor_insurance, tr.data)).*;
    update public.motor_insurance set move_id = null where id = tr.ref_id;
  elsif tr.kind = 'stock' then
    insert into public.motor_stock select (jsonb_populate_record(null::public.motor_stock, tr.data)).*;
  end if;
  delete from public.motor_trash where id = tr.id;
  return jsonb_build_object('ok', true, 'kind', tr.kind);
end $$;

-- حذف نهائي (p_id فاضي = إفراغ السلة كلها)
create or replace function public.motor_trash_purge(p_slug text, p_token text, p_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; tr record; n int := 0;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  for tr in select * from public.motor_trash where site_id = sid and (p_id is null or id = p_id) loop
    if tr.kind = 'customer' then
      delete from public.motor_customers where id = tr.ref_id and site_id = sid and deleted_at is not null;
    elsif tr.kind = 'invoice' then
      delete from public.motor_invoices where id = tr.ref_id and site_id = sid and voided;
    elsif tr.kind = 'payment' then
      delete from public.motor_payments where id = tr.ref_id and site_id = sid and voided;
    end if;
    delete from public.motor_trash where id = tr.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'count', n);
end $$;

-- ============================================================
--  20e) المدير يغيّر «العداد السابق» من جدول الزبائن
--       · إذا انقرى العداد هالدورة: بتتصحّح القراءة والفاتورة والرصيد
--       · وإلا: بينحفظ للقراءة الجاية (الاستهلاك = الحالي − هالقيمة)
-- ============================================================
create or replace function public._motor_set_prev(sid uuid, p_customer uuid, p_value numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare st public.motor_sites%rowtype; c public.motor_customers%rowtype; r public.motor_readings%rowtype;
        i public.motor_invoices%rowtype; v_kwh numeric; v_energy numeric; amt numeric; delta numeric := 0;
begin
  if p_value is null or p_value < 0 then perform public._motor_err('bad_value'); end if;
  select * into st from public.motor_sites where id = sid;
  select * into c from public.motor_customers where id = p_customer and site_id = sid and deleted_at is null for update;
  if not found then perform public._motor_err('customer_not_found'); end if;
  select * into r from public.motor_readings where customer_id = c.id and period = st.bill_period for update;
  if found then
    if r.value < p_value then perform public._motor_err('prev_above_cur', r.value::text); end if;
    update public.motor_readings set prev_value = p_value where id = r.id;
    select * into i from public.motor_invoices where reading_id = r.id and not voided for update;
    if found then
      v_kwh := r.value - p_value;
      v_energy := case when i.kind = 'meter' then round(v_kwh * i.kwh_price, 2) else 0 end;
      amt := public._motor_round(sid, i.fee + v_energy - i.discount + i.addition);
      delta := amt - i.amount;
      update public.motor_invoices set prev_value = p_value, kwh = v_kwh, energy = v_energy, amount = amt,
             balance_after = balance_after + delta where id = i.id;
    end if;
    update public.motor_customers set balance = balance + delta, updated_at = now() where id = c.id;
    return jsonb_build_object('ok', true, 'mode', 'current', 'delta', delta);
  end if;
  if not exists (select 1 from public.motor_readings where customer_id = c.id) then
    update public.motor_customers set initial_reading = p_value, next_prev = p_value, updated_at = now() where id = c.id;
  else
    update public.motor_customers set next_prev = p_value, updated_at = now() where id = c.id;
  end if;
  return jsonb_build_object('ok', true, 'mode', 'next');
end $$;
revoke all on function public._motor_set_prev(uuid, uuid, numeric) from public, anon, authenticated;

create or replace function public.motor_set_prev(p_slug text, p_token text, p_customer uuid, p_value numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  return public._motor_set_prev((w->>'site_id')::uuid, p_customer, p_value);
end $$;

-- إدخال العداد السابق دفعة وحدة (من ملف PDF): p_rows = [{id, value}]
create or replace function public.motor_set_prev_bulk(p_slug text, p_token text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; r jsonb; ok int := 0; errs jsonb := '[]'::jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 3000 then perform public._motor_err('bad_data'); end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    begin
      perform public._motor_set_prev(sid, (r->>'id')::uuid, (r->>'value')::numeric);
      ok := ok + 1;
    exception when others then
      errs := errs || jsonb_build_object('id', r->>'id', 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('ok', true, 'done', ok, 'errors', errs);
end $$;

-- ============================================================
--  20f) فك قفل الجهاز (المدير الأساسي فقط)
-- ============================================================
create or replace function public.motor_device_reset(p_slug text, p_token text, p_staff uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not coalesce((w->>'is_main')::boolean,false) then perform public._motor_err('main_only'); end if;
  update public.motor_staff set device_id = null, device_label = '', device_at = null where id = p_staff and site_id = sid;
  delete from public.motor_sessions where staff_id = p_staff;
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  20f2) المدير الأساسي بيفوت على حساب أي موظف من جهازو (بلا كلمة سر وبلا قفل جهاز)
-- ============================================================
create or replace function public.motor_impersonate(p_slug text, p_token text, p_staff uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sf public.motor_staff%rowtype; tok text;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not coalesce((w->>'is_main')::boolean,false) then perform public._motor_err('main_only'); end if;
  select * into sf from public.motor_staff where id = p_staff and site_id = sid;
  if not found then perform public._motor_err('bad_staff'); end if;
  if sf.id::text = w->>'staff_id' then perform public._motor_err('bad_staff'); end if;
  if not sf.is_active then perform public._motor_err('inactive_user'); end if;
  tok := encode(gen_random_bytes(24),'hex');
  insert into public.motor_sessions (token_hash, staff_id, site_id, expires_at, impersonated_by)
  values (encode(digest(tok,'sha256'),'hex'), sf.id, sid, now() + interval '12 hours', w->>'name');
  return jsonb_build_object('ok', true, 'token', tok, 'name', sf.name, 'role', sf.role);
end $$;

-- ============================================================
--  20g) المصاريف والمعاشات = سند صرف ينقص من الصندوق أو Whish
-- ============================================================
create or replace function public._motor_whish_bal(p_sid uuid, p_before timestamptz default null)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select sum(amount) from public.motor_payments where site_id = p_sid and method = 'whish' and not voided
                     and (p_before is null or created_at < p_before)), 0)
       + coalesce((select sum(case when kind = 'withdraw' then -abs(amount) else amount end) from public.motor_moves
                     where site_id = p_sid and account = 'whish' and (p_before is null or created_at < p_before)), 0);
$$;
revoke all on function public._motor_whish_bal(uuid, timestamptz) from public, anon, authenticated;

create or replace function public._motor_voucher(p_sid uuid, p_w jsonb, p_account text, p_amount numeric, p_category text,
  p_note text, p_type text, p_staff uuid, p_period text)
returns public.motor_moves language plpgsql security definer set search_path = public as $$
declare seq int; m public.motor_moves%rowtype;
begin
  if p_account not in ('cash','whish') then perform public._motor_err('bad_account'); end if;
  if coalesce(p_amount,0) <= 0 then perform public._motor_err('bad_amount'); end if;
  update public.motor_sites set voucher_seq = voucher_seq + 1 where id = p_sid returning voucher_seq into seq;
  insert into public.motor_moves (site_id, account, kind, amount, note, by_name, category, vno, pay_staff, period, extra)
  values (p_sid, p_account, case when p_account = 'cash' then 'out' else 'withdraw' end, abs(p_amount), coalesce(p_note,''),
          p_w->>'name', coalesce(p_category,''), seq, p_staff, coalesce(p_period,''), jsonb_build_object('type', p_type))
  returning * into m;
  return m;
end $$;
revoke all on function public._motor_voucher(uuid, jsonb, text, numeric, text, text, text, uuid, text) from public, anon, authenticated;

create or replace function public.motor_expense_add(p_slug text, p_token text, p_account text, p_category text, p_amount numeric, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; m public.motor_moves%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  if coalesce(trim(p_category),'') = '' then perform public._motor_err('name_required'); end if;
  m := public._motor_voucher((w->>'site_id')::uuid, w, p_account, p_amount, trim(p_category), p_note, 'expense', null, '');
  return jsonb_build_object('ok', true, 'move', to_jsonb(m) - 'site_id');
end $$;

create or replace function public.motor_vouchers(p_slug text, p_token text, p_type text, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; f date; t date;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  f := coalesce(p_from, date '2000-01-01'); t := coalesce(p_to, date '2999-12-31');
  return coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'vno', m.vno, 'at', m.created_at, 'account', m.account,
           'amount', m.amount, 'category', m.category, 'note', m.note, 'by', m.by_name, 'period', m.period,
           'staff_id', m.pay_staff, 'staff', (select name from public.motor_staff where id = m.pay_staff)) order by m.created_at desc)
         from public.motor_moves m where m.site_id = sid and m.extra->>'type' = p_type
          and (m.created_at at time zone 'Asia/Beirut')::date between f and t), '[]'::jsonb);
end $$;

create or replace function public.motor_salary_pay(p_slug text, p_token text, p_staff uuid, p_amount numeric, p_account text,
  p_period text, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sf public.motor_staff%rowtype; m public.motor_moves%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into sf from public.motor_staff where id = p_staff and site_id = sid;
  if not found then perform public._motor_err('bad_staff'); end if;
  if coalesce(p_period,'') !~ '^\d{4}-\d{2}$' then perform public._motor_err('bad_period'); end if;
  m := public._motor_voucher(sid, w, p_account, p_amount, 'معاش ' || sf.name, p_note, 'salary', sf.id, p_period);
  return jsonb_build_object('ok', true, 'move', to_jsonb(m) - 'site_id');
end $$;

create or replace function public.motor_salaries(p_slug text, p_token text, p_period text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'role', s.role, 'is_active', s.is_active,
           'salary', s.salary,
           'due', (select sum(d.amount) from public.motor_salary_dues d where d.staff_id = s.id and d.period = p_period),
           'dues', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'amount', d.amount, 'note', d.note, 'at', d.created_at) order by d.created_at)
                    from public.motor_salary_dues d where d.staff_id = s.id and d.period = p_period), '[]'::jsonb),
           'balance', coalesce((select sum(d.amount) from public.motor_salary_dues d where d.staff_id = s.id), 0)
                    - coalesce((select sum(m.amount) from public.motor_moves m where m.pay_staff = s.id and m.extra->>'type' = 'salary'), 0),
           'paid', coalesce((select sum(m.amount) from public.motor_moves m where m.pay_staff = s.id and m.extra->>'type' = 'salary' and m.period = p_period), 0),
           'payments', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'vno', m.vno, 'at', m.created_at, 'amount', m.amount,
                          'account', m.account, 'note', m.note) order by m.created_at)
                        from public.motor_moves m where m.pay_staff = s.id and m.extra->>'type' = 'salary' and m.period = p_period), '[]'::jsonb))
           order by s.name)
         from public.motor_staff s where s.site_id = sid and (s.is_active or s.salary > 0)), '[]'::jsonb);
end $$;

-- ============================================================
--  20h) المخزون (الموجودات)
-- ============================================================
create or replace function public.motor_stock_list(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  return coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.category, x.name) from public.motor_stock x
                    where x.site_id = (w->>'site_id')::uuid), '[]'::jsonb);
end $$;

create or replace function public.motor_stock_save(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; d jsonb := coalesce(p_data,'{}'::jsonb); x public.motor_stock%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(trim(d->>'name'),'') = '' then perform public._motor_err('name_required'); end if;
  if coalesce(d->>'id','') = '' then
    insert into public.motor_stock (site_id, name, category, qty, unit_price, notes, updated_by)
    values (sid, trim(d->>'name'), coalesce(d->>'category',''), coalesce(nullif(d->>'qty','')::numeric,0),
            coalesce(nullif(d->>'unit_price','')::numeric,0), coalesce(d->>'notes',''), w->>'name')
    returning * into x;
    if x.qty <> 0 then
      insert into public.motor_stock_moves (site_id, item_id, item_name, kind, qty, unit_price, note, by_name)
      values (sid, x.id, x.name, 'adjust', x.qty, x.unit_price, 'رصيد أول', w->>'name');
    end if;
  else
    insert into public.motor_stock_moves (site_id, item_id, item_name, kind, qty, unit_price, note, by_name)
    select sid, o.id, trim(d->>'name'), 'adjust', coalesce(nullif(d->>'qty','')::numeric,0) - o.qty, o.unit_price, 'تعديل يدوي', w->>'name'
      from public.motor_stock o where o.id = (d->>'id')::uuid and o.site_id = sid and o.qty <> coalesce(nullif(d->>'qty','')::numeric,0);
    update public.motor_stock set name = trim(d->>'name'), category = coalesce(d->>'category',''),
           qty = coalesce(nullif(d->>'qty','')::numeric,0), unit_price = coalesce(nullif(d->>'unit_price','')::numeric,0),
           notes = coalesce(d->>'notes',''), updated_by = w->>'name', updated_at = now()
     where id = (d->>'id')::uuid and site_id = sid returning * into x;
    if x.id is null then perform public._motor_err('not_found'); end if;
  end if;
  return to_jsonb(x) - 'site_id';
end $$;

create or replace function public.motor_stock_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  select sid, 'stock', x.id, x.name || ' × ' || x.qty, to_jsonb(x), w->>'name' from public.motor_stock x where x.id = p_id and x.site_id = sid;
  delete from public.motor_stock where id = p_id and site_id = sid;
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  20h2) سحب من المخزون (لازم مين سحب) + سجل حركات المخزون
-- ============================================================
create or replace function public.motor_stock_out(p_slug text, p_token text, p_item uuid, p_qty numeric,
  p_staff uuid default null, p_taker text default '', p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; x public.motor_stock%rowtype; who text;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(p_qty,0) <= 0 then perform public._motor_err('bad_amount'); end if;
  select name into who from public.motor_staff where id = p_staff and site_id = sid;
  who := coalesce(nullif(trim(coalesce(who,'')),''), nullif(trim(coalesce(p_taker,'')),''));
  if who is null then perform public._motor_err('taker_required'); end if;
  select * into x from public.motor_stock where id = p_item and site_id = sid for update;
  if not found then perform public._motor_err('not_found'); end if;
  if x.qty < p_qty then perform public._motor_err('stock_low', x.qty::text); end if;
  update public.motor_stock set qty = qty - p_qty, updated_by = w->>'name', updated_at = now() where id = x.id returning * into x;
  insert into public.motor_stock_moves (site_id, item_id, item_name, kind, qty, unit_price, taker, staff_id, note, by_name)
  values (sid, x.id, x.name, 'out', -p_qty, x.unit_price, who, p_staff, coalesce(p_note,''), w->>'name');
  return to_jsonb(x) - 'site_id';
end $$;

create or replace function public.motor_stock_moves_list(p_slug text, p_token text, p_item uuid default null, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'at', m.created_at, 'item_id', m.item_id, 'item', m.item_name, 'kind', m.kind,
           'qty', m.qty, 'unit_price', m.unit_price, 'taker', m.taker, 'note', m.note, 'by', m.by_name,
           'purchase_no', (select p.no from public.motor_purchases p where p.id = m.purchase_id)) order by m.created_at desc)
         from public.motor_stock_moves m where m.site_id = sid and (p_item is null or m.item_id = p_item)
          and (m.created_at at time zone 'Asia/Beirut')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2999-12-31')), '[]'::jsonb);
end $$;

-- ============================================================
--  20h3) الموردون، فواتير المشتريات، الدفعات (سند صرف من الصندوق أو Whish)
-- ============================================================
create or replace function public._motor_sup_bal(p_sup uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select sum(total) from public.motor_purchases where supplier_id = p_sup and not voided), 0)
       - coalesce((select sum(amount) from public.motor_moves where supplier_id = p_sup and extra->>'type' = 'supplier'), 0);
$$;
revoke all on function public._motor_sup_bal(uuid) from public, anon, authenticated;

create or replace function public.motor_suppliers(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'phone', s.phone, 'notes', s.notes,
           'purchases', coalesce((select sum(total) from public.motor_purchases where supplier_id = s.id and not voided), 0),
           'paid', coalesce((select sum(amount) from public.motor_moves where supplier_id = s.id and extra->>'type' = 'supplier'), 0),
           'balance', public._motor_sup_bal(s.id),
           'count', (select count(*) from public.motor_purchases where supplier_id = s.id and not voided)) order by s.name)
         from public.motor_suppliers s where s.site_id = sid), '[]'::jsonb);
end $$;

create or replace function public.motor_supplier_save(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; d jsonb := coalesce(p_data,'{}'::jsonb); x public.motor_suppliers%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(trim(d->>'name'),'') = '' then perform public._motor_err('name_required'); end if;
  if coalesce(d->>'id','') = '' then
    insert into public.motor_suppliers (site_id, name, phone, notes) values (sid, trim(d->>'name'), coalesce(d->>'phone',''), coalesce(d->>'notes',''))
    returning * into x;
  else
    update public.motor_suppliers set name = trim(d->>'name'), phone = coalesce(d->>'phone',''), notes = coalesce(d->>'notes','')
     where id = (d->>'id')::uuid and site_id = sid returning * into x;
    if x.id is null then perform public._motor_err('not_found'); end if;
  end if;
  return to_jsonb(x) - 'site_id';
end $$;

create or replace function public.motor_supplier_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if exists (select 1 from public.motor_purchases where supplier_id = p_id and not voided)
     or exists (select 1 from public.motor_moves where supplier_id = p_id) then perform public._motor_err('has_history'); end if;
  delete from public.motor_purchases where supplier_id = p_id and site_id = sid;
  delete from public.motor_suppliers where id = p_id and site_id = sid;
  return jsonb_build_object('ok', true);
end $$;

-- فاتورة مشتريات: p_data = {supplier_id, ref, day, note, to_stock, items:[{item_id|name, category, qty, unit_price}], pay_amount, pay_account}
create or replace function public.motor_purchase_add(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; d jsonb := coalesce(p_data,'{}'::jsonb); sup public.motor_suppliers%rowtype; it jsonb; x public.motor_stock%rowtype;
        seq int; pid uuid; tot numeric := 0; items jsonb := '[]'::jsonb; q numeric; pr numeric; nm text; tostk boolean; m public.motor_moves%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into sup from public.motor_suppliers where id = (d->>'supplier_id')::uuid and site_id = sid;
  if not found then perform public._motor_err('not_found'); end if;
  if jsonb_typeof(d->'items') <> 'array' or jsonb_array_length(d->'items') = 0 then perform public._motor_err('no_items'); end if;
  tostk := coalesce((d->>'to_stock')::boolean, true);
  update public.motor_sites set purchase_seq = purchase_seq + 1 where id = sid returning purchase_seq into seq;
  pid := gen_random_uuid();
  for it in select * from jsonb_array_elements(d->'items') loop
    q := coalesce(nullif(it->>'qty','')::numeric, 0); pr := coalesce(nullif(it->>'unit_price','')::numeric, 0);
    nm := trim(coalesce(it->>'name',''));
    if q <= 0 then continue; end if;
    x := null;
    if coalesce(it->>'item_id','') <> '' then select * into x from public.motor_stock where id = (it->>'item_id')::uuid and site_id = sid; end if;
    if x.id is null and nm <> '' then select * into x from public.motor_stock where site_id = sid and lower(name) = lower(nm) limit 1; end if;
    if x.id is null and nm = '' then perform public._motor_err('name_required'); end if;
    if tostk then
      if x.id is null then
        insert into public.motor_stock (site_id, name, category, qty, unit_price, updated_by)
        values (sid, nm, coalesce(it->>'category',''), q, pr, w->>'name') returning * into x;
      else
        update public.motor_stock set qty = qty + q, unit_price = case when pr > 0 then pr else unit_price end,
               updated_by = w->>'name', updated_at = now() where id = x.id returning * into x;
      end if;
      insert into public.motor_stock_moves (site_id, item_id, item_name, kind, qty, unit_price, taker, purchase_id, note, by_name)
      values (sid, x.id, x.name, 'purchase', q, pr, sup.name, pid, coalesce(d->>'ref',''), w->>'name');
    end if;
    items := items || jsonb_build_array(jsonb_build_object('item_id', x.id, 'name', coalesce(x.name, nm), 'qty', q, 'unit_price', pr, 'total', round(q*pr, 2)));
    tot := tot + round(q*pr, 2);
  end loop;
  if jsonb_array_length(items) = 0 then perform public._motor_err('no_items'); end if;
  insert into public.motor_purchases (id, site_id, supplier_id, no, ref, day, items, total, to_stock, note, by_name)
  values (pid, sid, sup.id, seq, coalesce(d->>'ref',''), coalesce(nullif(d->>'day','')::date, public._motor_today()), items, tot, tostk,
          coalesce(d->>'note',''), w->>'name');
  if coalesce(nullif(d->>'pay_amount','')::numeric, 0) > 0 then
    m := public._motor_voucher(sid, w, coalesce(d->>'pay_account','cash'), (d->>'pay_amount')::numeric, 'دفعة للمورد ' || sup.name,
                               'فاتورة مشتريات #' || seq, 'supplier', null, '');
    update public.motor_moves set supplier_id = sup.id where id = m.id;
  end if;
  return jsonb_build_object('ok', true, 'no', seq, 'total', tot, 'vno', m.vno);
end $$;

create or replace function public.motor_purchase_void(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; pu public.motor_purchases%rowtype; mv record;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into pu from public.motor_purchases where id = p_id and site_id = sid and not voided for update;
  if not found then perform public._motor_err('not_found'); end if;
  for mv in select * from public.motor_stock_moves where purchase_id = pu.id and kind = 'purchase' loop
    update public.motor_stock set qty = qty - mv.qty, updated_by = w->>'name', updated_at = now() where id = mv.item_id;
    insert into public.motor_stock_moves (site_id, item_id, item_name, kind, qty, unit_price, taker, purchase_id, note, by_name)
    values (sid, mv.item_id, mv.item_name, 'void', -mv.qty, mv.unit_price, mv.taker, pu.id, 'إلغاء فاتورة مشتريات #' || pu.no, w->>'name');
  end loop;
  update public.motor_purchases set voided = true where id = pu.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.motor_supplier_pay(p_slug text, p_token text, p_supplier uuid, p_amount numeric, p_account text, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sup public.motor_suppliers%rowtype; m public.motor_moves%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into sup from public.motor_suppliers where id = p_supplier and site_id = sid;
  if not found then perform public._motor_err('not_found'); end if;
  m := public._motor_voucher(sid, w, p_account, p_amount, 'دفعة للمورد ' || sup.name, p_note, 'supplier', null, '');
  update public.motor_moves set supplier_id = sup.id where id = m.id returning * into m;
  return jsonb_build_object('ok', true, 'move', to_jsonb(m) - 'site_id', 'balance', public._motor_sup_bal(sup.id));
end $$;

create or replace function public.motor_supplier_statement(p_slug text, p_token text, p_supplier uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sup public.motor_suppliers%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into sup from public.motor_suppliers where id = p_supplier and site_id = sid;
  if not found then perform public._motor_err('not_found'); end if;
  return jsonb_build_object('supplier', to_jsonb(sup) - 'site_id', 'balance', public._motor_sup_bal(sup.id),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
       select jsonb_build_object('t','purchase','id',p.id,'at',p.created_at,'day',p.day,'no',p.no,'ref',p.ref,'items',p.items,'total',p.total,
              'to_stock',p.to_stock,'note',p.note,'by',p.by_name,'voided',p.voided) x from public.motor_purchases p where p.supplier_id = sup.id
       union all
       select jsonb_build_object('t','pay','id',m.id,'at',m.created_at,'vno',m.vno,'amount',m.amount,'account',m.account,'note',m.note,'by',m.by_name)
         from public.motor_moves m where m.supplier_id = sup.id and m.extra->>'type' = 'supplier') q), '[]'::jsonb));
end $$;

-- ============================================================
--  20h4) المعاشات: إضافة قيمة المعاش (استحقاق) + كشف حساب الموظف
-- ============================================================
create or replace function public.motor_staff_salary_set(p_slug text, p_token text, p_staff uuid, p_amount numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  if coalesce(p_amount,-1) < 0 then perform public._motor_err('bad_amount'); end if;
  update public.motor_staff set salary = p_amount where id = p_staff and site_id = (w->>'site_id')::uuid;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.motor_salary_due_add(p_slug text, p_token text, p_staff uuid, p_period text, p_amount numeric, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not exists (select 1 from public.motor_staff where id = p_staff and site_id = sid) then perform public._motor_err('bad_staff'); end if;
  if coalesce(p_period,'') !~ '^\d{4}-\d{2}$' then perform public._motor_err('bad_period'); end if;
  if coalesce(p_amount,0) = 0 then perform public._motor_err('bad_amount'); end if;
  insert into public.motor_salary_dues (site_id, staff_id, period, amount, note, by_name)
  values (sid, p_staff, p_period, p_amount, coalesce(p_note,''), w->>'name');
  return jsonb_build_object('ok', true);
end $$;

-- إضافة معاش الشهر لكل الموظفين اللي إلهم معاش ولسّا ما انضاف إلهم بهالشهر
create or replace function public.motor_salary_due_all(p_slug text, p_token text, p_period text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; n int;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(p_period,'') !~ '^\d{4}-\d{2}$' then perform public._motor_err('bad_period'); end if;
  insert into public.motor_salary_dues (site_id, staff_id, period, amount, note, by_name)
  select sid, s.id, p_period, s.salary, 'معاش ' || p_period, w->>'name' from public.motor_staff s
   where s.site_id = sid and s.is_active and s.salary > 0
     and not exists (select 1 from public.motor_salary_dues d where d.staff_id = s.id and d.period = p_period);
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'count', n);
end $$;

create or replace function public.motor_salary_due_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  delete from public.motor_salary_dues where id = p_id and site_id = (w->>'site_id')::uuid;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.motor_staff_statement(p_slug text, p_token text, p_staff uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sf public.motor_staff%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into sf from public.motor_staff where id = p_staff and site_id = sid;
  if not found then perform public._motor_err('bad_staff'); end if;
  return jsonb_build_object('staff', jsonb_build_object('id', sf.id, 'name', sf.name, 'salary', sf.salary, 'phone', sf.phone),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
       select jsonb_build_object('t','due','id',d.id,'at',d.created_at,'period',d.period,'amount',d.amount,'note',d.note,'by',d.by_name) x
         from public.motor_salary_dues d where d.staff_id = sf.id
       union all
       select jsonb_build_object('t','pay','id',m.id,'at',m.created_at,'period',m.period,'vno',m.vno,'amount',m.amount,'account',m.account,'note',m.note,'by',m.by_name)
         from public.motor_moves m where m.pay_staff = sf.id and m.extra->>'type' = 'salary') q), '[]'::jsonb));
end $$;

-- ============================================================
--  20j) استيراد فواتير البرنامج السابق (Excel): كل سطر = فاتورة
--  p_data = [{customer_id, area, balance, rows:[{date:'YYYY-MM-DD', prev, cur, total, plan}]}]
--  الشهر: تاريخ الفاتورة 1–14 = الشهر اللي قبل (02/06 → أيار)، 15 وما فوق = نفس الشهر (فاتورة نص شهر)
--  الرصيد بعد الاستيراد = «رصيد الحساب الحالي» بالملف بالضبط (الفرق بيروح على سطر الرصيد السابق)
-- ============================================================
-- «دفعات مسددة في البرنامج السابق»: منوزّعها شهر بشهر — كل فاتورة (من الأقدم) بتنسدّ بالشهر يلّي بعدها
-- هيك الكشف الشهري بيطلع رصيد كل شهر منطقي بدل ما ينجمعو كل الدفعات القديمة بآخر شهر
create or replace function public._motor_spread_old_payments(p_cust uuid)
returns void language plpgsql security definer set search_path = public as $$
declare cred numeric; r record; part numeric; tp text; maxp text; cap text; sid uuid; seq int; x record;
begin
  select coalesce(-sum(amount),0), (array_agg(site_id))[1] into cred, sid from public.motor_invoices
   where customer_id = p_cust and imported and kind = 'adjust' and not voided and amount < 0;
  if cred <= 0 then return; end if;
  delete from public.motor_invoices where customer_id = p_cust and imported and kind = 'adjust' and amount < 0;
  select max(period) into maxp from public.motor_invoices where customer_id = p_cust and imported and kind in ('meter','fixed');
  cap := to_char((now() at time zone 'Asia/Beirut')::date, 'YYYY-MM');
  create temp table if not exists _spread (per text, amt numeric) on commit drop; truncate _spread;
  for r in select i.kind, i.period, i.amount, i.created_at from public.motor_invoices i
            where i.customer_id = p_cust and not i.voided and i.amount > 0 and (i.kind = 'opening' or (i.imported and i.kind in ('meter','fixed')))
            order by (i.kind = 'opening') desc, i.period, i.created_at loop
    exit when cred <= 0.004;
    part := least(cred, r.amount);
    tp := case when r.kind = 'opening' or r.period = '' then
                 coalesce((select min(period) from public.motor_invoices where customer_id = p_cust and imported and kind in ('meter','fixed')), cap)
               else to_char((r.period || '-01')::date + interval '1 month', 'YYYY-MM') end;
    if tp > cap then tp := cap; end if;
    insert into _spread values (tp, part); cred := cred - part;
  end loop;
  if cred > 0.004 then insert into _spread values (least(coalesce(maxp, cap), cap), cred); end if;
  for x in select per, sum(amt) amt from _spread group by per order by per loop
    update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
    insert into public.motor_invoices (site_id, no, customer_id, period, kind, amount, note, staff_name, imported, wa_sent_at, created_at)
    values (sid, seq, p_cust, x.per, 'adjust', -x.amt, 'دفعات مسددة في البرنامج السابق', 'استيراد', true, now(),
            least(((x.per || '-01')::timestamp + interval '1 day') at time zone 'Asia/Beirut', now()));
  end loop;
end $$;
revoke all on function public._motor_spread_old_payments(uuid) from public, anon, authenticated;

create or replace function public.motor_import_invoices(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; cu jsonb; c public.motor_customers%rowtype;
        seq int; rid uuid; first_d date; bal numeric; op numeric;
        n_inv int := 0; n_read int := 0; n_skip int := 0; n_cust int := 0; n_bal int := 0; r record; run numeric;
        best jsonb; grp record; oid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if jsonb_typeof(p_data) <> 'array' then perform public._motor_err('bad_data'); end if;
  perform 1 from public.motor_sites where id = sid for update;
  for cu in select * from jsonb_array_elements(p_data) loop
    select * into c from public.motor_customers where id = (cu->>'customer_id')::uuid and site_id = sid and deleted_at is null for update;
    if not found then continue; end if;
    n_cust := n_cust + 1;
    -- إعادة الاستيراد: امسح يلّي انستورد قبل لهالزبون
    delete from public.motor_invoices where customer_id = c.id and imported;
    delete from public.motor_readings where customer_id = c.id and imported;
    first_d := null;
    -- كل سطر مع شهرو
    create temp table if not exists _imp (ord int, d date, per text, prevv numeric, curv numeric, tot numeric, plan text) on commit drop;
    truncate _imp;
    insert into _imp
    select x.ordinality, (x.value->>'date')::date,
           to_char(case when extract(day from (x.value->>'date')::date) >= 15 then (x.value->>'date')::date
                        else ((x.value->>'date')::date - interval '1 month')::date end, 'YYYY-MM'),
           nullif(x.value->>'prev','')::numeric, nullif(x.value->>'cur','')::numeric,
           coalesce(nullif(x.value->>'total','')::numeric, 0), coalesce(x.value->>'plan','')
      from jsonb_array_elements(cu->'rows') with ordinality x
     where coalesce(x.value->>'date','') ~ '^\d{4}-\d{2}-\d{2}$';
    -- شهر فيه قراءة حقيقية من البرنامج: ما منلمسو
    delete from _imp i where exists (select 1 from public.motor_readings rr where rr.customer_id = c.id and rr.period = i.per and not rr.imported);
    get diagnostics seq = row_count; n_skip := n_skip + seq;
    for grp in select per, max(d) md from _imp group by per loop
      rid := null;
      -- القراءة = آخر سطر بالشهر (إذا في عداد حالي)
      select * into r from _imp where per = grp.per order by d desc, ord desc limit 1;
      if r.curv is not null then
        insert into public.motor_readings (site_id, customer_id, period, prev_value, value, staff_name, imported, created_at)
        values (sid, c.id, grp.per, coalesce(r.prevv, 0), r.curv, 'استيراد', true, (r.d::timestamp + interval '12 hours') at time zone 'Asia/Beirut')
        returning id into rid;
        n_read := n_read + 1;
      end if;
      for r in select * from _imp where per = grp.per order by d, ord loop
        update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
        insert into public.motor_invoices (site_id, no, customer_id, period, kind, reading_id, plan_name, prev_value, cur_value, kwh,
               amount, note, staff_name, imported, wa_sent_at, created_at)
        values (sid, seq, c.id, r.per, case when r.curv is null then 'fixed' else 'meter' end,
                case when r.d = grp.md then rid end, r.plan,
                case when r.curv is not null then coalesce(r.prevv, 0) end, r.curv,
                case when r.curv is not null then greatest(r.curv - coalesce(r.prevv, 0), 0) else 0 end,
                r.tot, 'مستوردة من البرنامج السابق', 'استيراد', true, now(), (r.d::timestamp + interval '12 hours') at time zone 'Asia/Beirut');
        n_inv := n_inv + 1;
      end loop;
    end loop;
    select min(d) into first_d from _imp;
    -- مطابقة الرصيد مع «رصيد الحساب الحالي»
    if nullif(cu->>'balance','') is not null then
      bal := (cu->>'balance')::numeric;
      op := bal - coalesce((select sum(amount) from public.motor_invoices where customer_id = c.id and not voided and kind <> 'opening'), 0)
                + coalesce((select sum(amount) from public.motor_payments where customer_id = c.id and not voided), 0);
      select id into oid from public.motor_invoices where customer_id = c.id and kind = 'opening' and not voided order by created_at limit 1;
      delete from public.motor_invoices where customer_id = c.id and kind = 'opening' and not voided and id is distinct from oid;
      -- الفرق بالسالب = دفعات انقبضت بالبرنامج السابق → سطر «له» بعد آخر فاتورة مستوردة
      if op < 0 then
        if oid is not null then delete from public.motor_invoices where id = oid; oid := null; end if;
        update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
        insert into public.motor_invoices (site_id, no, customer_id, period, kind, amount, note, staff_name, imported, created_at)
        values (sid, seq, c.id, coalesce((select max(per) from _imp), ''), 'adjust', op, 'دفعات مسددة في البرنامج السابق', 'استيراد', true,
                coalesce(((select max(d) from _imp)::timestamp + interval '13 hours') at time zone 'Asia/Beirut', now()));
        op := 0;
        perform public._motor_spread_old_payments(c.id);
      end if;
      if oid is null and op <> 0 then
        update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
        insert into public.motor_invoices (site_id, no, customer_id, kind, amount, note, staff_name)
        values (sid, seq, c.id, 'opening', op, '', w->>'name') returning id into oid;
      end if;
      if oid is not null then
        if op = 0 then delete from public.motor_invoices where id = oid;
        else
          update public.motor_invoices set amount = op, note = 'رصيد سابق (مطابقة مع البرنامج السابق)',
                 created_at = coalesce(((first_d - 1)::timestamp + interval '12 hours') at time zone 'Asia/Beirut', created_at)
           where id = oid;
        end if;
      end if;
      n_bal := n_bal + 1;
    end if;
    -- الرصيد الجاري لكل فاتورة (للطباعة)
    run := 0;
    for r in select 'i' t, i.id, i.amount, i.created_at from public.motor_invoices i where i.customer_id = c.id and not i.voided
             union all select 'p', p.id, -p.amount, p.created_at from public.motor_payments p where p.customer_id = c.id and not p.voided
             order by 4, 1 loop
      if r.t = 'i' then
        update public.motor_invoices set balance_before = run, balance_after = run + r.amount where id = r.id and (imported or kind = 'opening');
      end if;
      run := run + r.amount;
    end loop;
    update public.motor_customers set balance = run,
           area = coalesce(nullif(trim(coalesce(cu->>'area','')), ''), area),
           next_prev = case when exists (select 1 from public.motor_readings where customer_id = c.id and imported) then null else next_prev end,
           updated_at = now()
     where id = c.id;
  end loop;
  return jsonb_build_object('ok', true, 'customers', n_cust, 'invoices', n_inv, 'readings', n_read, 'skipped', n_skip, 'balanced', n_bal);
end $$;

-- ============================================================
--  20j2) تصحيح الحسابات من «كشف حساب» البرنامج السابق (Excel)
--  لكل زبون: بيمسح يلّي انستورد من بعد تاريخ بداية الكشف ودفعات «البرنامج السابق» والرصيد السابق،
--  وبيرجع يبني الحركات متل الكشف بالظبط: فاتورة كل شهر بشهرها وتاريخها، الدفعات بتاريخها ورقم الإيصال،
--  الرسوم الإضافية (كونتكتير، تركيب...)، وكل شي قبل بداية الكشف بسطر «رصيد سابق».
--  الرصيد النهائي = رصيد الكشف − الدفعات يلّي انقبضت بهالبرنامج وما مسجّلة بالكشف.
-- ============================================================
create or replace function public.motor_import_statement(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; cu jsonb; x jsonb; c public.motor_customers%rowtype;
        f date; seq int; kept numeric; op numeric; pre_cr numeric; sdr numeric; scr numeric; run numeric; old numeric;
        amt numeric; per text; ts timestamptz; rid uuid; pid uuid; r record; v_kind text; skip_bill boolean;
        n_cust int := 0; n_rows int := 0; n_dup int := 0; n_app int := 0; changed jsonb := '[]'::jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if jsonb_typeof(p_data) <> 'array' then perform public._motor_err('bad_data'); end if;
  perform 1 from public.motor_sites where id = sid for update;
  create temp table if not exists _used_pay (id uuid primary key) on commit drop;
  for cu in select * from jsonb_array_elements(p_data) loop
    select * into c from public.motor_customers where id = (cu->>'customer_id')::uuid and site_id = sid and deleted_at is null for update;
    if not found then continue; end if;
    n_cust := n_cust + 1; old := c.balance;
    f := coalesce(nullif(cu->>'from','')::date, date '2026-05-11');
    -- امسح: المستورد من بعد بداية الكشف + كل تسويات الاستيراد + الرصيد السابق
    delete from public.motor_invoices
     where customer_id = c.id and (kind = 'opening'
        or (imported and kind = 'adjust')
        or (imported and (created_at at time zone 'Asia/Beirut')::date >= f));
    -- الفواتير المستوردة قبل بداية الكشف بتضل (فيها العدادات) والفرق بيصير «رصيد سابق»
    select coalesce(sum(amount), 0) into kept from public.motor_invoices
     where customer_id = c.id and imported and not voided and kind in ('meter','fixed');
    select coalesce(sum((v->>'dr')::numeric), 0), coalesce(sum((v->>'cr')::numeric), 0) into sdr, scr
      from jsonb_array_elements(cu->'rows') v;
    -- قبل بداية الكشف: فواتير (ناقص يلّي باقي مستورد) + دفعات. رصيد الكشف النهائي هو المرجع (فروقات التقريب).
    op := round(((cu->>'tdr')::numeric - sdr) - kept
                + (coalesce(nullif(cu->>'tb','')::numeric, (cu->>'tdr')::numeric - (cu->>'tcr')::numeric) - ((cu->>'tdr')::numeric - (cu->>'tcr')::numeric)), 2);
    pre_cr := round((cu->>'tcr')::numeric - scr, 2);
    if op <> 0 then
      update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
      insert into public.motor_invoices (site_id, no, customer_id, period, kind, amount, note, staff_name, imported, wa_sent_at, created_at)
      values (sid, seq, c.id, to_char(f - interval '1 month', 'YYYY-MM'), 'opening', op, 'رصيد ما قبل ' || to_char(f, 'YYYY/MM/DD') || ' (حسب كشف البرنامج السابق)',
              'استيراد', true, now(), ((f - 1)::timestamp + interval '11 hours') at time zone 'Asia/Beirut');
    end if;
    if pre_cr <> 0 then
      update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
      insert into public.motor_invoices (site_id, no, customer_id, period, kind, amount, note, staff_name, imported, wa_sent_at, created_at)
      values (sid, seq, c.id, to_char(f - interval '1 month', 'YYYY-MM'), 'adjust', -pre_cr, 'دفعات قبل ' || to_char(f, 'YYYY/MM/DD') || ' (حسب كشف البرنامج السابق)',
              'استيراد', true, now(), ((f - 1)::timestamp + interval '12 hours') at time zone 'Asia/Beirut');
    end if;
    truncate _used_pay;
    for x in select * from jsonb_array_elements(cu->'rows') loop
      amt := round(coalesce((x->>'dr')::numeric, 0) - coalesce((x->>'cr')::numeric, 0), 2);
      if amt = 0 then continue; end if;
      ts := (x->>'d')::timestamp;
      if ts::time = time '00:00' then ts := ts + interval '12 hours'; end if;
      ts := ts at time zone 'Asia/Beirut';
      per := coalesce(nullif(x->>'per',''), to_char((x->>'d')::timestamp, 'YYYY-MM'));
      if x->>'k' = 'pay' then
        -- دفعة انسجلت بالكشف وكمان انقبضت بهالبرنامج (نفس المبلغ، خلال 4 أيام): منكتفي بإيصال البرنامج
        select p.id into pid from public.motor_payments p
         where p.customer_id = c.id and not p.voided and p.amount = -amt
           and p.created_at >= ts - interval '1 hour' and p.created_at < ts + interval '4 days'
           and not exists (select 1 from _used_pay u where u.id = p.id)
         order by p.created_at limit 1;
        if pid is not null then insert into _used_pay values (pid); n_dup := n_dup + 1; continue; end if;
      end if;
      v_kind := 'adjust'; rid := null; skip_bill := false;
      if x->>'k' = 'bill' and amt > 0 then
        -- شهر انقرا بهالبرنامج: فاتورتو موجودة، ما منكررها
        if exists (select 1 from public.motor_invoices i where i.customer_id = c.id and not i.voided and not i.imported
                    and i.kind in ('meter','fixed') and i.period = per) then
          n_app := n_app + 1; continue;
        end if;
        select rr.id into rid from public.motor_readings rr where rr.customer_id = c.id and rr.period = per and rr.imported
           and not exists (select 1 from public.motor_invoices i where i.reading_id = rr.id) limit 1;
        v_kind := case when rid is null then 'fixed' else 'meter' end;
      end if;
      update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
      insert into public.motor_invoices (site_id, no, customer_id, period, kind, reading_id, plan_name, prev_value, cur_value, kwh,
             amount, note, staff_name, imported, wa_sent_at, created_at)
      select sid, seq, c.id, per, v_kind, rid, coalesce(x->>'svc',''), rr.prev_value, rr.value,
             coalesce(rr.value - rr.prev_value, 0), amt, left(coalesce(x->>'desc',''), 300), 'استيراد', true, now(), ts
        from (select 1) one left join public.motor_readings rr on rr.id = rid;
      n_rows := n_rows + 1;
    end loop;
    -- الرصيد الجاري لكل حركة (للطباعة) + رصيد الزبون
    run := 0;
    for r in select 'i' t, i.id, i.amount, i.created_at from public.motor_invoices i where i.customer_id = c.id and not i.voided
             union all select 'p', p.id, -p.amount, p.created_at from public.motor_payments p where p.customer_id = c.id and not p.voided
             order by 4, 1 loop
      if r.t = 'i' then
        update public.motor_invoices set balance_before = run, balance_after = run + r.amount where id = r.id and (imported or kind = 'opening');
      end if;
      run := run + r.amount;
    end loop;
    update public.motor_customers set balance = run, updated_at = now() where id = c.id;
    if run <> old then
      changed := changed || jsonb_build_array(jsonb_build_object('code', c.code, 'name', c.name, 'old', old, 'new', run));
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'customers', n_cust, 'rows', n_rows, 'dup_pays', n_dup, 'app_bills', n_app, 'changed', changed);
end $$;

-- ============================================================
--  20j3) الزبائن الذين لم يدفعوا بعد — الخط مفعّل وعليه فاتورة شهر (الدورة المختارة) أو أقدم غير مدفوعة
--  الفواتير المدفوعة تُحسب من الأقدم (الرصيد الحالي بيغطي آخر الفواتير)
-- ============================================================
create or replace function public.motor_unpaid(p_slug text, p_token text, p_period text, p_min integer default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; per text; st public.motor_sites%rowtype; mine uuid; out jsonb := '[]'::jsonb;
        c record; r record; acc numeric; pers text[]; amt numeric; n int; older boolean;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  if not ((w->>'is_admin')::boolean or (w->>'can_collect')::boolean) then perform public._motor_err('forbidden'); end if;
  if not (w->>'is_admin')::boolean and not st.collector_sees_all then mine := (w->>'staff_id')::uuid; end if;
  per := coalesce(nullif(p_period,''), st.bill_period);
  if per !~ '^\d{4}-\d{2}$' then perform public._motor_err('bad_period'); end if;
  for c in select cu.*, coalesce(sf.name, cu.collector_name) coll
             from public.motor_customers cu left join public.motor_staff sf on sf.id = cu.collector_id
            where cu.site_id = sid and cu.is_active and not cu.archived and cu.deleted_at is null and cu.balance > 0.005
              and (mine is null or cu.collector_id = mine) loop
    -- الرصيد بيتوزّع على الفواتير من الأحدث للأقدم: يلّي بيغطيهن الرصيد هني غير المدفوعين
    acc := 0; pers := '{}'; amt := 0; n := 0; older := false;
    for r in select i.period, i.amount from public.motor_invoices i
              where i.customer_id = c.id and not i.voided and i.amount > 0 and i.kind in ('meter','fixed') and i.period <> ''
              order by i.period desc, i.created_at desc loop
      exit when acc >= c.balance - 0.005;
      if r.period <= per then
        n := n + 1; amt := amt + least(r.amount, c.balance - acc);
        if not (r.period = any(pers)) then pers := r.period || pers; end if;
      end if;
      acc := acc + r.amount;
    end loop;
    if c.balance - acc > 0.005 then older := true; amt := amt + (c.balance - acc); end if;
    if n + (case when older then 1 else 0 end) >= greatest(coalesce(p_min, 1), 1) and amt > 0.005 then
      out := out || jsonb_build_array(jsonb_build_object(
        'id', c.id, 'code', c.code, 'name', c.name, 'mobile', c.mobile, 'mobile_cc', c.mobile_cc, 'box', c.box, 'area', c.area,
        'collector', c.coll, 'balance', c.balance, 'due', round(amt, 2), 'months', to_jsonb(pers), 'n', n, 'older', older,
        'last_pay', greatest(
            (select max(p.created_at) from public.motor_payments p where p.customer_id = c.id and not p.voided),
            (select max(i.created_at) from public.motor_invoices i where i.customer_id = c.id and not i.voided and i.imported
                and i.kind = 'adjust' and i.amount < 0 and i.note like 'ايصال%'))));
    end if;
  end loop;
  return jsonb_build_object('period', per, 'rows', out);
end $$;

-- ============================================================
--  20k) إقفال صندوق الموظف: يسلّم كل النقد للمكتب ويطلع تقرير
-- ============================================================
create or replace function public.motor_staff_close(p_slug text, p_token text, p_staff uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sf public.motor_staff%rowtype; since timestamptz; hand numeric; rep jsonb; m public.motor_moves%rowtype; nowt timestamptz := clock_timestamp();
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_staff is not null and p_staff::text is distinct from w->>'staff_id' and not (w->>'is_admin')::boolean then perform public._motor_err('forbidden'); end if;
  select * into sf from public.motor_staff where id = coalesce(p_staff, (w->>'staff_id')::uuid) and site_id = sid;
  if not found then perform public._motor_err('bad_staff'); end if;
  perform 1 from public.motor_staff where id = sf.id for update;
  since := coalesce((select max(created_at) from public.motor_moves where staff_id = sf.id and account = 'collector' and extra->>'type' = 'staff_close'),
                    '-infinity'::timestamptz);
  hand := coalesce((select sum(amount) from public.motor_payments where staff_id = sf.id and method = 'cash' and not voided), 0)
        - coalesce((select sum(amount) from public.motor_moves where staff_id = sf.id and account = 'collector'), 0);
  rep := jsonb_build_object(
    'staff', sf.name, 'from', case when since = '-infinity'::timestamptz then null else since end, 'to', nowt, 'by', w->>'name',
    'cash', coalesce((select sum(amount) from public.motor_payments where staff_id = sf.id and method = 'cash' and not voided and created_at > since), 0),
    'whish', coalesce((select sum(amount) from public.motor_payments where staff_id = sf.id and method = 'whish' and not voided and created_at > since), 0),
    'count', (select count(*) from public.motor_payments where staff_id = sf.id and not voided and created_at > since),
    'readings', (select count(*) from public.motor_readings where staff_id = sf.id and created_at > since),
    'handed_before', coalesce((select sum(amount) from public.motor_moves where staff_id = sf.id and account = 'collector' and created_at > since), 0),
    'handed', hand,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('no', p.no, 'at', p.created_at, 'customer', c.name, 'code', c.code, 'method', p.method,
               'amount', p.amount, 'paid_currency', p.paid_currency, 'paid_amount', p.paid_amount) order by p.created_at)
             from public.motor_payments p join public.motor_customers c on c.id = p.customer_id
            where p.staff_id = sf.id and not p.voided and p.created_at > since), '[]'::jsonb));
  insert into public.motor_moves (site_id, account, staff_id, kind, amount, note, by_name, extra, created_at)
  values (sid, 'collector', sf.id, 'handover', hand, 'إقفال صندوق ' || sf.name, w->>'name', rep || jsonb_build_object('type','staff_close'), nowt)
  returning * into m;
  return rep || jsonb_build_object('id', m.id);
end $$;

create or replace function public.motor_staff_closes(p_slug text, p_token text, p_staff uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; st uuid;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  st := case when (w->>'is_admin')::boolean then p_staff else (w->>'staff_id')::uuid end;
  return coalesce((select jsonb_agg((m.extra - 'type') || jsonb_build_object('id', m.id, 'at', m.created_at) order by m.created_at desc)
    from (select * from public.motor_moves where site_id = sid and account = 'collector' and extra->>'type' = 'staff_close'
            and (st is null or staff_id = st) order by created_at desc limit 40) m), '[]'::jsonb);
end $$;

-- ============================================================
--  20l) التأمينات: قبض تأمين / إعادة تأمين (من الصندوق أو Whish) + استيراد Excel
-- ============================================================
create or replace function public.motor_ins_list(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return jsonb_build_object(
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'at', i.created_at, 'customer_id', i.customer_id,
              'name', coalesce(c.name, i.name), 'code', c.code, 'kind', i.kind, 'amount', i.amount, 'account', i.account, 'ref_no', i.ref_no,
              'service', i.service, 'note', i.note, 'by', i.by_name, 'imported', i.imported) order by i.created_at)
            from public.motor_insurance i left join public.motor_customers c on c.id = i.customer_id where i.site_id = sid), '[]'::jsonb));
end $$;

create or replace function public.motor_ins_add(p_slug text, p_token text, p_customer uuid, p_kind text, p_amount numeric,
  p_account text, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype; m public.motor_moves%rowtype; x public.motor_insurance%rowtype; seq int;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into c from public.motor_customers where id = p_customer and site_id = sid;
  if not found then perform public._motor_err('customer_not_found'); end if;
  if p_kind not in ('in','out') then perform public._motor_err('bad_kind'); end if;
  if p_account not in ('cash','whish') then perform public._motor_err('bad_account'); end if;
  if coalesce(p_amount,0) <= 0 then perform public._motor_err('bad_amount'); end if;
  if p_kind = 'out' then
    m := public._motor_voucher(sid, w, p_account, p_amount, 'إعادة تأمين ' || c.name, p_note, 'insurance', null, '');
  else
    insert into public.motor_moves (site_id, account, kind, amount, note, by_name, category, extra)
    values (sid, p_account, case when p_account = 'cash' then 'in' else 'deposit' end, abs(p_amount), coalesce(p_note,''), w->>'name',
            'تأمين ' || c.name, jsonb_build_object('type','insurance'))
    returning * into m;
  end if;
  insert into public.motor_insurance (site_id, customer_id, name, kind, amount, account, ref_no, service, note, move_id, by_name)
  values (sid, c.id, c.name, p_kind, abs(p_amount), p_account, coalesce(m.vno::text,''), coalesce((select name from public.motor_plans where id = c.plan_id),''),
          coalesce(p_note,''), m.id, w->>'name')
  returning * into x;
  return jsonb_build_object('ok', true, 'row', to_jsonb(x) - 'site_id', 'vno', m.vno,
    'balance', coalesce((select sum(case when kind = 'in' then amount else -amount end) from public.motor_insurance where customer_id = c.id), 0));
end $$;

create or replace function public.motor_ins_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; x public.motor_insurance%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into x from public.motor_insurance where id = p_id and site_id = sid;
  if not found then perform public._motor_err('not_found'); end if;
  if x.move_id is not null then
    if exists (select 1 from public.motor_moves m join public.motor_day_closes dc on dc.site_id = m.site_id
                and dc.day = (m.created_at at time zone 'Asia/Beirut')::date where m.id = x.move_id) then perform public._motor_err('day_closed'); end if;
    delete from public.motor_moves where id = x.move_id;
  end if;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  values (sid, 'insurance', x.id, x.name || ' · ' || x.amount, to_jsonb(x), w->>'name');
  delete from public.motor_insurance where id = x.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.motor_ins_link(p_slug text, p_token text, p_name text, p_customer uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype; n int;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into c from public.motor_customers where id = p_customer and site_id = sid;
  if not found then perform public._motor_err('customer_not_found'); end if;
  update public.motor_insurance set customer_id = c.id, name = c.name where site_id = sid and customer_id is null and name = p_name;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'count', n);
end $$;

-- p_rows = [{at:'YYYY-MM-DD HH:MI', kind:'in'|'out', amount, ref_no, service, note, name, customer_id}] — بيستبدل المستورد قبل
create or replace function public.motor_ins_import(p_slug text, p_token text, p_rows jsonb, p_replace boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; n int;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_replace then delete from public.motor_insurance where site_id = sid and imported; end if;
  insert into public.motor_insurance (site_id, customer_id, name, kind, amount, account, ref_no, service, note, by_name, imported, created_at)
  select sid, (select id from public.motor_customers c where c.id::text = x->>'customer_id' and c.site_id = sid),
         coalesce(x->>'name',''), x->>'kind', abs((x->>'amount')::numeric), '', coalesce(x->>'ref_no',''), coalesce(x->>'service',''),
         coalesce(x->>'note',''), 'استيراد', true, ((x->>'at')::timestamp) at time zone 'Asia/Beirut'
    from jsonb_array_elements(p_rows) x
   where x->>'kind' in ('in','out') and coalesce(nullif(x->>'amount','')::numeric, 0) <> 0;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'count', n);
end $$;

-- ============================================================
--  20i) اليومية: كل القبض والصرف، وإقفال كل يوم بمجموع الصندوق وWhish
-- ============================================================
create or replace function public._motor_day_totals(p_sid uuid, p_day date)
returns jsonb language sql stable security definer set search_path = public as $$
  with b as (select (p_day::timestamp at time zone 'Asia/Beirut') as f, ((p_day + 1)::timestamp at time zone 'Asia/Beirut') as t)
  select jsonb_build_object(
    'cash_in',  coalesce((select sum(amount) from public.motor_payments, b where site_id = p_sid and not voided and method = 'cash' and created_at >= b.f and created_at < b.t), 0),
    'whish_in', coalesce((select sum(amount) from public.motor_payments, b where site_id = p_sid and not voided and method = 'whish' and created_at >= b.f and created_at < b.t), 0),
    'receipts_n', (select count(*) from public.motor_payments, b where site_id = p_sid and not voided and created_at >= b.f and created_at < b.t),
    'expenses', coalesce((select sum(amount) from public.motor_moves, b where site_id = p_sid and extra->>'type' = 'expense' and created_at >= b.f and created_at < b.t), 0),
    'salaries', coalesce((select sum(amount) from public.motor_moves, b where site_id = p_sid and extra->>'type' = 'salary' and created_at >= b.f and created_at < b.t), 0),
    'suppliers', coalesce((select sum(amount) from public.motor_moves, b where site_id = p_sid and extra->>'type' = 'supplier' and created_at >= b.f and created_at < b.t), 0),
    'cash_out', coalesce((select sum(amount) from public.motor_moves, b where site_id = p_sid and account = 'cash' and kind in ('out','close') and created_at >= b.f and created_at < b.t), 0),
    'whish_out', coalesce((select sum(abs(amount)) from public.motor_moves, b where site_id = p_sid and account = 'whish' and kind = 'withdraw' and created_at >= b.f and created_at < b.t), 0),
    'handovers', coalesce((select sum(amount) from public.motor_moves, b where site_id = p_sid and account = 'collector' and kind = 'handover' and created_at >= b.f and created_at < b.t), 0),
    'cash_box_end', public._motor_cash_bal(p_sid, (select t from b)),
    'whish_end', public._motor_whish_bal(p_sid, (select t from b)),
    'collectors_hand', coalesce((select sum(p.amount) from public.motor_payments p join public.motor_staff s on s.id = p.staff_id, b
                                  where p.site_id = p_sid and not p.voided and p.method = 'cash' and s.role <> 'admin' and p.created_at < b.t), 0)
                     - coalesce((select sum(amount) from public.motor_moves, b where site_id = p_sid and account = 'collector' and created_at < b.t), 0));
$$;
revoke all on function public._motor_day_totals(uuid, date) from public, anon, authenticated;

create or replace function public.motor_journal(p_slug text, p_token text, p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; f date := coalesce(p_from, public._motor_today()); t date := coalesce(p_to, public._motor_today());
        ft timestamptz; tt timestamptz;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if t - f > 400 then perform public._motor_err('bad_period'); end if;
  ft := f::timestamp at time zone 'Asia/Beirut'; tt := (t + 1)::timestamp at time zone 'Asia/Beirut';
  return jsonb_build_object(
    'from', f, 'to', t, 'today', public._motor_today(),
    'cash_open', public._motor_cash_bal(sid, ft), 'whish_open', public._motor_whish_bal(sid, ft),
    'cash_close', public._motor_cash_bal(sid, tt), 'whish_close', public._motor_whish_bal(sid, tt),
    'closes', coalesce((select jsonb_agg(jsonb_build_object('day', c.day, 'totals', c.totals, 'by', c.closed_by, 'at', c.closed_at))
                         from public.motor_day_closes c where c.site_id = sid and c.day between f and t), '[]'::jsonb),
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', d::date, 'totals', public._motor_day_totals(sid, d::date)) order by d)
                       from generate_series(f, t, interval '1 day') d), '[]'::jsonb),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
        select jsonb_build_object('t','pay','at',p.created_at,'no',p.no,'account',p.method,'in',p.amount,'out',0,
               'label', c.name, 'code', c.code, 'staff', p.staff_name, 'paid_currency', p.paid_currency, 'paid_amount', p.paid_amount,
               'note', p.note) as x
          from public.motor_payments p join public.motor_customers c on c.id = p.customer_id
         where p.site_id = sid and not p.voided and p.created_at >= ft and p.created_at < tt
        union all
        select jsonb_build_object('t', coalesce(m.extra->>'type', m.kind), 'kind', m.kind, 'at', m.created_at, 'no', m.vno,
               'account', m.account,
               'in', case when (m.account = 'cash' and (m.kind = 'in' or (m.kind = 'adjust' and m.amount > 0)))
                            or (m.account = 'whish' and (m.kind = 'deposit' or (m.kind = 'adjust' and m.amount > 0)))
                            or (m.account = 'collector' and m.kind = 'handover') then abs(m.amount) else 0 end,
               'out', case when m.kind in ('out','close','withdraw') or (m.kind = 'adjust' and m.amount < 0) then abs(m.amount) else 0 end,
               'label', coalesce(nullif(m.category,''), case when m.account = 'collector' then (select name from public.motor_staff where id = m.staff_id) else '' end),
               'staff', m.by_name, 'note', m.note)
          from public.motor_moves m
         where m.site_id = sid and m.created_at >= ft and m.created_at < tt
      ) q), '[]'::jsonb));
end $$;

create or replace function public.motor_day_close(p_slug text, p_token text, p_day date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; tot jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_day is null or p_day > public._motor_today() then perform public._motor_err('bad_period'); end if;
  if exists (select 1 from public.motor_day_closes where site_id = sid and day = p_day) then perform public._motor_err('day_closed'); end if;
  tot := public._motor_day_totals(sid, p_day);
  insert into public.motor_day_closes (site_id, day, totals, closed_by) values (sid, p_day, tot, w->>'name');
  return jsonb_build_object('ok', true, 'totals', tot);
end $$;

-- إعادة فتح يوم مقفل (المدير الأساسي فقط)
create or replace function public.motor_day_reopen(p_slug text, p_token text, p_day date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  if not coalesce((w->>'is_main')::boolean,false) then perform public._motor_err('main_only'); end if;
  delete from public.motor_day_closes where site_id = (w->>'site_id')::uuid and day = p_day;
  return jsonb_build_object('ok', true);
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

-- المؤسسات الموجودة قبل هذا التحديث: مستخدم ADMIN / 0000 إذا ما عندها مدير
do $$ declare r record; begin
  for r in select id from public.motor_sites loop perform public._motor_default_admin(r.id); end loop;
end $$;
-- الاستيراد القديم: «دفعات مسددة في البرنامج السابق» كانت سطر واحد بلا شهر → منوزّعها على الأشهر
do $$ declare r record; begin
  for r in select distinct customer_id from public.motor_invoices where imported and kind = 'adjust' and period = '' and amount < 0 loop
    perform public._motor_spread_old_payments(r.customer_id);
  end loop;
end $$;

-- المدير الأساسي لكل مؤسسة: مستخدم admin (أو أقدم مدير)
update public.motor_staff s set is_main = true
 where s.id = (select x.id from public.motor_staff x where x.site_id = s.site_id and x.role = 'admin'
               order by (lower(x.username) = 'admin') desc, x.created_at limit 1)
   and not exists (select 1 from public.motor_staff y where y.site_id = s.site_id and y.is_main);

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
    'motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision,boolean)',
    'motor_bill_fixed(text,text)', 'motor_invoice_void(text,text,uuid)', 'motor_adjust(text,text,uuid,numeric,text)',
    'motor_pay(text,text,uuid,numeric,text,text,text,double precision,double precision)',
    'motor_payment_void(text,text,uuid)', 'motor_month(text,text,text)', 'motor_settings_save(text,text,jsonb)',
    'motor_plan_save(text,text,jsonb)', 'motor_plan_delete(text,text,uuid)', 'motor_staff_save(text,text,jsonb,text)',
    'motor_window_all(text,text,date,date)', 'motor_staff_delete(text,text,uuid)',
    'motor_collector_statement(text,text,uuid,date,date)', 'motor_whish_statement(text,text,date,date)',
    'motor_move_add(text,text,text,uuid,text,numeric,text)', 'motor_move_delete(text,text,uuid)',
    'motor_dashboard(text,text)', 'motor_upload_ok(text,text)', 'motor_slug_available(text)',
    'motor_changes(text,text,timestamptz)',
    'motor_cash_statement(text,text,date,date)', 'motor_cash_close(text,text,numeric,numeric,text)',
    'motor_set_active(text,text,uuid,boolean,text,double precision,double precision)',
    'motor_note_add(text,text,uuid,text)', 'motor_ping(text,text,double precision,double precision,double precision)',
    'motor_staff_map(text,text)', 'motor_unpaid(text,text,text,integer)', 'motor_2fa_setup(text,text)', 'motor_2fa_enable(text,text,text)',
    'motor_2fa_disable(text,text,text,uuid)', 'motor_wa_outbox(text,text,integer)', 'motor_wa_mark(text,text,text,uuid)',
    'motor_reading_edit(text,text,uuid,numeric,text)', 'motor_customer_set_login(text,text,uuid,text,text)', 'motor_cust_me(text,text)',
    'motor_invoice_edit(text,text,uuid,numeric,text)', 'motor_payment_edit(text,text,uuid,numeric,text)',
    'motor_fill_barcodes(text,text)', 'motor_month_report(text,text,text)', 'motor_backup(text,text)',
    'motor_trash_list(text,text)', 'motor_trash_restore(text,text,uuid)', 'motor_trash_purge(text,text,uuid)',
    'motor_set_prev(text,text,uuid,numeric)', 'motor_set_prev_bulk(text,text,jsonb)',
    'motor_login(text,text,text,text,text,text)', 'motor_device_reset(text,text,uuid)',
    'motor_expense_add(text,text,text,text,numeric,text)', 'motor_vouchers(text,text,text,date,date)',
    'motor_salary_pay(text,text,uuid,numeric,text,text,text)', 'motor_salaries(text,text,text)',
    'motor_stock_list(text,text)', 'motor_stock_save(text,text,jsonb)', 'motor_stock_delete(text,text,uuid)',
    'motor_journal(text,text,date,date)', 'motor_day_close(text,text,date)', 'motor_day_reopen(text,text,date)',
    'motor_stock_out(text,text,uuid,numeric,uuid,text,text)', 'motor_stock_moves_list(text,text,uuid,date,date)',
    'motor_suppliers(text,text)', 'motor_supplier_save(text,text,jsonb)', 'motor_supplier_delete(text,text,uuid)',
    'motor_purchase_add(text,text,jsonb)', 'motor_purchase_void(text,text,uuid)', 'motor_supplier_pay(text,text,uuid,numeric,text,text)',
    'motor_supplier_statement(text,text,uuid)', 'motor_staff_salary_set(text,text,uuid,numeric)', 'motor_salary_due_add(text,text,uuid,text,numeric,text)',
    'motor_salary_due_all(text,text,text)', 'motor_salary_due_delete(text,text,uuid)', 'motor_staff_statement(text,text,uuid)',
    'motor_import_invoices(text,text,jsonb)', 'motor_import_statement(text,text,jsonb)', 'motor_impersonate(text,text,uuid)', 'motor_staff_close(text,text,uuid)', 'motor_staff_closes(text,text,uuid)',
    'motor_ins_list(text,text)', 'motor_ins_add(text,text,uuid,text,numeric,text,text)', 'motor_ins_delete(text,text,uuid)',
    'motor_ins_import(text,text,jsonb,boolean)', 'motor_ins_link(text,text,text,uuid)']
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
union all select 'read function', to_regprocedure('public.motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision,boolean)') is not null;
