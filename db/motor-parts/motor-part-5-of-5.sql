-- motorapp — الجزء 5 من 5 (شغّل الأجزاء بالترتيب)
-- ============================================================
--  20h4) المعاشات: إضافة قيمة المعاش (استحقاق) + كشف حساب الموظف
-- ============================================================
create or replace function public.motor_staff_salary_set(p_slug text, p_token text, p_staff uuid, p_amount numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  if coalesce(p_amount,-1) < 0 then perform public._motor_err('bad_amount'); end if;
  update public.motor_staff set salary = p_amount where id = p_staff and site_id = (w->>'site_id')::uuid;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.motor_salary_due_add(p_slug text, p_token text, p_staff uuid, p_period text, p_amount numeric, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not exists (select 1 from public.motor_staff where id = p_staff and site_id = sid) then perform public._motor_err('bad_staff'); end if;
  if coalesce(p_period,'') !~ '^\d{4}-\d{2}$' then perform public._motor_err('bad_period'); end if;
  if coalesce(p_amount,0) = 0 then perform public._motor_err('bad_amount'); end if;
  insert into public.motor_salary_dues (site_id, staff_id, period, amount, note, by_name)
  values (sid, p_staff, p_period, p_amount, coalesce(p_note,''), w->>'name');
  return jsonb_build_object('ok', true);
end $$;

-- إضافة معاش الشهر لكل الموظفين اللي إلهم معاش ولسّا ما انضاف إلهم بهالشهر
create or replace function public.motor_salary_due_all(p_slug text, p_token text, p_period text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; n int;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(p_period,'') !~ '^\d{4}-\d{2}$' then perform public._motor_err('bad_period'); end if;
  insert into public.motor_salary_dues (site_id, staff_id, period, amount, note, by_name)
  select sid, s.id, p_period, s.salary, 'معاش ' || p_period, w->>'name' from public.motor_staff s
   where s.site_id = sid and s.is_active and s.salary > 0
     and not exists (select 1 from public.motor_salary_dues d where d.staff_id = s.id and d.period = p_period);
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'count', n);
end $$;

create or replace function public.motor_salary_due_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  delete from public.motor_salary_dues where id = p_id and site_id = (w->>'site_id')::uuid;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.motor_staff_statement(p_slug text, p_token text, p_staff uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sf public.motor_staff%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into sf from public.motor_staff where id = p_staff and site_id = sid;
  if not found then perform public._motor_err('bad_staff'); end if;
  return jsonb_build_object('staff', jsonb_build_object('id', sf.id, 'name', sf.name, 'salary', sf.salary, 'phone', sf.phone),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
       select jsonb_build_object('t','due','id',d.id,'at',d.created_at,'period',d.period,'amount',d.amount,'note',d.note,'by',d.by_name) x
         from public.motor_salary_dues d where d.staff_id = sf.id
       union all
       select jsonb_build_object('t','pay','id',m.id,'at',m.created_at,'period',m.period,'vno',m.vno,'amount',m.amount,'account',m.account,'note',m.note,'by',m.by_name)
         from public.motor_moves m where m.pay_staff = sf.id and m.extra->>'type' = 'salary') q), '[]'::jsonb));
end $$;

-- ============================================================
--  20j) استيراد فواتير البرنامج السابق (Excel): كل سطر = فاتورة
--  p_data = [{customer_id, area, balance, rows:[{date:'YYYY-MM-DD', prev, cur, total, plan}]}]
--  الشهر: تاريخ الفاتورة 1–14 = الشهر اللي قبل (02/06 → أيار)، 15 وما فوق = نفس الشهر (فاتورة نص شهر)
--  الرصيد بعد الاستيراد = «رصيد الحساب الحالي» بالملف بالضبط (الفرق بيروح على سطر الرصيد السابق)
-- ============================================================
-- «دفعات مسددة في البرنامج السابق»: منوزّعها شهر بشهر — كل فاتورة (من الأقدم) بتنسدّ بالشهر يلّي بعدها
-- هيك الكشف الشهري بيطلع رصيد كل شهر منطقي بدل ما ينجمعو كل الدفعات القديمة بآخر شهر
create or replace function public._motor_spread_old_payments(p_cust uuid)
returns void language plpgsql security definer set search_path = public as $$
declare cred numeric; r record; part numeric; tp text; maxp text; cap text; sid uuid; seq int; x record;
begin
  select coalesce(-sum(amount),0), (array_agg(site_id))[1] into cred, sid from public.motor_invoices
   where customer_id = p_cust and imported and kind = 'adjust' and not voided and amount < 0;
  if cred <= 0 then return; end if;
  delete from public.motor_invoices where customer_id = p_cust and imported and kind = 'adjust' and amount < 0;
  select max(period) into maxp from public.motor_invoices where customer_id = p_cust and imported and kind in ('meter','fixed');
  cap := to_char((now() at time zone 'Asia/Beirut')::date, 'YYYY-MM');
  create temp table if not exists _spread (per text, amt numeric) on commit drop; truncate _spread;
  for r in select i.kind, i.period, i.amount, i.created_at from public.motor_invoices i
            where i.customer_id = p_cust and not i.voided and i.amount > 0 and (i.kind = 'opening' or (i.imported and i.kind in ('meter','fixed')))
            order by (i.kind = 'opening') desc, i.period, i.created_at loop
    exit when cred <= 0.004;
    part := least(cred, r.amount);
    tp := case when r.kind = 'opening' or r.period = '' then
                 coalesce((select min(period) from public.motor_invoices where customer_id = p_cust and imported and kind in ('meter','fixed')), cap)
               else to_char((r.period || '-01')::date + interval '1 month', 'YYYY-MM') end;
    if tp > cap then tp := cap; end if;
    insert into _spread values (tp, part); cred := cred - part;
  end loop;
  if cred > 0.004 then insert into _spread values (least(coalesce(maxp, cap), cap), cred); end if;
  for x in select per, sum(amt) amt from _spread group by per order by per loop
    update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
    insert into public.motor_invoices (site_id, no, customer_id, period, kind, amount, note, staff_name, imported, wa_sent_at, created_at)
    values (sid, seq, p_cust, x.per, 'adjust', -x.amt, 'دفعات مسددة في البرنامج السابق', 'استيراد', true, now(),
            least(((x.per || '-01')::timestamp + interval '1 day') at time zone 'Asia/Beirut', now()));
  end loop;
end $$;
revoke all on function public._motor_spread_old_payments(uuid) from public, anon, authenticated;

create or replace function public.motor_import_invoices(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; cu jsonb; c public.motor_customers%rowtype;
        seq int; rid uuid; first_d date; bal numeric; op numeric;
        n_inv int := 0; n_read int := 0; n_skip int := 0; n_cust int := 0; n_bal int := 0; r record; run numeric;
        best jsonb; grp record; oid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if jsonb_typeof(p_data) <> 'array' then perform public._motor_err('bad_data'); end if;
  perform 1 from public.motor_sites where id = sid for update;
  for cu in select * from jsonb_array_elements(p_data) loop
    select * into c from public.motor_customers where id = (cu->>'customer_id')::uuid and site_id = sid and deleted_at is null for update;
    if not found then continue; end if;
    n_cust := n_cust + 1;
    -- إعادة الاستيراد: امسح يلّي انستورد قبل لهالزبون
    delete from public.motor_invoices where customer_id = c.id and imported;
    delete from public.motor_readings where customer_id = c.id and imported;
    first_d := null;
    -- كل سطر مع شهرو
    create temp table if not exists _imp (ord int, d date, per text, prevv numeric, curv numeric, tot numeric, plan text) on commit drop;
    truncate _imp;
    insert into _imp
    select x.ordinality, (x.value->>'date')::date,
           to_char(case when extract(day from (x.value->>'date')::date) >= 15 then (x.value->>'date')::date
                        else ((x.value->>'date')::date - interval '1 month')::date end, 'YYYY-MM'),
           nullif(x.value->>'prev','')::numeric, nullif(x.value->>'cur','')::numeric,
           coalesce(nullif(x.value->>'total','')::numeric, 0), coalesce(x.value->>'plan','')
      from jsonb_array_elements(cu->'rows') with ordinality x
     where coalesce(x.value->>'date','') ~ '^\d{4}-\d{2}-\d{2}$';
    -- شهر فيه قراءة حقيقية من البرنامج: ما منلمسو
    delete from _imp i where exists (select 1 from public.motor_readings rr where rr.customer_id = c.id and rr.period = i.per and not rr.imported);
    get diagnostics seq = row_count; n_skip := n_skip + seq;
    for grp in select per, max(d) md from _imp group by per loop
      rid := null;
      -- القراءة = آخر سطر بالشهر (إذا في عداد حالي)
      select * into r from _imp where per = grp.per order by d desc, ord desc limit 1;
      if r.curv is not null then
        insert into public.motor_readings (site_id, customer_id, period, prev_value, value, staff_name, imported, created_at)
        values (sid, c.id, grp.per, coalesce(r.prevv, 0), r.curv, 'استيراد', true, (r.d::timestamp + interval '12 hours') at time zone 'Asia/Beirut')
        returning id into rid;
        n_read := n_read + 1;
      end if;
      for r in select * from _imp where per = grp.per order by d, ord loop
        update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
        insert into public.motor_invoices (site_id, no, customer_id, period, kind, reading_id, plan_name, prev_value, cur_value, kwh,
               amount, note, staff_name, imported, wa_sent_at, created_at)
        values (sid, seq, c.id, r.per, case when r.curv is null then 'fixed' else 'meter' end,
                case when r.d = grp.md then rid end, r.plan,
                case when r.curv is not null then coalesce(r.prevv, 0) end, r.curv,
                case when r.curv is not null then greatest(r.curv - coalesce(r.prevv, 0), 0) else 0 end,
                r.tot, 'مستوردة من البرنامج السابق', 'استيراد', true, now(), (r.d::timestamp + interval '12 hours') at time zone 'Asia/Beirut');
        n_inv := n_inv + 1;
      end loop;
    end loop;
    select min(d) into first_d from _imp;
    -- مطابقة الرصيد مع «رصيد الحساب الحالي»
    if nullif(cu->>'balance','') is not null then
      bal := (cu->>'balance')::numeric;
      op := bal - coalesce((select sum(amount) from public.motor_invoices where customer_id = c.id and not voided and kind <> 'opening'), 0)
                + coalesce((select sum(amount) from public.motor_payments where customer_id = c.id and not voided), 0);
      select id into oid from public.motor_invoices where customer_id = c.id and kind = 'opening' and not voided order by created_at limit 1;
      delete from public.motor_invoices where customer_id = c.id and kind = 'opening' and not voided and id is distinct from oid;
      -- الفرق بالسالب = دفعات انقبضت بالبرنامج السابق → سطر «له» بعد آخر فاتورة مستوردة
      if op < 0 then
        if oid is not null then delete from public.motor_invoices where id = oid; oid := null; end if;
        update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
        insert into public.motor_invoices (site_id, no, customer_id, period, kind, amount, note, staff_name, imported, created_at)
        values (sid, seq, c.id, coalesce((select max(per) from _imp), ''), 'adjust', op, 'دفعات مسددة في البرنامج السابق', 'استيراد', true,
                coalesce(((select max(d) from _imp)::timestamp + interval '13 hours') at time zone 'Asia/Beirut', now()));
        op := 0;
        perform public._motor_spread_old_payments(c.id);
      end if;
      if oid is null and op <> 0 then
        update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
        insert into public.motor_invoices (site_id, no, customer_id, kind, amount, note, staff_name)
        values (sid, seq, c.id, 'opening', op, '', w->>'name') returning id into oid;
      end if;
      if oid is not null then
        if op = 0 then delete from public.motor_invoices where id = oid;
        else
          update public.motor_invoices set amount = op, note = 'رصيد سابق (مطابقة مع البرنامج السابق)',
                 created_at = coalesce(((first_d - 1)::timestamp + interval '12 hours') at time zone 'Asia/Beirut', created_at)
           where id = oid;
        end if;
      end if;
      n_bal := n_bal + 1;
    end if;
    -- الرصيد الجاري لكل فاتورة (للطباعة)
    run := 0;
    for r in select 'i' t, i.id, i.amount, i.created_at from public.motor_invoices i where i.customer_id = c.id and not i.voided
             union all select 'p', p.id, -p.amount, p.created_at from public.motor_payments p where p.customer_id = c.id and not p.voided
             order by 4, 1 loop
      if r.t = 'i' then
        update public.motor_invoices set balance_before = run, balance_after = run + r.amount where id = r.id and (imported or kind = 'opening');
      end if;
      run := run + r.amount;
    end loop;
    update public.motor_customers set balance = run,
           area = coalesce(nullif(trim(coalesce(cu->>'area','')), ''), area),
           next_prev = case when exists (select 1 from public.motor_readings where customer_id = c.id and imported) then null else next_prev end,
           updated_at = now()
     where id = c.id;
  end loop;
  return jsonb_build_object('ok', true, 'customers', n_cust, 'invoices', n_inv, 'readings', n_read, 'skipped', n_skip, 'balanced', n_bal);
end $$;

-- ============================================================
--  20j2) تصحيح الحسابات من «كشف حساب» البرنامج السابق (Excel)
--  لكل زبون: بيمسح يلّي انستورد من بعد تاريخ بداية الكشف ودفعات «البرنامج السابق» والرصيد السابق،
--  وبيرجع يبني الحركات متل الكشف بالظبط: فاتورة كل شهر بشهرها وتاريخها، الدفعات بتاريخها ورقم الإيصال،
--  الرسوم الإضافية (كونتكتير، تركيب...)، وكل شي قبل بداية الكشف بسطر «رصيد سابق».
--  الرصيد النهائي = رصيد الكشف − الدفعات يلّي انقبضت بهالبرنامج وما مسجّلة بالكشف.
-- ============================================================
create or replace function public.motor_import_statement(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; cu jsonb; x jsonb; c public.motor_customers%rowtype;
        f date; seq int; kept numeric; op numeric; pre_cr numeric; sdr numeric; scr numeric; run numeric; old numeric;
        amt numeric; per text; ts timestamptz; rid uuid; pid uuid; r record; v_kind text; skip_bill boolean;
        n_cust int := 0; n_rows int := 0; n_dup int := 0; n_app int := 0; changed jsonb := '[]'::jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if jsonb_typeof(p_data) <> 'array' then perform public._motor_err('bad_data'); end if;
  perform 1 from public.motor_sites where id = sid for update;
  create temp table if not exists _used_pay (id uuid primary key) on commit drop;
  for cu in select * from jsonb_array_elements(p_data) loop
    select * into c from public.motor_customers where id = (cu->>'customer_id')::uuid and site_id = sid and deleted_at is null for update;
    if not found then continue; end if;
    n_cust := n_cust + 1; old := c.balance;
    f := coalesce(nullif(cu->>'from','')::date, date '2026-05-11');
    -- امسح: المستورد من بعد بداية الكشف + كل تسويات الاستيراد + الرصيد السابق
    delete from public.motor_invoices
     where customer_id = c.id and (kind = 'opening'
        or (imported and kind = 'adjust')
        or (imported and (created_at at time zone 'Asia/Beirut')::date >= f));
    -- الفواتير المستوردة قبل بداية الكشف بتضل (فيها العدادات) والفرق بيصير «رصيد سابق»
    select coalesce(sum(amount), 0) into kept from public.motor_invoices
     where customer_id = c.id and imported and not voided and kind in ('meter','fixed');
    select coalesce(sum((v->>'dr')::numeric), 0), coalesce(sum((v->>'cr')::numeric), 0) into sdr, scr
      from jsonb_array_elements(cu->'rows') v;
    -- قبل بداية الكشف: فواتير (ناقص يلّي باقي مستورد) + دفعات. رصيد الكشف النهائي هو المرجع (فروقات التقريب).
    op := round(((cu->>'tdr')::numeric - sdr) - kept
                + (coalesce(nullif(cu->>'tb','')::numeric, (cu->>'tdr')::numeric - (cu->>'tcr')::numeric) - ((cu->>'tdr')::numeric - (cu->>'tcr')::numeric)), 2);
    pre_cr := round((cu->>'tcr')::numeric - scr, 2);
    if op <> 0 then
      update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
      insert into public.motor_invoices (site_id, no, customer_id, period, kind, amount, note, staff_name, imported, wa_sent_at, created_at)
      values (sid, seq, c.id, to_char(f - interval '1 month', 'YYYY-MM'), 'opening', op, 'رصيد ما قبل ' || to_char(f, 'YYYY/MM/DD') || ' (حسب كشف البرنامج السابق)',
              'استيراد', true, now(), ((f - 1)::timestamp + interval '11 hours') at time zone 'Asia/Beirut');
    end if;
    if pre_cr <> 0 then
      update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
      insert into public.motor_invoices (site_id, no, customer_id, period, kind, amount, note, staff_name, imported, wa_sent_at, created_at)
      values (sid, seq, c.id, to_char(f - interval '1 month', 'YYYY-MM'), 'adjust', -pre_cr, 'دفعات قبل ' || to_char(f, 'YYYY/MM/DD') || ' (حسب كشف البرنامج السابق)',
              'استيراد', true, now(), ((f - 1)::timestamp + interval '12 hours') at time zone 'Asia/Beirut');
    end if;
    truncate _used_pay;
    for x in select * from jsonb_array_elements(cu->'rows') loop
      amt := round(coalesce((x->>'dr')::numeric, 0) - coalesce((x->>'cr')::numeric, 0), 2);
      if amt = 0 then continue; end if;
      ts := (x->>'d')::timestamp;
      if ts::time = time '00:00' then ts := ts + interval '12 hours'; end if;
      ts := ts at time zone 'Asia/Beirut';
      per := coalesce(nullif(x->>'per',''), to_char((x->>'d')::timestamp, 'YYYY-MM'));
      if x->>'k' = 'pay' then
        -- دفعة انسجلت بالكشف وكمان انقبضت بهالبرنامج (نفس المبلغ، خلال 4 أيام): منكتفي بإيصال البرنامج
        select p.id into pid from public.motor_payments p
         where p.customer_id = c.id and not p.voided and p.amount = -amt
           and p.created_at >= ts - interval '1 hour' and p.created_at < ts + interval '4 days'
           and not exists (select 1 from _used_pay u where u.id = p.id)
         order by p.created_at limit 1;
        if pid is not null then insert into _used_pay values (pid); n_dup := n_dup + 1; continue; end if;
      end if;
      v_kind := 'adjust'; rid := null; skip_bill := false;
      if x->>'k' = 'bill' and amt > 0 then
        -- شهر انقرا بهالبرنامج: فاتورتو موجودة، ما منكررها
        if exists (select 1 from public.motor_invoices i where i.customer_id = c.id and not i.voided and not i.imported
                    and i.kind in ('meter','fixed') and i.period = per) then
          n_app := n_app + 1; continue;
        end if;
        select rr.id into rid from public.motor_readings rr where rr.customer_id = c.id and rr.period = per and rr.imported
           and not exists (select 1 from public.motor_invoices i where i.reading_id = rr.id) limit 1;
        v_kind := case when rid is null then 'fixed' else 'meter' end;
      end if;
      update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
      insert into public.motor_invoices (site_id, no, customer_id, period, kind, reading_id, plan_name, prev_value, cur_value, kwh,
             amount, note, staff_name, imported, wa_sent_at, created_at)
      select sid, seq, c.id, per, v_kind, rid, coalesce(x->>'svc',''), rr.prev_value, rr.value,
             coalesce(rr.value - rr.prev_value, 0), amt, left(coalesce(x->>'desc',''), 300), 'استيراد', true, now(), ts
        from (select 1) one left join public.motor_readings rr on rr.id = rid;
      n_rows := n_rows + 1;
    end loop;
    -- الرصيد الجاري لكل حركة (للطباعة) + رصيد الزبون
    run := 0;
    for r in select 'i' t, i.id, i.amount, i.created_at from public.motor_invoices i where i.customer_id = c.id and not i.voided
             union all select 'p', p.id, -p.amount, p.created_at from public.motor_payments p where p.customer_id = c.id and not p.voided
             order by 4, 1 loop
      if r.t = 'i' then
        update public.motor_invoices set balance_before = run, balance_after = run + r.amount where id = r.id and (imported or kind = 'opening');
      end if;
      run := run + r.amount;
    end loop;
    update public.motor_customers set balance = run, updated_at = now() where id = c.id;
    if run <> old then
      changed := changed || jsonb_build_array(jsonb_build_object('code', c.code, 'name', c.name, 'old', old, 'new', run));
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'customers', n_cust, 'rows', n_rows, 'dup_pays', n_dup, 'app_bills', n_app, 'changed', changed);
end $$;

-- ============================================================
--  20k) إقفال صندوق الموظف: يسلّم كل النقد للمكتب ويطلع تقرير
-- ============================================================
create or replace function public.motor_staff_close(p_slug text, p_token text, p_staff uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sf public.motor_staff%rowtype; since timestamptz; hand numeric; rep jsonb; m public.motor_moves%rowtype; nowt timestamptz := clock_timestamp();
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_staff is not null and p_staff::text is distinct from w->>'staff_id' and not (w->>'is_admin')::boolean then perform public._motor_err('forbidden'); end if;
  select * into sf from public.motor_staff where id = coalesce(p_staff, (w->>'staff_id')::uuid) and site_id = sid;
  if not found then perform public._motor_err('bad_staff'); end if;
  perform 1 from public.motor_staff where id = sf.id for update;
  since := coalesce((select max(created_at) from public.motor_moves where staff_id = sf.id and account = 'collector' and extra->>'type' = 'staff_close'),
                    '-infinity'::timestamptz);
  hand := coalesce((select sum(amount) from public.motor_payments where staff_id = sf.id and method = 'cash' and not voided), 0)
        - coalesce((select sum(amount) from public.motor_moves where staff_id = sf.id and account = 'collector'), 0);
  rep := jsonb_build_object(
    'staff', sf.name, 'from', case when since = '-infinity'::timestamptz then null else since end, 'to', nowt, 'by', w->>'name',
    'cash', coalesce((select sum(amount) from public.motor_payments where staff_id = sf.id and method = 'cash' and not voided and created_at > since), 0),
    'whish', coalesce((select sum(amount) from public.motor_payments where staff_id = sf.id and method = 'whish' and not voided and created_at > since), 0),
    'count', (select count(*) from public.motor_payments where staff_id = sf.id and not voided and created_at > since),
    'readings', (select count(*) from public.motor_readings where staff_id = sf.id and created_at > since),
    'handed_before', coalesce((select sum(amount) from public.motor_moves where staff_id = sf.id and account = 'collector' and created_at > since), 0),
    'handed', hand,
    'rows', coalesce((select jsonb_agg(jsonb_build_object('no', p.no, 'at', p.created_at, 'customer', c.name, 'code', c.code, 'method', p.method,
               'amount', p.amount, 'paid_currency', p.paid_currency, 'paid_amount', p.paid_amount) order by p.created_at)
             from public.motor_payments p join public.motor_customers c on c.id = p.customer_id
            where p.staff_id = sf.id and not p.voided and p.created_at > since), '[]'::jsonb));
  insert into public.motor_moves (site_id, account, staff_id, kind, amount, note, by_name, extra, created_at)
  values (sid, 'collector', sf.id, 'handover', hand, 'إقفال صندوق ' || sf.name, w->>'name', rep || jsonb_build_object('type','staff_close'), nowt)
  returning * into m;
  return rep || jsonb_build_object('id', m.id);
end $$;

create or replace function public.motor_staff_closes(p_slug text, p_token text, p_staff uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; st uuid;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  st := case when (w->>'is_admin')::boolean then p_staff else (w->>'staff_id')::uuid end;
  return coalesce((select jsonb_agg((m.extra - 'type') || jsonb_build_object('id', m.id, 'at', m.created_at) order by m.created_at desc)
    from (select * from public.motor_moves where site_id = sid and account = 'collector' and extra->>'type' = 'staff_close'
            and (st is null or staff_id = st) order by created_at desc limit 40) m), '[]'::jsonb);
end $$;

-- ============================================================
--  20l) التأمينات: قبض تأمين / إعادة تأمين (من الصندوق أو Whish) + استيراد Excel
-- ============================================================
create or replace function public.motor_ins_list(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return jsonb_build_object(
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'at', i.created_at, 'customer_id', i.customer_id,
              'name', coalesce(c.name, i.name), 'code', c.code, 'kind', i.kind, 'amount', i.amount, 'account', i.account, 'ref_no', i.ref_no,
              'service', i.service, 'note', i.note, 'by', i.by_name, 'imported', i.imported) order by i.created_at)
            from public.motor_insurance i left join public.motor_customers c on c.id = i.customer_id where i.site_id = sid), '[]'::jsonb));
end $$;

create or replace function public.motor_ins_add(p_slug text, p_token text, p_customer uuid, p_kind text, p_amount numeric,
  p_account text, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype; m public.motor_moves%rowtype; x public.motor_insurance%rowtype; seq int;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into c from public.motor_customers where id = p_customer and site_id = sid;
  if not found then perform public._motor_err('customer_not_found'); end if;
  if p_kind not in ('in','out') then perform public._motor_err('bad_kind'); end if;
  if p_account not in ('cash','whish') then perform public._motor_err('bad_account'); end if;
  if coalesce(p_amount,0) <= 0 then perform public._motor_err('bad_amount'); end if;
  if p_kind = 'out' then
    m := public._motor_voucher(sid, w, p_account, p_amount, 'إعادة تأمين ' || c.name, p_note, 'insurance', null, '');
  else
    insert into public.motor_moves (site_id, account, kind, amount, note, by_name, category, extra)
    values (sid, p_account, case when p_account = 'cash' then 'in' else 'deposit' end, abs(p_amount), coalesce(p_note,''), w->>'name',
            'تأمين ' || c.name, jsonb_build_object('type','insurance'))
    returning * into m;
  end if;
  insert into public.motor_insurance (site_id, customer_id, name, kind, amount, account, ref_no, service, note, move_id, by_name)
  values (sid, c.id, c.name, p_kind, abs(p_amount), p_account, coalesce(m.vno::text,''), coalesce((select name from public.motor_plans where id = c.plan_id),''),
          coalesce(p_note,''), m.id, w->>'name')
  returning * into x;
  return jsonb_build_object('ok', true, 'row', to_jsonb(x) - 'site_id', 'vno', m.vno,
    'balance', coalesce((select sum(case when kind = 'in' then amount else -amount end) from public.motor_insurance where customer_id = c.id), 0));
end $$;

create or replace function public.motor_ins_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; x public.motor_insurance%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into x from public.motor_insurance where id = p_id and site_id = sid;
  if not found then perform public._motor_err('not_found'); end if;
  if x.move_id is not null then
    if exists (select 1 from public.motor_moves m join public.motor_day_closes dc on dc.site_id = m.site_id
                and dc.day = (m.created_at at time zone 'Asia/Beirut')::date where m.id = x.move_id) then perform public._motor_err('day_closed'); end if;
    delete from public.motor_moves where id = x.move_id;
  end if;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  values (sid, 'insurance', x.id, x.name || ' · ' || x.amount, to_jsonb(x), w->>'name');
  delete from public.motor_insurance where id = x.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.motor_ins_link(p_slug text, p_token text, p_name text, p_customer uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype; n int;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into c from public.motor_customers where id = p_customer and site_id = sid;
  if not found then perform public._motor_err('customer_not_found'); end if;
  update public.motor_insurance set customer_id = c.id, name = c.name where site_id = sid and customer_id is null and name = p_name;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'count', n);
end $$;

-- p_rows = [{at:'YYYY-MM-DD HH:MI', kind:'in'|'out', amount, ref_no, service, note, name, customer_id}] — بيستبدل المستورد قبل
create or replace function public.motor_ins_import(p_slug text, p_token text, p_rows jsonb, p_replace boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; n int;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_replace then delete from public.motor_insurance where site_id = sid and imported; end if;
  insert into public.motor_insurance (site_id, customer_id, name, kind, amount, account, ref_no, service, note, by_name, imported, created_at)
  select sid, (select id from public.motor_customers c where c.id::text = x->>'customer_id' and c.site_id = sid),
         coalesce(x->>'name',''), x->>'kind', abs((x->>'amount')::numeric), '', coalesce(x->>'ref_no',''), coalesce(x->>'service',''),
         coalesce(x->>'note',''), 'استيراد', true, ((x->>'at')::timestamp) at time zone 'Asia/Beirut'
    from jsonb_array_elements(p_rows) x
   where x->>'kind' in ('in','out') and coalesce(nullif(x->>'amount','')::numeric, 0) <> 0;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'count', n);
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
    'suppliers', coalesce((select sum(amount) from public.motor_moves, b where site_id = p_sid and extra->>'type' = 'supplier' and created_at >= b.f and created_at < b.t), 0),
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
-- الاستيراد القديم: «دفعات مسددة في البرنامج السابق» كانت سطر واحد بلا شهر → منوزّعها على الأشهر
do $$ declare r record; begin
  for r in select distinct customer_id from public.motor_invoices where imported and kind = 'adjust' and period = '' and amount < 0 loop
    perform public._motor_spread_old_payments(r.customer_id);
  end loop;
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
    'motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision,boolean)',
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
    'motor_journal(text,text,date,date)', 'motor_day_close(text,text,date)', 'motor_day_reopen(text,text,date)',
    'motor_stock_out(text,text,uuid,numeric,uuid,text,text)', 'motor_stock_moves_list(text,text,uuid,date,date)',
    'motor_suppliers(text,text)', 'motor_supplier_save(text,text,jsonb)', 'motor_supplier_delete(text,text,uuid)',
    'motor_purchase_add(text,text,jsonb)', 'motor_purchase_void(text,text,uuid)', 'motor_supplier_pay(text,text,uuid,numeric,text,text)',
    'motor_supplier_statement(text,text,uuid)', 'motor_staff_salary_set(text,text,uuid,numeric)', 'motor_salary_due_add(text,text,uuid,text,numeric,text)',
    'motor_salary_due_all(text,text,text)', 'motor_salary_due_delete(text,text,uuid)', 'motor_staff_statement(text,text,uuid)',
    'motor_import_invoices(text,text,jsonb)', 'motor_import_statement(text,text,jsonb)', 'motor_impersonate(text,text,uuid)', 'motor_staff_close(text,text,uuid)', 'motor_staff_closes(text,text,uuid)',
    'motor_ins_list(text,text)', 'motor_ins_add(text,text,uuid,text,numeric,text,text)', 'motor_ins_delete(text,text,uuid)',
    'motor_ins_import(text,text,jsonb,boolean)', 'motor_ins_link(text,text,text,uuid)']
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
union all select 'read function', to_regprocedure('public.motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision,boolean)') is not null;
