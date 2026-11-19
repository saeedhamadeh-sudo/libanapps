-- إلغاء عداد مأخوذ (المدير + المدير الأساسي) لأي دورة: بيلغي الفاتورة تبعو (والرصيد بيرجع) أو بيمحي القراءة إذا ما إلها فاتورة
create or replace function public.motor_reading_void(p_slug text, p_token text, p_reading uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; r public.motor_readings%rowtype; iid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into r from public.motor_readings where id = p_reading and site_id = sid for update;
  if not found then perform public._motor_err('not_found'); end if;
  select id into iid from public.motor_invoices where reading_id = r.id and not voided limit 1;
  if iid is not null then
    return public.motor_invoice_void(p_slug, p_token, iid);
  end if;
  delete from public.motor_readings where id = r.id;
  update public.motor_customers set updated_at = now() where id = r.customer_id;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  values (sid, 'reading', r.id, 'عداد ' || coalesce(r.period,'') || ' — ' || (select name from public.motor_customers where id = r.customer_id) || ' (' || r.prev_value || '→' || r.value || ')',
          to_jsonb(r), w->>'name');
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.motor_reading_void(text, text, uuid) to anon, authenticated;

-- عدادات الزبون (لكل الدورات) لصفحة الزبون
create or replace function public.motor_cust_readings(p_slug text, p_token text, p_customer uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'period', r.period, 'prev_value', r.prev_value, 'value', r.value,
           'kwh', r.value - r.prev_value, 'at', r.created_at, 'by', coalesce(r.staff_name, ''), 'invoice_no', i.no, 'amount', i.amount,
           'latest', not exists (select 1 from public.motor_readings x where x.customer_id = r.customer_id and x.created_at > r.created_at))
           order by r.created_at desc)
    from public.motor_readings r left join public.motor_invoices i on i.reading_id = r.id and not i.voided
    where r.site_id = sid and r.customer_id = p_customer), '[]'::jsonb);
end $$;
grant execute on function public.motor_cust_readings(text, text, uuid) to anon, authenticated;

-- استرجاع عداد ملغى (بلا فاتورة) من سلة المحذوفات
do $$
declare d text;
begin
  select pg_get_functiondef('public.motor_trash_restore'::regproc) into d;
  if position('tr.kind = ''reading''' in d) = 0 then
    d := replace(d, '  elsif tr.kind = ''move'' then', '  elsif tr.kind = ''reading'' then
    r := jsonb_populate_record(null::public.motor_readings, tr.data);
    if exists (select 1 from public.motor_readings where customer_id = r.customer_id and period = r.period) then
      perform public._motor_err(''already_read'', r.period);
    end if;
    insert into public.motor_readings values (r.*);
  elsif tr.kind = ''move'' then');
    execute d;
  end if;
end $$;
