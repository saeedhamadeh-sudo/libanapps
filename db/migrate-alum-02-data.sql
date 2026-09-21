-- ============================================================
--  نقل بيانات زبون من مشروعه القديم إلى المنصة
--
--  الطريقة (بدون أدوات خارجية):
--  ١) من مشروع الزبون القديم: Table Editor → كل جدول → Export CSV
--  ٢) من مشروع المنصة: Table Editor → alum_<الجدول> → Import CSV
--  ٣) شغّل هذا الملف بعد الاستيراد ليربط الصفوف بالزبون
--
--  ⚠️ بدّل الـUUID تحت بهوية الزبون الفعلية
-- ============================================================

-- هوية الزبون: خودها من تبويب الزبائن بلوحتك، أو:
--   select id, name from public.clients order by created_at desc;

do $$
declare
  cid uuid := '00000000-0000-0000-0000-000000000000';  -- ← بدّلها
  t text;
  n integer;
begin
  if not exists (select 1 from public.clients where id = cid) then
    raise exception 'هوية الزبون غير موجودة — بدّل cid أولاً';
  end if;

  foreach t in array array[
    'alum_customers','alum_invoices','alum_receipts','alum_suppliers',
    'alum_purchase_invoices','alum_payment_vouchers','alum_workers',
    'alum_work_entries','alum_worker_payments','alum_deductions','alum_quotes',
    'alum_warehouse_items','alum_stock_ins','alum_stock_outs','alum_cutting_orders',
    'alum_customer_accounts','alum_worker_accounts','alum_budget_categories',
    'alum_budget_entries','alum_app_users','alum_app_settings'
  ]
  loop
    execute format('update public.%I set client_id = $1 where client_id is null', t) using cid;
    get diagnostics n = row_count;
    if n > 0 then raise notice '% → % صف', t, n; end if;
  end loop;
end $$;

-- ============================================================
--  تحقّق: كم صف لكل جدول ولمين
-- ============================================================
select 'alum_customers'      as t, count(*) , count(client_id) as linked from public.alum_customers
union all select 'alum_invoices',        count(*), count(client_id) from public.alum_invoices
union all select 'alum_receipts',        count(*), count(client_id) from public.alum_receipts
union all select 'alum_suppliers',       count(*), count(client_id) from public.alum_suppliers
union all select 'alum_purchase_invoices',count(*),count(client_id) from public.alum_purchase_invoices
union all select 'alum_payment_vouchers',count(*), count(client_id) from public.alum_payment_vouchers
union all select 'alum_workers',         count(*), count(client_id) from public.alum_workers
union all select 'alum_work_entries',    count(*), count(client_id) from public.alum_work_entries
union all select 'alum_worker_payments', count(*), count(client_id) from public.alum_worker_payments
union all select 'alum_deductions',      count(*), count(client_id) from public.alum_deductions
union all select 'alum_quotes',          count(*), count(client_id) from public.alum_quotes
union all select 'alum_warehouse_items', count(*), count(client_id) from public.alum_warehouse_items
union all select 'alum_stock_ins',       count(*), count(client_id) from public.alum_stock_ins
union all select 'alum_stock_outs',      count(*), count(client_id) from public.alum_stock_outs
union all select 'alum_cutting_orders',  count(*), count(client_id) from public.alum_cutting_orders
union all select 'alum_app_users',       count(*), count(client_id) from public.alum_app_users
union all select 'alum_app_settings',    count(*), count(client_id) from public.alum_app_settings;
