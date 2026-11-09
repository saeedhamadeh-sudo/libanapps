-- motorapp — الجزء 4 من 4 (شغّل الأجزاء بالترتيب)
-- ============================================================
--  20d) سلة المحذوفات (المدير): إرجاع أو حذف نهائي
-- ============================================================
create or replace function public.motor_trash_list(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'kind', t.kind, 'label', t.label, 'by', t.deleted_by,
           'at', t.deleted_at, 'amount', t.data->'amount') order by t.deleted_at desc)
         from public.motor_trash t where t.site_id = (w->>'site_id')::uuid), '[]'::jsonb);
end $$;

create or replace function public.motor_trash_restore(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; tr public.motor_trash%rowtype; i public.motor_invoices%rowtype; p public.motor_payments%rowtype;
        r public.motor_readings%rowtype; nid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into tr from public.motor_trash where id = p_id and site_id = sid for update;
  if not found then perform public._motor_err('not_found'); end if;
  if tr.kind = 'customer' then
    update public.motor_customers set deleted_at = null, updated_at = now() where id = tr.ref_id and site_id = sid;
  elsif tr.kind = 'invoice' then
    select * into i from public.motor_invoices where id = tr.ref_id and site_id = sid for update;
    if found and i.voided then
      if i.voided_reading is not null then
        r := jsonb_populate_record(null::public.motor_readings, i.voided_reading);
        if exists (select 1 from public.motor_readings where customer_id = r.customer_id and period = r.period) then
          perform public._motor_err('already_read', r.period);
        end if;
        insert into public.motor_readings values (r.*) returning id into nid;
      end if;
      update public.motor_invoices set voided = false, voided_at = null, voided_by = '', reading_id = nid, voided_reading = null where id = i.id;
      update public.motor_customers set balance = balance + i.amount, updated_at = now() where id = i.customer_id;
    end if;
  elsif tr.kind = 'payment' then
    select * into p from public.motor_payments where id = tr.ref_id and site_id = sid for update;
    if found and p.voided then
      update public.motor_payments set voided = false, voided_at = null, voided_by = '' where id = p.id;
      update public.motor_customers set balance = balance - p.amount, updated_at = now() where id = p.customer_id;
    end if;
  elsif tr.kind = 'move' then
    insert into public.motor_moves select (jsonb_populate_record(null::public.motor_moves, tr.data)).*;
  elsif tr.kind = 'plan' then
    insert into public.motor_plans select (jsonb_populate_record(null::public.motor_plans, tr.data)).*;
  elsif tr.kind = 'staff' then
    insert into public.motor_staff select (jsonb_populate_record(null::public.motor_staff, tr.data)).*;
  elsif tr.kind = 'stock' then
    insert into public.motor_stock select (jsonb_populate_record(null::public.motor_stock, tr.data)).*;
  end if;
  delete from public.motor_trash where id = tr.id;
  return jsonb_build_object('ok', true, 'kind', tr.kind);
end $$;

-- حذف نهائي (p_id فاضي = إفراغ السلة كلها)
create or replace function public.motor_trash_purge(p_slug text, p_token text, p_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; tr record; n int := 0;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  for tr in select * from public.motor_trash where site_id = sid and (p_id is null or id = p_id) loop
    if tr.kind = 'customer' then
      delete from public.motor_customers where id = tr.ref_id and site_id = sid and deleted_at is not null;
    elsif tr.kind = 'invoice' then
      delete from public.motor_invoices where id = tr.ref_id and site_id = sid and voided;
    elsif tr.kind = 'payment' then
      delete from public.motor_payments where id = tr.ref_id and site_id = sid and voided;
    end if;
    delete from public.motor_trash where id = tr.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'count', n);
end $$;

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
--  20f) فك قفل الجهاز (المدير الأساسي فقط)
-- ============================================================
create or replace function public.motor_device_reset(p_slug text, p_token text, p_staff uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not coalesce((w->>'is_main')::boolean,false) then perform public._motor_err('main_only'); end if;
  update public.motor_staff set device_id = null, device_label = '', device_at = null where id = p_staff and site_id = sid;
  delete from public.motor_sessions where staff_id = p_staff;
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  20g) المصاريف والمعاشات = سند صرف ينقص من الصندوق أو Whish
-- ============================================================
create or replace function public._motor_whish_bal(p_sid uuid, p_before timestamptz default null)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select sum(amount) from public.motor_payments where site_id = p_sid and method = 'whish' and not voided
                     and (p_before is null or created_at < p_before)), 0)
       + coalesce((select sum(case when kind = 'withdraw' then -abs(amount) else amount end) from public.motor_moves
                     where site_id = p_sid and account = 'whish' and (p_before is null or created_at < p_before)), 0);
$$;
revoke all on function public._motor_whish_bal(uuid, timestamptz) from public, anon, authenticated;

create or replace function public._motor_voucher(p_sid uuid, p_w jsonb, p_account text, p_amount numeric, p_category text,
  p_note text, p_type text, p_staff uuid, p_period text)
returns public.motor_moves language plpgsql security definer set search_path = public as $$
declare seq int; m public.motor_moves%rowtype;
begin
  if p_account not in ('cash','whish') then perform public._motor_err('bad_account'); end if;
  if coalesce(p_amount,0) <= 0 then perform public._motor_err('bad_amount'); end if;
  update public.motor_sites set voucher_seq = voucher_seq + 1 where id = p_sid returning voucher_seq into seq;
  insert into public.motor_moves (site_id, account, kind, amount, note, by_name, category, vno, pay_staff, period, extra)
  values (p_sid, p_account, case when p_account = 'cash' then 'out' else 'withdraw' end, abs(p_amount), coalesce(p_note,''),
          p_w->>'name', coalesce(p_category,''), seq, p_staff, coalesce(p_period,''), jsonb_build_object('type', p_type))
  returning * into m;
  return m;
end $$;
revoke all on function public._motor_voucher(uuid, jsonb, text, numeric, text, text, text, uuid, text) from public, anon, authenticated;

create or replace function public.motor_expense_add(p_slug text, p_token text, p_account text, p_category text, p_amount numeric, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; m public.motor_moves%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  if coalesce(trim(p_category),'') = '' then perform public._motor_err('name_required'); end if;
  m := public._motor_voucher((w->>'site_id')::uuid, w, p_account, p_amount, trim(p_category), p_note, 'expense', null, '');
  return jsonb_build_object('ok', true, 'move', to_jsonb(m) - 'site_id');
end $$;

create or replace function public.motor_vouchers(p_slug text, p_token text, p_type text, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; f date; t date;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  f := coalesce(p_from, date '2000-01-01'); t := coalesce(p_to, date '2999-12-31');
  return coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'vno', m.vno, 'at', m.created_at, 'account', m.account,
           'amount', m.amount, 'category', m.category, 'note', m.note, 'by', m.by_name, 'period', m.period,
           'staff_id', m.pay_staff, 'staff', (select name from public.motor_staff where id = m.pay_staff)) order by m.created_at desc)
         from public.motor_moves m where m.site_id = sid and m.extra->>'type' = p_type
          and (m.created_at at time zone 'Asia/Beirut')::date between f and t), '[]'::jsonb);
end $$;

create or replace function public.motor_salary_pay(p_slug text, p_token text, p_staff uuid, p_amount numeric, p_account text,
  p_period text, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sf public.motor_staff%rowtype; m public.motor_moves%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into sf from public.motor_staff where id = p_staff and site_id = sid;
  if not found then perform public._motor_err('bad_staff'); end if;
  if coalesce(p_period,'') !~ '^\d{4}-\d{2}$' then perform public._motor_err('bad_period'); end if;
  m := public._motor_voucher(sid, w, p_account, p_amount, 'معاش ' || sf.name, p_note, 'salary', sf.id, p_period);
  return jsonb_build_object('ok', true, 'move', to_jsonb(m) - 'site_id');
end $$;

create or replace function public.motor_salaries(p_slug text, p_token text, p_period text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'role', s.role, 'is_active', s.is_active,
           'salary', s.salary,
           'paid', coalesce((select sum(m.amount) from public.motor_moves m where m.pay_staff = s.id and m.extra->>'type' = 'salary' and m.period = p_period), 0),
           'payments', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'vno', m.vno, 'at', m.created_at, 'amount', m.amount,
                          'account', m.account, 'note', m.note) order by m.created_at)
                        from public.motor_moves m where m.pay_staff = s.id and m.extra->>'type' = 'salary' and m.period = p_period), '[]'::jsonb))
           order by s.name)
         from public.motor_staff s where s.site_id = sid and (s.is_active or s.salary > 0)), '[]'::jsonb);
end $$;

-- ============================================================
--  20h) المخزون (الموجودات)
-- ============================================================
create or replace function public.motor_stock_list(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  return coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.category, x.name) from public.motor_stock x
                    where x.site_id = (w->>'site_id')::uuid), '[]'::jsonb);
end $$;

create or replace function public.motor_stock_save(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; d jsonb := coalesce(p_data,'{}'::jsonb); x public.motor_stock%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(trim(d->>'name'),'') = '' then perform public._motor_err('name_required'); end if;
  if coalesce(d->>'id','') = '' then
    insert into public.motor_stock (site_id, name, category, qty, unit_price, notes, updated_by)
    values (sid, trim(d->>'name'), coalesce(d->>'category',''), coalesce(nullif(d->>'qty','')::numeric,0),
            coalesce(nullif(d->>'unit_price','')::numeric,0), coalesce(d->>'notes',''), w->>'name')
    returning * into x;
  else
    update public.motor_stock set name = trim(d->>'name'), category = coalesce(d->>'category',''),
           qty = coalesce(nullif(d->>'qty','')::numeric,0), unit_price = coalesce(nullif(d->>'unit_price','')::numeric,0),
           notes = coalesce(d->>'notes',''), updated_by = w->>'name', updated_at = now()
     where id = (d->>'id')::uuid and site_id = sid returning * into x;
    if x.id is null then perform public._motor_err('not_found'); end if;
  end if;
  return to_jsonb(x) - 'site_id';
end $$;

create or replace function public.motor_stock_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  select sid, 'stock', x.id, x.name || ' × ' || x.qty, to_jsonb(x), w->>'name' from public.motor_stock x where x.id = p_id and x.site_id = sid;
  delete from public.motor_stock where id = p_id and site_id = sid;
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  20i) اليومية: كل القبض والصرف، وإقفال كل يوم بمجموع الصندوق وWhish
-- ============================================================
create or replace function public._motor_day_totals(p_sid uuid, p_day date)
returns jsonb language sql stable security definer set search_path = public as $$
  with b as (select (p_day::timestamp at time zone 'Asia/Beirut') as f, ((p_day + 1)::timestamp at time zone 'Asia/Beirut') as t)
  select jsonb_build_object(
    'cash_in',  coalesce((select sum(amount) from public.motor_payments, b where site_id = p_sid and not voided and method = 'cash' and created_at >= b.f and created_at < b.t), 0),
    'whish_in', coalesce((select sum(amount) from public.motor_payments, b where site_id = p_sid and not voided and method = 'whish' and created_at >= b.f and created_at < b.t), 0),
    'receipts_n', (select count(*) from public.motor_payments, b where site_id = p_sid and not voided and created_at >= b.f and created_at < b.t),
    'expenses', coalesce((select sum(amount) from public.motor_moves, b where site_id = p_sid and extra->>'type' = 'expense' and created_at >= b.f and created_at < b.t), 0),
    'salaries', coalesce((select sum(amount) from public.motor_moves, b where site_id = p_sid and extra->>'type' = 'salary' and created_at >= b.f and created_at < b.t), 0),
    'cash_out', coalesce((select sum(amount) from public.motor_moves, b where site_id = p_sid and account = 'cash' and kind in ('out','close') and created_at >= b.f and created_at < b.t), 0),
    'whish_out', coalesce((select sum(abs(amount)) from public.motor_moves, b where site_id = p_sid and account = 'whish' and kind = 'withdraw' and created_at >= b.f and created_at < b.t), 0),
    'handovers', coalesce((select sum(amount) from public.motor_moves, b where site_id = p_sid and account = 'collector' and kind = 'handover' and created_at >= b.f and created_at < b.t), 0),
    'cash_box_end', public._motor_cash_bal(p_sid, (select t from b)),
    'whish_end', public._motor_whish_bal(p_sid, (select t from b)),
    'collectors_hand', coalesce((select sum(p.amount) from public.motor_payments p join public.motor_staff s on s.id = p.staff_id, b
                                  where p.site_id = p_sid and not p.voided and p.method = 'cash' and s.role <> 'admin' and p.created_at < b.t), 0)
                     - coalesce((select sum(amount) from public.motor_moves, b where site_id = p_sid and account = 'collector' and created_at < b.t), 0));
$$;
revoke all on function public._motor_day_totals(uuid, date) from public, anon, authenticated;

create or replace function public.motor_journal(p_slug text, p_token text, p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; f date := coalesce(p_from, public._motor_today()); t date := coalesce(p_to, public._motor_today());
        ft timestamptz; tt timestamptz;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if t - f > 400 then perform public._motor_err('bad_period'); end if;
  ft := f::timestamp at time zone 'Asia/Beirut'; tt := (t + 1)::timestamp at time zone 'Asia/Beirut';
  return jsonb_build_object(
    'from', f, 'to', t, 'today', public._motor_today(),
    'cash_open', public._motor_cash_bal(sid, ft), 'whish_open', public._motor_whish_bal(sid, ft),
    'cash_close', public._motor_cash_bal(sid, tt), 'whish_close', public._motor_whish_bal(sid, tt),
    'closes', coalesce((select jsonb_agg(jsonb_build_object('day', c.day, 'totals', c.totals, 'by', c.closed_by, 'at', c.closed_at))
                         from public.motor_day_closes c where c.site_id = sid and c.day between f and t), '[]'::jsonb),
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', d::date, 'totals', public._motor_day_totals(sid, d::date)) order by d)
                       from generate_series(f, t, interval '1 day') d), '[]'::jsonb),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
        select jsonb_build_object('t','pay','at',p.created_at,'no',p.no,'account',p.method,'in',p.amount,'out',0,
               'label', c.name, 'code', c.code, 'staff', p.staff_name, 'paid_currency', p.paid_currency, 'paid_amount', p.paid_amount,
               'note', p.note) as x
          from public.motor_payments p join public.motor_customers c on c.id = p.customer_id
         where p.site_id = sid and not p.voided and p.created_at >= ft and p.created_at < tt
        union all
        select jsonb_build_object('t', coalesce(m.extra->>'type', m.kind), 'kind', m.kind, 'at', m.created_at, 'no', m.vno,
               'account', m.account,
               'in', case when (m.account = 'cash' and (m.kind = 'in' or (m.kind = 'adjust' and m.amount > 0)))
                            or (m.account = 'whish' and (m.kind = 'deposit' or (m.kind = 'adjust' and m.amount > 0)))
                            or (m.account = 'collector' and m.kind = 'handover') then abs(m.amount) else 0 end,
               'out', case when m.kind in ('out','close','withdraw') or (m.kind = 'adjust' and m.amount < 0) then abs(m.amount) else 0 end,
               'label', coalesce(nullif(m.category,''), case when m.account = 'collector' then (select name from public.motor_staff where id = m.staff_id) else '' end),
               'staff', m.by_name, 'note', m.note)
          from public.motor_moves m
         where m.site_id = sid and m.created_at >= ft and m.created_at < tt
      ) q), '[]'::jsonb));
end $$;

create or replace function public.motor_day_close(p_slug text, p_token text, p_day date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; tot jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_day is null or p_day > public._motor_today() then perform public._motor_err('bad_period'); end if;
  if exists (select 1 from public.motor_day_closes where site_id = sid and day = p_day) then perform public._motor_err('day_closed'); end if;
  tot := public._motor_day_totals(sid, p_day);
  insert into public.motor_day_closes (site_id, day, totals, closed_by) values (sid, p_day, tot, w->>'name');
  return jsonb_build_object('ok', true, 'totals', tot);
end $$;

-- إعادة فتح يوم مقفل (المدير الأساسي فقط)
create or replace function public.motor_day_reopen(p_slug text, p_token text, p_day date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  if not coalesce((w->>'is_main')::boolean,false) then perform public._motor_err('main_only'); end if;
  delete from public.motor_day_closes where site_id = (w->>'site_id')::uuid and day = p_day;
  return jsonb_build_object('ok', true);
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
-- المدير الأساسي لكل مؤسسة: مستخدم admin (أو أقدم مدير)
update public.motor_staff s set is_main = true
 where s.id = (select x.id from public.motor_staff x where x.site_id = s.site_id and x.role = 'admin'
               order by (lower(x.username) = 'admin') desc, x.created_at limit 1)
   and not exists (select 1 from public.motor_staff y where y.site_id = s.site_id and y.is_main);

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
    'motor_changes(text,text,timestamptz)',
    'motor_cash_statement(text,text,date,date)', 'motor_cash_close(text,text,numeric,numeric,text)',
    'motor_set_active(text,text,uuid,boolean,text,double precision,double precision)',
    'motor_note_add(text,text,uuid,text)', 'motor_ping(text,text,double precision,double precision,double precision)',
    'motor_staff_map(text,text)', 'motor_2fa_setup(text,text)', 'motor_2fa_enable(text,text,text)',
    'motor_2fa_disable(text,text,text,uuid)', 'motor_wa_outbox(text,text,integer)', 'motor_wa_mark(text,text,text,uuid)',
    'motor_reading_edit(text,text,uuid,numeric,text)', 'motor_customer_set_login(text,text,uuid,text,text)', 'motor_cust_me(text,text)',
    'motor_invoice_edit(text,text,uuid,numeric,text)', 'motor_payment_edit(text,text,uuid,numeric,text)',
    'motor_fill_barcodes(text,text)', 'motor_month_report(text,text,text)', 'motor_backup(text,text)',
    'motor_trash_list(text,text)', 'motor_trash_restore(text,text,uuid)', 'motor_trash_purge(text,text,uuid)',
    'motor_set_prev(text,text,uuid,numeric)', 'motor_set_prev_bulk(text,text,jsonb)',
    'motor_login(text,text,text,text,text,text)', 'motor_device_reset(text,text,uuid)',
    'motor_expense_add(text,text,text,text,numeric,text)', 'motor_vouchers(text,text,text,date,date)',
    'motor_salary_pay(text,text,uuid,numeric,text,text,text)', 'motor_salaries(text,text,text)',
    'motor_stock_list(text,text)', 'motor_stock_save(text,text,jsonb)', 'motor_stock_delete(text,text,uuid)',
    'motor_journal(text,text,date,date)', 'motor_day_close(text,text,date)', 'motor_day_reopen(text,text,date)']
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
