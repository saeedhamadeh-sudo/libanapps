-- ============================================================
--  ترقية: الزبون يقدر يلغي عملية شراء معلّقة
--  الإلغاء متاح فقط لعمليته هو، وفقط إذا لم تُدفع
-- ============================================================

create or replace function public.cancel_purchase(p_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.purchases%rowtype;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;

  select * into p from public.purchases where id = p_id;
  if not found then raise exception 'not found'; end if;
  if p.user_id <> auth.uid() and not public.is_admin() then raise exception 'not allowed'; end if;
  if p.status = 'paid' then
    return jsonb_build_object('ok', false, 'reason', 'مدفوعة — ما فينا نلغيها');
  end if;

  delete from public.purchases where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- تنظيف تلقائي: العمليات المعلّقة القديمة (أكثر من يوم) تُلغى
create or replace function public.expire_stale_purchases()
returns integer language sql security definer set search_path = public as $$
  with x as (
    update public.purchases
       set status = 'cancelled'
     where status in ('pending','awaiting_payment')
       and created_at < now() - interval '24 hours'
    returning 1
  ) select count(*)::int from x;
$$;
