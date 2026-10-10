-- ============================================================
--  البرنامج التجاري (trade): محل إطارات وبطاريات وزيوت + العمال
--
--  · نوع النشاط، أيقونة المتصفح، تفعيل العمال، لوائح المنتجات (الإعدادات)
--  · خانات المنتج الإضافية (عمود extra) — SKU، المقاس، DOT، الأمبير، اللزوجة...
--  · العداد السابق وتاريخ غيار الزيت للزبون (عمود extra)
--  · فاتورة مشتريات مع/بدون مستودع + فاتورة مرتجع مشتريات
--  · ربط حركات المستودع بالفاتورة (ref_id)
--  · جداول العمال: workers / work_entries / worker_payments / worker_accounts
--
--  آمن للتشغيل أكثر من مرة — لا يحذف أي بيانات.
--  الترتيب: شغّل هذا الملف أولاً، ثم أعد تشغيل secure-apps.sql
--  (ليضيف الحماية على جداول العمال الجديدة ويفعّل دخول العمال في التجاري).
-- ============================================================

-- ---------- 1) أعمدة جديدة على الجداول الموجودة ----------
alter table public.trade_app_settings      add column if not exists business_type   text default 'supermarket';
alter table public.trade_app_settings      add column if not exists favicon         text;
alter table public.trade_app_settings      add column if not exists workers_enabled boolean default false;
alter table public.trade_app_settings      add column if not exists product_lists   jsonb;

alter table public.trade_warehouse_items   add column if not exists extra jsonb;
alter table public.trade_customers         add column if not exists extra jsonb;

alter table public.trade_purchase_invoices add column if not exists add_to_stock boolean default false;
alter table public.trade_purchase_invoices add column if not exists is_return    boolean default false;

alter table public.trade_stock_ins         add column if not exists ref_id text;
alter table public.trade_stock_outs        add column if not exists ref_id text;

-- منع تكرار الباركود داخل نفس المؤسسة (الباركود الفارغ مسموح)
-- إذا فشل هذا السطر فمعناه أن عندك منتجات مكررة الباركود حالياً — نتخطاه ولا نوقف الملف
do $$
begin
  if not exists (select 1 from pg_indexes where schemaname='public' and indexname='trade_warehouse_items_barcode_uq') then
    begin
      create unique index trade_warehouse_items_barcode_uq
        on public.trade_warehouse_items (client_id, barcode)
        where barcode is not null and barcode <> '';
    exception when unique_violation then
      raise notice 'يوجد باركود مكرر حالياً — لم يُنشأ الفهرس الفريد. البرنامج يمنع التكرار من الواجهة.';
    end;
  end if;
end $$;

-- ---------- 2) جداول العمال ----------
create table if not exists public.trade_workers (
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
create index if not exists trade_workers_client_idx on public.trade_workers (client_id);

create table if not exists public.trade_work_entries (
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
create index if not exists trade_work_entries_client_idx on public.trade_work_entries (client_id);

create table if not exists public.trade_worker_payments (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  worker_id text,
  number text,
  date date,
  amount numeric default 0,
  method text,
  details text,
  created_at bigint,
  deleted boolean default false,
  deleted_at bigint,
  admin_purged boolean default false,
  primary key (client_id, id)
);
create index if not exists trade_worker_payments_client_idx on public.trade_worker_payments (client_id);

create table if not exists public.trade_worker_accounts (
  client_id uuid not null references public.clients(id) on delete cascade,
  id text not null,
  worker_id text,
  username text not null,
  password text,
  created_at bigint,
  primary key (client_id, id)
);
create index if not exists trade_worker_accounts_client_idx on public.trade_worker_accounts (client_id, username);

-- ---------- 3) الحماية: كل زبون يرى بياناته فقط ----------
do $$
declare t text;
begin
  foreach t in array array['trade_workers','trade_work_entries','trade_worker_payments','trade_worker_accounts']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists own_rows on public.%I', t);
    execute format(
      'create policy own_rows on public.%I for all to authenticated
         using (public.owns(client_id)) with check (public.owns(client_id))', t);
  end loop;
end $$;

-- إعادة تحميل مخطط PostgREST حتى تظهر الأعمدة والجداول الجديدة فوراً
notify pgrst, 'reload schema';
