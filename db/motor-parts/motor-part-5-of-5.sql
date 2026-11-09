-- motorapp — الجزء 5 من 5 (شغّل الأجزاء بالترتيب)
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
    if x.qty <> 0 then
      insert into public.motor_stock_moves (site_id, item_id, item_name, kind, qty, unit_price, note, by_name)
      values (sid, x.id, x.name, 'adjust', x.qty, x.unit_price, 'رصيد أول', w->>'name');
    end if;
  else
    insert into public.motor_stock_moves (site_id, item_id, item_name, kind, qty, unit_price, note, by_name)
    select sid, o.id, trim(d->>'name'), 'adjust', coalesce(nullif(d->>'qty','')::numeric,0) - o.qty, o.unit_price, 'تعديل يدوي', w->>'name'
      from public.motor_stock o where o.id = (d->>'id')::uuid and o.site_id = sid and o.qty <> coalesce(nullif(d->>'qty','')::numeric,0);
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
--  20h2) سحب من المخزون (لازم مين سحب) + سجل حركات المخزون
-- ============================================================
create or replace function public.motor_stock_out(p_slug text, p_token text, p_item uuid, p_qty numeric,
  p_staff uuid default null, p_taker text default '', p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; x public.motor_stock%rowtype; who text;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(p_qty,0) <= 0 then perform public._motor_err('bad_amount'); end if;
  select name into who from public.motor_staff where id = p_staff and site_id = sid;
  who := coalesce(nullif(trim(coalesce(who,'')),''), nullif(trim(coalesce(p_taker,'')),''));
  if who is null then perform public._motor_err('taker_required'); end if;
  select * into x from public.motor_stock where id = p_item and site_id = sid for update;
  if not found then perform public._motor_err('not_found'); end if;
  if x.qty < p_qty then perform public._motor_err('stock_low', x.qty::text); end if;
  update public.motor_stock set qty = qty - p_qty, updated_by = w->>'name', updated_at = now() where id = x.id returning * into x;
  insert into public.motor_stock_moves (site_id, item_id, item_name, kind, qty, unit_price, taker, staff_id, note, by_name)
  values (sid, x.id, x.name, 'out', -p_qty, x.unit_price, who, p_staff, coalesce(p_note,''), w->>'name');
  return to_jsonb(x) - 'site_id';
end $$;

create or replace function public.motor_stock_moves_list(p_slug text, p_token text, p_item uuid default null, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'at', m.created_at, 'item_id', m.item_id, 'item', m.item_name, 'kind', m.kind,
           'qty', m.qty, 'unit_price', m.unit_price, 'taker', m.taker, 'note', m.note, 'by', m.by_name,
           'purchase_no', (select p.no from public.motor_purchases p where p.id = m.purchase_id)) order by m.created_at desc)
         from public.motor_stock_moves m where m.site_id = sid and (p_item is null or m.item_id = p_item)
          and (m.created_at at time zone 'Asia/Beirut')::date between coalesce(p_from, date '2000-01-01') and coalesce(p_to, date '2999-12-31')), '[]'::jsonb);
end $$;

-- ============================================================
--  20h3) الموردون، فواتير المشتريات، الدفعات (سند صرف من الصندوق أو Whish)
-- ============================================================
create or replace function public._motor_sup_bal(p_sup uuid)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select sum(total) from public.motor_purchases where supplier_id = p_sup and not voided), 0)
       - coalesce((select sum(amount) from public.motor_moves where supplier_id = p_sup and extra->>'type' = 'supplier'), 0);
$$;
revoke all on function public._motor_sup_bal(uuid) from public, anon, authenticated;

create or replace function public.motor_suppliers(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'phone', s.phone, 'notes', s.notes,
           'purchases', coalesce((select sum(total) from public.motor_purchases where supplier_id = s.id and not voided), 0),
           'paid', coalesce((select sum(amount) from public.motor_moves where supplier_id = s.id and extra->>'type' = 'supplier'), 0),
           'balance', public._motor_sup_bal(s.id),
           'count', (select count(*) from public.motor_purchases where supplier_id = s.id and not voided)) order by s.name)
         from public.motor_suppliers s where s.site_id = sid), '[]'::jsonb);
end $$;

create or replace function public.motor_supplier_save(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; d jsonb := coalesce(p_data,'{}'::jsonb); x public.motor_suppliers%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(trim(d->>'name'),'') = '' then perform public._motor_err('name_required'); end if;
  if coalesce(d->>'id','') = '' then
    insert into public.motor_suppliers (site_id, name, phone, notes) values (sid, trim(d->>'name'), coalesce(d->>'phone',''), coalesce(d->>'notes',''))
    returning * into x;
  else
    update public.motor_suppliers set name = trim(d->>'name'), phone = coalesce(d->>'phone',''), notes = coalesce(d->>'notes','')
     where id = (d->>'id')::uuid and site_id = sid returning * into x;
    if x.id is null then perform public._motor_err('not_found'); end if;
  end if;
  return to_jsonb(x) - 'site_id';
end $$;

create or replace function public.motor_supplier_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if exists (select 1 from public.motor_purchases where supplier_id = p_id and not voided)
     or exists (select 1 from public.motor_moves where supplier_id = p_id) then perform public._motor_err('has_history'); end if;
  delete from public.motor_purchases where supplier_id = p_id and site_id = sid;
  delete from public.motor_suppliers where id = p_id and site_id = sid;
  return jsonb_build_object('ok', true);
end $$;

-- فاتورة مشتريات: p_data = {supplier_id, ref, day, note, to_stock, items:[{item_id|name, category, qty, unit_price}], pay_amount, pay_account}
create or replace function public.motor_purchase_add(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; d jsonb := coalesce(p_data,'{}'::jsonb); sup public.motor_suppliers%rowtype; it jsonb; x public.motor_stock%rowtype;
        seq int; pid uuid; tot numeric := 0; items jsonb := '[]'::jsonb; q numeric; pr numeric; nm text; tostk boolean; m public.motor_moves%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into sup from public.motor_suppliers where id = (d->>'supplier_id')::uuid and site_id = sid;
  if not found then perform public._motor_err('not_found'); end if;
  if jsonb_typeof(d->'items') <> 'array' or jsonb_array_length(d->'items') = 0 then perform public._motor_err('no_items'); end if;
  tostk := coalesce((d->>'to_stock')::boolean, true);
  update public.motor_sites set purchase_seq = purchase_seq + 1 where id = sid returning purchase_seq into seq;
  pid := gen_random_uuid();
  for it in select * from jsonb_array_elements(d->'items') loop
    q := coalesce(nullif(it->>'qty','')::numeric, 0); pr := coalesce(nullif(it->>'unit_price','')::numeric, 0);
    nm := trim(coalesce(it->>'name',''));
    if q <= 0 then continue; end if;
    x := null;
    if coalesce(it->>'item_id','') <> '' then select * into x from public.motor_stock where id = (it->>'item_id')::uuid and site_id = sid; end if;
    if x.id is null and nm <> '' then select * into x from public.motor_stock where site_id = sid and lower(name) = lower(nm) limit 1; end if;
    if x.id is null and nm = '' then perform public._motor_err('name_required'); end if;
    if tostk then
      if x.id is null then
        insert into public.motor_stock (site_id, name, category, qty, unit_price, updated_by)
        values (sid, nm, coalesce(it->>'category',''), q, pr, w->>'name') returning * into x;
      else
        update public.motor_stock set qty = qty + q, unit_price = case when pr > 0 then pr else unit_price end,
               updated_by = w->>'name', updated_at = now() where id = x.id returning * into x;
      end if;
      insert into public.motor_stock_moves (site_id, item_id, item_name, kind, qty, unit_price, taker, purchase_id, note, by_name)
      values (sid, x.id, x.name, 'purchase', q, pr, sup.name, pid, coalesce(d->>'ref',''), w->>'name');
    end if;
    items := items || jsonb_build_array(jsonb_build_object('item_id', x.id, 'name', coalesce(x.name, nm), 'qty', q, 'unit_price', pr, 'total', round(q*pr, 2)));
    tot := tot + round(q*pr, 2);
  end loop;
  if jsonb_array_length(items) = 0 then perform public._motor_err('no_items'); end if;
  insert into public.motor_purchases (id, site_id, supplier_id, no, ref, day, items, total, to_stock, note, by_name)
  values (pid, sid, sup.id, seq, coalesce(d->>'ref',''), coalesce(nullif(d->>'day','')::date, public._motor_today()), items, tot, tostk,
          coalesce(d->>'note',''), w->>'name');
  if coalesce(nullif(d->>'pay_amount','')::numeric, 0) > 0 then
    m := public._motor_voucher(sid, w, coalesce(d->>'pay_account','cash'), (d->>'pay_amount')::numeric, 'دفعة للمورد ' || sup.name,
                               'فاتورة مشتريات #' || seq, 'supplier', null, '');
    update public.motor_moves set supplier_id = sup.id where id = m.id;
  end if;
  return jsonb_build_object('ok', true, 'no', seq, 'total', tot, 'vno', m.vno);
end $$;

create or replace function public.motor_purchase_void(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; pu public.motor_purchases%rowtype; mv record;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into pu from public.motor_purchases where id = p_id and site_id = sid and not voided for update;
  if not found then perform public._motor_err('not_found'); end if;
  for mv in select * from public.motor_stock_moves where purchase_id = pu.id and kind = 'purchase' loop
    update public.motor_stock set qty = qty - mv.qty, updated_by = w->>'name', updated_at = now() where id = mv.item_id;
    insert into public.motor_stock_moves (site_id, item_id, item_name, kind, qty, unit_price, taker, purchase_id, note, by_name)
    values (sid, mv.item_id, mv.item_name, 'void', -mv.qty, mv.unit_price, mv.taker, pu.id, 'إلغاء فاتورة مشتريات #' || pu.no, w->>'name');
  end loop;
  update public.motor_purchases set voided = true where id = pu.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.motor_supplier_pay(p_slug text, p_token text, p_supplier uuid, p_amount numeric, p_account text, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sup public.motor_suppliers%rowtype; m public.motor_moves%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into sup from public.motor_suppliers where id = p_supplier and site_id = sid;
  if not found then perform public._motor_err('not_found'); end if;
  m := public._motor_voucher(sid, w, p_account, p_amount, 'دفعة للمورد ' || sup.name, p_note, 'supplier', null, '');
  update public.motor_moves set supplier_id = sup.id where id = m.id returning * into m;
  return jsonb_build_object('ok', true, 'move', to_jsonb(m) - 'site_id', 'balance', public._motor_sup_bal(sup.id));
end $$;

create or replace function public.motor_supplier_statement(p_slug text, p_token text, p_supplier uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sup public.motor_suppliers%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into sup from public.motor_suppliers where id = p_supplier and site_id = sid;
  if not found then perform public._motor_err('not_found'); end if;
  return jsonb_build_object('supplier', to_jsonb(sup) - 'site_id', 'balance', public._motor_sup_bal(sup.id),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
       select jsonb_build_object('t','purchase','id',p.id,'at',p.created_at,'day',p.day,'no',p.no,'ref',p.ref,'items',p.items,'total',p.total,
              'to_stock',p.to_stock,'note',p.note,'by',p.by_name,'voided',p.voided) x from public.motor_purchases p where p.supplier_id = sup.id
       union all
       select jsonb_build_object('t','pay','id',m.id,'at',m.created_at,'vno',m.vno,'amount',m.amount,'account',m.account,'note',m.note,'by',m.by_name)
         from public.motor_moves m where m.supplier_id = sup.id and m.extra->>'type' = 'supplier') q), '[]'::jsonb));
end $$;

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
    'motor_journal(text,text,date,date)', 'motor_day_close(text,text,date)', 'motor_day_reopen(text,text,date)',
    'motor_stock_out(text,text,uuid,numeric,uuid,text,text)', 'motor_stock_moves_list(text,text,uuid,date,date)',
    'motor_suppliers(text,text)', 'motor_supplier_save(text,text,jsonb)', 'motor_supplier_delete(text,text,uuid)',
    'motor_purchase_add(text,text,jsonb)', 'motor_purchase_void(text,text,uuid)', 'motor_supplier_pay(text,text,uuid,numeric,text,text)',
    'motor_supplier_statement(text,text,uuid)', 'motor_staff_salary_set(text,text,uuid,numeric)', 'motor_salary_due_add(text,text,uuid,text,numeric,text)',
    'motor_salary_due_all(text,text,text)', 'motor_salary_due_delete(text,text,uuid)', 'motor_staff_statement(text,text,uuid)']
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
