-- العدادات المعلّقة (بلا فاتورة بعد) بتبيّن «⏳ قيد الانتظار» بجدول الشهر وبصفحة الإرسال
do $$
declare d text;
begin
  select pg_get_functiondef('public.motor_month(text,text,text)'::regprocedure) into d;
  if position('inv_pending' in d) = 0 then
    d := replace(d, '''invoice_id'', i.id, ''invoice_no'', i.no,', '''pending'', r.inv_pending, ''invoice_id'', i.id, ''invoice_no'', i.no,');
    d := replace(d, 'left join public.motor_invoices i on i.reading_id = r.id', 'left join public.motor_invoices i on i.reading_id = r.id and not i.voided');
    if position('inv_pending' in d) = 0 then raise exception 'm patch'; end if;
    execute d;
  end if;
end $$;

-- لائحة العدادات المعلّقة لصفحة «الفواتير» (المدير)
create or replace function public.motor_pending_list(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token); sid := (w->>'site_id')::uuid;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'at', r.created_at, 'period', left(r.period,7),
            'bill_from', public._motor_bill_from(r.period), 'priced', public._motor_month_price(sid, left(r.period,7)) is not null,
            'prev', r.prev_value, 'value', r.value, 'kwh', r.value - r.prev_value, 'by', r.staff_name,
            'customer', jsonb_build_object('id', c.id, 'code', c.code, 'name', c.name, 'box', c.box, 'mobile', c.mobile, 'mobile_cc', c.mobile_cc))
            order by r.created_at desc)
     from public.motor_readings r join public.motor_customers c on c.id = r.customer_id
    where r.site_id = sid and r.inv_pending), '[]'::jsonb);
end $$;
revoke all on function public.motor_pending_list(text,text) from public, anon;
grant execute on function public.motor_pending_list(text,text) to anon, authenticated;
