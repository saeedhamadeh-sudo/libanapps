-- motorapp — الجزء 4 من 4. شغّل الأجزاء بالترتيب (1 ثم 2 …) كل جزء لحاله في Supabase SQL Editor.
-- ============================================================
--  20e) المدير يغيّر «العداد السابق» من جدول الزبائن
--       · إذا انقرى العداد هالدورة: بتتصحّح القراءة والفاتورة والرصيد
--       · وإلا: بينحفظ للقراءة الجاية (الاستهلاك = الحالي − هالقيمة)
-- ============================================================
create or replace function public._motor_set_prev(sid uuid, p_customer uuid, p_value numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare st public.motor_sites%rowtype; c public.motor_customers%rowtype; r public.motor_readings%rowtype;
        i public.motor_invoices%rowtype; v_kwh numeric; v_energy numeric; amt numeric; delta numeric := 0;
begin
  if p_value is null or p_value < 0 then perform public._motor_err('bad_value'); end if;
  select * into st from public.motor_sites where id = sid;
  select * into c from public.motor_customers where id = p_customer and site_id = sid and deleted_at is null for update;
  if not found then perform public._motor_err('customer_not_found'); end if;
  select * into r from public.motor_readings where customer_id = c.id and period = st.bill_period for update;
  if found then
    if r.value < p_value then perform public._motor_err('prev_above_cur', r.value::text); end if;
    update public.motor_readings set prev_value = p_value where id = r.id;
    select * into i from public.motor_invoices where reading_id = r.id and not voided for update;
    if found then
      v_kwh := r.value - p_value;
      v_energy := case when i.kind = 'meter' then round(v_kwh * i.kwh_price, 2) else 0 end;
      amt := public._motor_round(sid, i.fee + v_energy - i.discount + i.addition);
      delta := amt - i.amount;
      update public.motor_invoices set prev_value = p_value, kwh = v_kwh, energy = v_energy, amount = amt,
             balance_after = balance_after + delta where id = i.id;
    end if;
    update public.motor_customers set balance = balance + delta, updated_at = now() where id = c.id;
    return jsonb_build_object('ok', true, 'mode', 'current', 'delta', delta);
  end if;
  if not exists (select 1 from public.motor_readings where customer_id = c.id) then
    update public.motor_customers set initial_reading = p_value, next_prev = p_value, updated_at = now() where id = c.id;
  else
    update public.motor_customers set next_prev = p_value, updated_at = now() where id = c.id;
  end if;
  return jsonb_build_object('ok', true, 'mode', 'next');
end $$;
revoke all on function public._motor_set_prev(uuid, uuid, numeric) from public, anon, authenticated;

create or replace function public.motor_set_prev(p_slug text, p_token text, p_customer uuid, p_value numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  return public._motor_set_prev((w->>'site_id')::uuid, p_customer, p_value);
end $$;

-- إدخال العداد السابق دفعة وحدة (من ملف PDF): p_rows = [{id, value}]
create or replace function public.motor_set_prev_bulk(p_slug text, p_token text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; r jsonb; ok int := 0; errs jsonb := '[]'::jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 3000 then perform public._motor_err('bad_data'); end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    begin
      perform public._motor_set_prev(sid, (r->>'id')::uuid, (r->>'value')::numeric);
      ok := ok + 1;
    exception when others then
      errs := errs || jsonb_build_object('id', r->>'id', 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('ok', true, 'done', ok, 'errors', errs);
end $$;

-- ============================================================
--  21) رفع صورة العداد — تستدعيها الـWorker (/api/motor-photo) قبل الرفع
-- ============================================================
create or replace function public.motor_upload_ok(p_slug text, p_token text)
returns uuid language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_who(p_slug, p_token);
  return (w->>'site_id')::uuid;
end $$;

do $$ begin
  insert into storage.buckets (id, name, public) values ('motor','motor', true)
  on conflict (id) do nothing;
exception when others then raise notice 'bucket skipped: %', sqlerrm;
end $$;

-- المؤسسات الموجودة قبل هذا التحديث: مستخدم ADMIN / 0000 إذا ما عندها مدير
do $$ declare r record; begin
  for r in select id from public.motor_sites loop perform public._motor_default_admin(r.id); end loop;
end $$;

-- ============================================================
--  22) صلاحيات التنفيذ
-- ============================================================
do $$
declare f text;
begin
  foreach f in array array[
    'motor_public(text)', 'motor_logout(text)',
    'motor_change_password(text,text,text,text)', 'motor_me(text,text)', 'motor_customers(text,text)',
    'motor_customer_get(text,text,uuid,text)', 'motor_customer_save(text,text,jsonb)',
    'motor_customer_delete(text,text,uuid)', 'motor_import(text,text,jsonb)', 'motor_statement(text,text,uuid)',
    'motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision)',
    'motor_bill_fixed(text,text)', 'motor_invoice_void(text,text,uuid)', 'motor_adjust(text,text,uuid,numeric,text)',
    'motor_pay(text,text,uuid,numeric,text,text,text,double precision,double precision)',
    'motor_payment_void(text,text,uuid)', 'motor_month(text,text,text)', 'motor_settings_save(text,text,jsonb)',
    'motor_plan_save(text,text,jsonb)', 'motor_plan_delete(text,text,uuid)', 'motor_staff_save(text,text,jsonb,text)',
    'motor_window_all(text,text,date,date)', 'motor_staff_delete(text,text,uuid)',
    'motor_collector_statement(text,text,uuid,date,date)', 'motor_whish_statement(text,text,date,date)',
    'motor_move_add(text,text,text,uuid,text,numeric,text)', 'motor_move_delete(text,text,uuid)',
    'motor_dashboard(text,text)', 'motor_upload_ok(text,text)', 'motor_slug_available(text)',
    'motor_login(text,text,text,text)', 'motor_changes(text,text,timestamptz)',
    'motor_cash_statement(text,text,date,date)', 'motor_cash_close(text,text,numeric,numeric,text)',
    'motor_set_active(text,text,uuid,boolean,text,double precision,double precision)',
    'motor_note_add(text,text,uuid,text)', 'motor_ping(text,text,double precision,double precision,double precision)',
    'motor_staff_map(text,text)', 'motor_2fa_setup(text,text)', 'motor_2fa_enable(text,text,text)',
    'motor_2fa_disable(text,text,text,uuid)', 'motor_wa_outbox(text,text,integer)', 'motor_wa_mark(text,text,text,uuid)',
    'motor_reading_edit(text,text,uuid,numeric,text)', 'motor_customer_set_login(text,text,uuid,text,text)', 'motor_cust_me(text,text)',
    'motor_invoice_edit(text,text,uuid,numeric,text)', 'motor_payment_edit(text,text,uuid,numeric,text)',
    'motor_fill_barcodes(text,text)', 'motor_month_report(text,text,text)', 'motor_backup(text,text)',
    'motor_trash_list(text,text)', 'motor_trash_restore(text,text,uuid)', 'motor_trash_purge(text,text,uuid)',
    'motor_set_prev(text,text,uuid,numeric)', 'motor_set_prev_bulk(text,text,jsonb)']
  loop
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;

revoke all on function public.admin_new_motor(uuid, text, text, integer, numeric) from public, anon;
revoke all on function public.ensure_motor(text) from public, anon;
revoke all on function public.start_motor_trial(text, text) from public, anon;
revoke all on function public.admin_motor_product(numeric, numeric, integer, boolean) from public, anon;
grant execute on function public.admin_new_motor(uuid, text, text, integer, numeric) to authenticated;
grant execute on function public.ensure_motor(text) to authenticated;
grant execute on function public.start_motor_trial(text, text) to authenticated;
grant execute on function public.admin_motor_product(numeric, numeric, integer, boolean) to authenticated;
revoke all on function public._motor_round(uuid, numeric) from public, anon, authenticated;

-- تحقق سريع
select 'motor product' as item, exists (select 1 from public.products where code = 'motor') as ok
union all select 'motor plan', exists (select 1 from public.plans where product_code = 'motor')
union all select 'motor tables', to_regclass('public.motor_customers') is not null and to_regclass('public.motor_moves') is not null
union all select 'portal link ok', pg_get_functiondef('public.my_client_id()'::regprocedure) like '%portal_users%'
union all select 'read function', to_regprocedure('public.motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision)') is not null;

