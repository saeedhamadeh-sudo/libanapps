-- عداد مقطوع شهري لكل زبون: الكيلوات المقطوعة ما بتنحسب (مثلاً 240 − 150 = 90 بينحسبوا)
-- + لائحة الزبائن اللي ما انقرا عدادهم بجدول عدادات الشهر
alter table public.motor_customers add column if not exists kwh_free numeric default 0;
alter table public.motor_invoices  add column if not exists free_kwh numeric not null default 0;

create or replace function public.motor_customer_kwh_free(p_slug text, p_token text, p_customer uuid, p_kwh numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_kwh is null or p_kwh < 0 or p_kwh > 1000000 then perform public._motor_err('bad_value'); end if;
  update public.motor_customers set kwh_free = p_kwh, updated_at = now() where id = p_customer and site_id = sid;
  if not found then perform public._motor_err('customer_not_found'); end if;
  insert into public.motor_notes (site_id, customer_id, body, staff_id, staff_name)
  values (sid, p_customer, case when p_kwh > 0 then 'عداد مقطوع شهري: ' || p_kwh || ' ك.و.س' else 'أُلغي العداد المقطوع' end, (w->>'staff_id')::uuid, w->>'name');
  return jsonb_build_object('ok', true, 'kwh_free', p_kwh);
end $$;
grant execute on function public.motor_customer_kwh_free(text, text, uuid, numeric) to anon, authenticated;

do $$
declare d text;
begin
  -- القراءة: الطاقة على (الاستهلاك − المقطوع)
  select pg_get_functiondef('public.motor_read'::regproc) into d;
  if position('kwh_free' in d) = 0 then
    d := replace(d, '    energy := kwh * price;', '    energy := greatest(kwh - coalesce(c.kwh_free, 0), 0) * price;');
    d := replace(d, '  if coalesce(c.charge_discount_pct,0) <> 0 then update public.motor_invoices set disc_pct',
                    '  if coalesce(pl.kind,''meter'') = ''meter'' and coalesce(c.kwh_free,0) > 0 then update public.motor_invoices set free_kwh = c.kwh_free where id = inv.id; inv.free_kwh := c.kwh_free; end if;
  if coalesce(c.charge_discount_pct,0) <> 0 then update public.motor_invoices set disc_pct');
    execute d;
  end if;
  -- تعديل العداد / تعديل السابق
  select pg_get_functiondef('public.motor_reading_edit(text,text,uuid,numeric,text,numeric)'::regprocedure) into d;
  if position('free_kwh' in d) = 0 then
    d := replace(d, 'round(v_kwh * i.kwh_price, 2)', 'round(greatest(v_kwh - coalesce(i.free_kwh,0), 0) * i.kwh_price, 2)');
    execute d;
  end if;
  select pg_get_functiondef('public._motor_set_prev'::regproc) into d;
  if position('free_kwh' in d) = 0 then
    d := replace(d, 'round(v_kwh * i.kwh_price, 2)', 'round(greatest(v_kwh - coalesce(i.free_kwh,0), 0) * i.kwh_price, 2)');
    execute d;
  end if;
  -- تسعيرة الشهر
  select pg_get_functiondef('public.motor_month_price_set'::regproc) into d;
  if position('free_kwh' in d) = 0 then
    d := replace(d, 'en := round(coalesce(i.kwh,0) * p_price, 2);', 'en := round(greatest(coalesce(i.kwh,0) - coalesce(i.free_kwh,0), 0) * p_price, 2);');
    execute d;
  end if;
  -- جدول عدادات الشهر: الزبائن اللي ما انقرا عدادهم (للمدراء)
  select pg_get_functiondef('public.motor_month'::regproc) into d;
  if position('''unread''' in d) = 0 then
    d := replace(d, '    ''total_read'', (select count(*) from public.motor_readings where site_id = sid and period = per));',
'    ''total_read'', (select count(*) from public.motor_readings where site_id = sid and period = per),
    ''unread'', case when coalesce((w->>''is_admin'')::boolean, false) then coalesce((
      select jsonb_agg(jsonb_build_object(''customer_id'', c.id, ''code'', c.code, ''name'', c.name, ''barcode'', c.barcode, ''box'', c.box,
             ''area'', c.area, ''mobile'', c.mobile, ''collector'', coalesce((select name from public.motor_staff where id = c.collector_id), c.collector_name),
             ''collector_id'', c.collector_id, ''last_value'', (select r.value from public.motor_readings r where r.customer_id = c.id order by r.created_at desc limit 1))
             order by c.box, c.code)
        from public.motor_customers c left join public.motor_plans pl on pl.id = c.plan_id
       where c.site_id = sid and c.is_active and not c.archived and c.deleted_at is null and coalesce(pl.kind, ''meter'') = ''meter''
         and not exists (select 1 from public.motor_readings r where r.customer_id = c.id and r.period = per)), ''[]''::jsonb) end);');
    execute d;
  end if;
end $$;
