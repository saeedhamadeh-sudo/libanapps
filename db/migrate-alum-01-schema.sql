-- ============================================================
--  نقل برنامج محاسبة الصناعيين إلى منصة LibanApps
--  جداول بسابقة alum_ لتجنّب التعارض مع جداول المنيو
--  كل جدول مربوط بـ client_id ومحمي بـRLS
--  آمن للتشغيل أكثر من مرة — لا يحذف أي بيانات
--  شغّل upgrade-apps-tenancy.sql قبله
-- ============================================================

create table if not exists public.alum_customers (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  name text not null,
  account_number text,
  phone text,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  primary key (client_id, id)
);
alter table public.alum_customers add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_customers_client_idx on public.alum_customers (client_id);

create table if not exists public.alum_invoices (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  customer_id text,
  number text,
  date date,
  doc_type text,
  exchange_rate numeric,
  items jsonb,
  discount numeric default 0,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  admin_purged boolean default false,
  primary key (client_id, id)
);
alter table public.alum_invoices add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_invoices_client_idx on public.alum_invoices (client_id);

create table if not exists public.alum_receipts (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  customer_id text,
  number text,
  date date,
  amount numeric,
  method text,
  details text,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  admin_purged boolean default false,
  primary key (client_id, id)
);
alter table public.alum_receipts add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_receipts_client_idx on public.alum_receipts (client_id);

create table if not exists public.alum_suppliers (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  name text not null,
  account_number text,
  phone text,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  primary key (client_id, id)
);
alter table public.alum_suppliers add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_suppliers_client_idx on public.alum_suppliers (client_id);

create table if not exists public.alum_purchase_invoices (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  supplier_id text,
  number text,
  date date,
  doc_type text,
  exchange_rate numeric,
  items jsonb,
  discount numeric default 0,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  admin_purged boolean default false,
  primary key (client_id, id)
);
alter table public.alum_purchase_invoices add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_purchase_invoices_client_idx on public.alum_purchase_invoices (client_id);

create table if not exists public.alum_payment_vouchers (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  supplier_id text,
  number text,
  date date,
  amount numeric,
  method text,
  details text,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  admin_purged boolean default false,
  primary key (client_id, id)
);
alter table public.alum_payment_vouchers add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_payment_vouchers_client_idx on public.alum_payment_vouchers (client_id);

create table if not exists public.alum_workers (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  name text not null,
  account_number text,
  phone text,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  primary key (client_id, id)
);
alter table public.alum_workers add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_workers_client_idx on public.alum_workers (client_id);

create table if not exists public.alum_work_entries (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  worker_id text,
  number text,
  date date,
  daily_wage numeric default 0,
  overtime_hours numeric default 0,
  overtime_rate numeric default 0,
  weight_kg numeric default 0,
  kg_rate numeric default 0,
  details text,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  admin_purged boolean default false,
  primary key (client_id, id)
);
alter table public.alum_work_entries add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_work_entries_client_idx on public.alum_work_entries (client_id);

create table if not exists public.alum_worker_payments (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  worker_id text,
  number text,
  date date,
  amount numeric,
  method text,
  details text,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  admin_purged boolean default false,
  primary key (client_id, id)
);
alter table public.alum_worker_payments add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_worker_payments_client_idx on public.alum_worker_payments (client_id);

create table if not exists public.alum_deductions (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  customer_id text,
  type text,
  number text,
  date date,
  rows jsonb,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  admin_purged boolean default false,
  primary key (client_id, id)
);
alter table public.alum_deductions add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_deductions_client_idx on public.alum_deductions (client_id);

create table if not exists public.alum_quotes (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  customer_id text,
  number text,
  date date,
  doc_type text,
  specs jsonb,
  is_pdf boolean default false,
  pdf_data text,
  pdf_file_name text,
  is_custom_text boolean default false,
  customer_name text,
  scope text,
  location text,
  content text,
  direction text,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  admin_purged boolean default false,
  primary key (client_id, id)
);
alter table public.alum_quotes add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_quotes_client_idx on public.alum_quotes (client_id);

create table if not exists public.alum_warehouse_items (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  name text not null,
  brand text,
  type text,
  customer_id text,
  note text,
  purchase_date date,
  created_at bigint,
  primary key (client_id, id)
);
alter table public.alum_warehouse_items add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_warehouse_items_client_idx on public.alum_warehouse_items (client_id);

create table if not exists public.alum_stock_ins (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  item_id text,
  qty numeric,
  date date,
  number text,
  note text,
  created_at bigint,
  deleted boolean default false,
  primary key (client_id, id)
);
alter table public.alum_stock_ins add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_stock_ins_client_idx on public.alum_stock_ins (client_id);

create table if not exists public.alum_stock_outs (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  item_id text,
  worker_id text,
  qty numeric,
  date date,
  number text,
  note text,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  admin_purged boolean default false,
  primary key (client_id, id)
);
alter table public.alum_stock_outs add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_stock_outs_client_idx on public.alum_stock_outs (client_id);

create table if not exists public.alum_cutting_orders (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  customer_id text,
  deduction_id text,
  number text,
  date date,
  bar_length numeric,
  results jsonb,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  admin_purged boolean default false,
  primary key (client_id, id)
);
alter table public.alum_cutting_orders add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_cutting_orders_client_idx on public.alum_cutting_orders (client_id);

create table if not exists public.alum_customer_accounts (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  customer_id text,
  username text not null,
  password text not null,
  created_at bigint,
  primary key (client_id, id)
);
alter table public.alum_customer_accounts add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_customer_accounts_client_idx on public.alum_customer_accounts (client_id);

create table if not exists public.alum_worker_accounts (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  worker_id text,
  username text not null,
  password text not null,
  created_at bigint,
  primary key (client_id, id)
);
alter table public.alum_worker_accounts add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_worker_accounts_client_idx on public.alum_worker_accounts (client_id);

create table if not exists public.alum_budget_categories (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  key text,
  name text not null,
  type text not null, -- 'income' | 'expense'
  auto boolean default false,
  builtin boolean default false,
  primary key (client_id, id)
);
alter table public.alum_budget_categories add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_budget_categories_client_idx on public.alum_budget_categories (client_id);

create table if not exists public.alum_budget_entries (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  category_id text,
  amount numeric,
  date date,
  note text,
  number text,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  primary key (client_id, id)
);
alter table public.alum_budget_entries add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_budget_entries_client_idx on public.alum_budget_entries (client_id);

create table if not exists public.alum_app_users (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  username text not null,
  password text not null,
  role text not null, -- 'superuser' | 'admin' | 'custom'
  permissions jsonb default '[]',
  totp_secret text,
  totp_enabled boolean default false,
  primary key (client_id, id)
);
alter table public.alum_app_users add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_app_users_client_idx on public.alum_app_users (client_id);

create table if not exists public.alum_app_settings (
  client_id uuid not null references public.clients(id) on delete cascade,
  id int default 1,
  company_name text,
  company_tag text,
  company_phone text,
  logo text,
  default_exchange_rate numeric default 90000,
  invoice_start int default 0,
  receipt_start int default 1000,
  auto_backup_on_close boolean default false,
  quote_desc_options jsonb default '[]',
  spec_options jsonb default '{}',
  custom_deduction_profiles jsonb default '[]',
  trial_started_at bigint,
  license_serial text,
  license_expires_at bigint,
  license_label text,
  primary key (client_id)
);
alter table public.alum_app_settings add column if not exists client_id uuid references public.clients(id) on delete cascade;
create index if not exists alum_app_settings_client_idx on public.alum_app_settings (client_id);


-- ---------- أسماء الدخول فريدة داخل كل زبون ----------
create unique index if not exists alum_app_users_uq
  on public.alum_app_users (client_id, username);
create unique index if not exists alum_customer_accounts_uq
  on public.alum_customer_accounts (client_id, username);
create unique index if not exists alum_worker_accounts_uq
  on public.alum_worker_accounts (client_id, username);

-- إعدادات المؤسسة: صف واحد لكل زبون (المفتاح client_id)

-- ============================================================
--  الحماية: كل زبون يشوف بياناته هو فقط
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array['alum_customers', 'alum_invoices', 'alum_receipts', 'alum_suppliers', 'alum_purchase_invoices', 'alum_payment_vouchers', 'alum_workers', 'alum_work_entries', 'alum_worker_payments', 'alum_deductions', 'alum_quotes', 'alum_warehouse_items', 'alum_stock_ins', 'alum_stock_outs', 'alum_cutting_orders', 'alum_customer_accounts', 'alum_worker_accounts', 'alum_budget_categories', 'alum_budget_entries', 'alum_app_users', 'alum_app_settings']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists own_rows on public.%I', t);
    execute format(
      'create policy own_rows on public.%I for all to authenticated
         using (public.owns(client_id)) with check (public.owns(client_id))', t);
  end loop;
end $$;
