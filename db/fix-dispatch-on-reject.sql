-- ============================================================
--  fix-dispatch-on-reject.sql (2026-11-15)
--  لما المطعم يرفض أو يلغي طلب توصيل، الطلب لازم يلتغي عند السائق كمان —
--  حتى لو السائق كان مستلمو (claimed / ready_wait / on_the_way).
--  قبل: الإلغاء كان بس للطلب «المنتظر» وبس للحالة cancelled/failed (مش rejected).
--  آمن تشغيله أكتر من مرة.
-- ============================================================

alter table public.orders add column if not exists dispatch_cancelled_at timestamptz;

create or replace function public.auto_dispatch() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_mode text;
begin
  if new.order_type <> 'delivery' then return new; end if;
  -- رفض / إلغاء / فشل / استرجاع ← بيتوقف التوصيل، وبيضل driver_id حتى السائق يشوف إنو انلغى
  if new.status in ('rejected','cancelled','failed','refunded')
     and coalesce(new.dispatch,'') in ('waiting','claimed','ready_wait','on_the_way') then
    new.dispatch := 'cancelled';
    new.dispatch_cancelled_at := now();
    return new;
  end if;
  if new.dispatch is null and new.status in ('pending','paid','confirmed') then
    if not public.delivery_active(new.restaurant_id) then return new; end if;
    select dispatch_mode into v_mode from public.delivery_settings where restaurant_id = new.restaurant_id;
    if coalesce(v_mode,'auto') = 'auto' then
      new.dispatch := 'waiting';
      new.dispatched_at := now();
    end if;
  end if;
  return new;
end $$;

-- صفحة السائق: الطلبات اللي كانت معو وانلغت (آخر 3 ساعات) حتى يعرف ما يطلّعها
do $$
declare def text;
begin
  select pg_get_functiondef(p.oid) into def from pg_proc p
  where p.proname = 'driver_session' and p.pronamespace = 'public'::regnamespace;
  if def is not null and position('''cancelled'', coalesce' in def) = 0 then
    def := replace(def, '''done_today''',
      '''cancelled'', coalesce((select jsonb_agg(jsonb_build_object(' ||
        '''id'',o.id,''order_no'',o.order_no,''customer_name'',o.customer_name,' ||
        '''status'',o.status,''reason'',o.reject_reason,''at'',o.dispatch_cancelled_at) order by o.dispatch_cancelled_at desc) ' ||
      'from public.orders o where o.driver_id = d.id and o.dispatch = ''cancelled'' ' ||
        'and o.dispatch_cancelled_at > now() - interval ''3 hours''), ''[]''::jsonb), ' ||
      '''done_today''');
    execute def;
  end if;
end $$;

-- الطلبات العالقة من قبل (مرفوضة بس بعدها عند السائق)
update public.orders set dispatch = 'cancelled', dispatch_cancelled_at = coalesce(dispatch_cancelled_at, now() - interval '1 day')   -- قديمة: ما منعرضها للسائق
where order_type = 'delivery' and status in ('rejected','cancelled','failed','refunded')
  and dispatch in ('waiting','claimed','ready_wait','on_the_way');
