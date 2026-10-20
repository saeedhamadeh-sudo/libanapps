-- ============================================================
--  LibanApps Store — v10
--   • إخفاء زبون من تبويب "الزبائن" (بدون حذف طلباته) — stores.hidden_customers
--   • إلغاء طلب من لوحة التحكم مع إرجاع المخزون تلقائيًا — store_cancel_order()
--  شغّله بعد upgrade-store-v9.sql — آمن للتشغيل أكثر من مرة.
-- ============================================================
alter table public.stores add column if not exists hidden_customers text[] not null default '{}';

-- إلغاء طلب: يتحقق من ملكية المتجر (نفس صلاحية تعديل الطلبات بالضبط)، يرجّع الكمية
-- للمخزون (بالمقاس إذا فيه مقاسات، وإلا بالمنتج نفسه)، وبعدين يحطّ الحالة "ملغي".
-- آمن للاستدعاء أكثر من مرة على نفس الطلب — إذا كان ملغي أصلاً ما بيرجّع المخزون مرتين.
create or replace function public.store_cancel_order(p_order_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.store_orders%rowtype; it record;
begin
  select * into o from public.store_orders where id = p_order_id for update;
  if not found then raise exception 'order not found'; end if;
  if not public.store_owned(o.store_id) then raise exception 'not authorized'; end if;
  if o.status = 'cancelled' then return jsonb_build_object('ok', true, 'already', true); end if;

  for it in select * from public.store_order_items where order_id = o.id loop
    if coalesce(it.size, '') <> '' then
      perform public._size_stock_add(it.product_id, it.size, it.qty);
    else
      update public.store_products set stock = stock + it.qty where id = it.product_id and stock is not null;
    end if;
  end loop;

  update public.store_orders set status = 'cancelled' where id = o.id;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.store_cancel_order(bigint) to authenticated;

select 'stores.hidden_customers' as item,
       exists (select 1 from information_schema.columns where table_name='stores' and column_name='hidden_customers') as ok
union all
select 'store_cancel_order', exists (select 1 from pg_proc where proname='store_cancel_order')
union all
select '_size_stock_add', exists (select 1 from pg_proc where proname='_size_stock_add')
union all
select 'store_owned', exists (select 1 from pg_proc where proname='store_owned');
