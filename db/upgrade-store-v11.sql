-- ============================================================
--  LibanApps Store — v11
--   • حذف طلب نهائيًا من لوحة التحكم (زر منفصل عن الإلغاء)
--     - إذا الطلب لسا مش ملغي، بيرجّع المخزون أولًا (مثل store_cancel_order)
--       حتى ما تضيع الكمية، وبعدين يحذف الطلب وبنوده نهائيًا.
--  شغّله بعد upgrade-store-v10.sql — آمن للتشغيل أكثر من مرة.
-- ============================================================
create or replace function public.store_delete_order(p_order_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.store_orders%rowtype; it record;
begin
  select * into o from public.store_orders where id = p_order_id for update;
  if not found then return jsonb_build_object('ok', true); end if;  -- محذوف أصلًا
  if not public.store_owned(o.store_id) then raise exception 'not authorized'; end if;

  if o.status <> 'cancelled' then
    for it in select * from public.store_order_items where order_id = o.id loop
      if coalesce(it.size, '') <> '' then
        perform public._size_stock_add(it.product_id, it.size, it.qty);
      else
        update public.store_products set stock = stock + it.qty where id = it.product_id and stock is not null;
      end if;
    end loop;
  end if;

  delete from public.store_orders where id = o.id;  -- store_order_items بينحذف تلقائيًا (on delete cascade)
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.store_delete_order(bigint) to authenticated;

select 'store_delete_order' as item, exists (select 1 from pg_proc where proname='store_delete_order') as ok;
