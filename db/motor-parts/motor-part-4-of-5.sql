-- motorapp — الجزء 4 من 5 (شغّل الأجزاء بالترتيب)
-- ============================================================
--  19) واتساب من المكتب: الفواتير والإيصالات يلّي بعد ما انبعتت
-- ============================================================
-- الفواتير المتراكمة حسب كشف الحساب: الدفعات تسدّد الأقدم أولاً، فالباقي = أحدث الفواتير لحد ما يكمل الرصيد
create or replace function public._motor_due_info(p_cust uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare bal numeric; acc numeric := 0; r record; per text[] := '{}'; n int := 0; rest numeric;
begin
  select balance into bal from public.motor_customers where id = p_cust;
  bal := coalesce(bal, 0);
  if bal > 0 then
    for r in select period, amount from public.motor_invoices where customer_id = p_cust and not voided and amount > 0
               and kind in ('meter','fixed') and period <> ''
              order by created_at desc loop
      exit when acc >= bal - 0.005;
      acc := acc + r.amount; n := n + 1;
      if not (r.period = any(per)) then per := r.period || per; end if;
    end loop;
  end if;
  rest := greatest(bal - acc, 0);
  return jsonb_build_object('balance', bal, 'count', n, 'periods', to_jsonb(per), 'older', rest > 0.005);
end $$;
revoke all on function public._motor_due_info(uuid) from public, anon, authenticated;

create or replace function public.motor_wa_outbox(p_slug text, p_token text, p_days integer default 60)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return coalesce((select jsonb_agg(x order by x->>'at') from (
      select jsonb_build_object('t','inv','id',i.id,'at',i.created_at,'inv',to_jsonb(i) - 'site_id',
             'due', public._motor_due_info(c.id),
             'customer', jsonb_build_object('id',c.id,'code',c.code,'name',c.name,'mobile',c.mobile,'mobile_cc',c.mobile_cc,'box',c.box)) as x
        from public.motor_invoices i join public.motor_customers c on c.id = i.customer_id
       where i.site_id = sid and not i.voided and i.kind in ('meter','fixed') and i.wa_sent_at is null
         and i.created_at > now() - make_interval(days => greatest(1, coalesce(p_days,60)))
      union all
      select jsonb_build_object('t','pay','id',p.id,'at',p.created_at,'pay',to_jsonb(p) - 'site_id',
             'inv', (select to_jsonb(i) - 'site_id' from public.motor_invoices i where i.customer_id = p.customer_id
                      and not i.voided and i.kind in ('meter','fixed') and i.created_at <= p.created_at
                      order by i.created_at desc limit 1),
             'customer', jsonb_build_object('id',c.id,'code',c.code,'name',c.name,'mobile',c.mobile,'mobile_cc',c.mobile_cc,'box',c.box))
        from public.motor_payments p join public.motor_customers c on c.id = p.customer_id
       where p.site_id = sid and not p.voided and p.wa_sent_at is null
         and p.created_at > now() - make_interval(days => greatest(1, coalesce(p_days,60)))
    ) q), '[]'::jsonb);
end $$;

create or replace function public.motor_wa_mark(p_slug text, p_token text, p_kind text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_kind = 'inv' then
    update public.motor_invoices set wa_sent_at = now(), wa_sent_by = w->>'name' where id = p_id and site_id = sid;
  elsif p_kind = 'pay' then
    update public.motor_payments set wa_sent_at = now(), wa_sent_by = w->>'name' where id = p_id and site_id = sid;
  else perform public._motor_err('bad_kind'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  20) لوحة سريعة
-- ============================================================
create or replace function public.motor_dashboard(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; st public.motor_sites%rowtype; mine boolean; me uuid; m0 date; today date := public._motor_today();
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid; mine := not (w->>'is_admin')::boolean; me := (w->>'staff_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  m0 := date_trunc('month', today)::date;
  return jsonb_build_object(
    'period', st.bill_period, 'lbp_rate', st.lbp_rate,
    'customers_active', (select count(*) from public.motor_customers where site_id = sid and is_active and not archived and deleted_at is null),
    'customers_total', (select count(*) from public.motor_customers where site_id = sid and deleted_at is null),
    'read_period', (select count(*) from public.motor_readings where site_id = sid and period = st.bill_period
                     and (not mine or staff_id = me)),
    'billed_period', coalesce((select sum(amount) from public.motor_invoices where site_id = sid and period = st.bill_period
                     and kind in ('meter','fixed') and not voided and (not mine or staff_id = me)), 0),
    'unpaid_count', (select count(*) from public.motor_customers where site_id = sid and balance > 0 and not archived and deleted_at is null),
    'debt_total', case when mine then null else coalesce((select sum(balance) from public.motor_customers
                     where site_id = sid and balance > 0 and deleted_at is null), 0) end,
    'trash_count', case when mine then null else (select count(*) from public.motor_trash where site_id = sid) end,
    'cash_box', case when mine then null else public._motor_cash_bal(sid, null) end,
    'whish_box', case when mine then null else
                   coalesce((select sum(amount) from public.motor_payments where site_id = sid and method = 'whish' and not voided), 0)
                 + coalesce((select sum(case when kind = 'withdraw' then -abs(amount) else amount end) from public.motor_moves
                              where site_id = sid and account = 'whish'), 0) end,
    'wa_inv', case when mine then null else
        (select count(*) from public.motor_invoices i where i.site_id = sid and not i.voided and i.kind in ('meter','fixed')
            and i.wa_sent_at is null and i.created_at > now() - interval '60 days') end,
    'wa_pending', case when mine then null else
        (select count(*) from public.motor_invoices i where i.site_id = sid and not i.voided and i.kind in ('meter','fixed')
            and i.wa_sent_at is null and i.created_at > now() - interval '60 days')
      + (select count(*) from public.motor_payments p where p.site_id = sid and not p.voided
            and p.wa_sent_at is null and p.created_at > now() - interval '60 days') end,
    'cash_today', coalesce((select sum(amount) from public.motor_payments where site_id = sid and method = 'cash' and not voided
                     and (created_at at time zone 'Asia/Beirut')::date = today and (not mine or staff_id = me)), 0),
    'whish_today', coalesce((select sum(amount) from public.motor_payments where site_id = sid and method = 'whish' and not voided
                     and (created_at at time zone 'Asia/Beirut')::date = today and (not mine or staff_id = me)), 0),
    'collected_month', coalesce((select sum(amount) from public.motor_payments where site_id = sid and not voided
                     and (created_at at time zone 'Asia/Beirut')::date >= m0 and (not mine or staff_id = me)), 0),
    'my_cash_in_hand', case when me is null or not mine then null else
                     coalesce((select sum(amount) from public.motor_payments where staff_id = me and method = 'cash' and not voided), 0)
                   - coalesce((select sum(amount) from public.motor_moves where staff_id = me and account = 'collector'), 0) end);
end $$;

-- ============================================================
--  20b) تعديل قراءة العداد (المدير فقط — بلا صورة ولا موقع) + حساب دخول الزبون + صفحة الزبون
-- ============================================================
create or replace function public.motor_reading_edit(p_slug text, p_token text, p_reading uuid, p_value numeric, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; r public.motor_readings%rowtype; i public.motor_invoices%rowtype; st public.motor_sites%rowtype;
        v_kwh numeric; v_energy numeric; amt numeric; delta numeric;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  select * into r from public.motor_readings where id = p_reading and site_id = sid for update;
  if not found then perform public._motor_err('not_found'); end if;
  if exists (select 1 from public.motor_readings x where x.customer_id = r.customer_id and x.created_at > r.created_at) then
    perform public._motor_err('not_latest');
  end if;
  if p_value is null or p_value < r.prev_value then perform public._motor_err('lower_than_prev', r.prev_value::text); end if;
  update public.motor_readings set value = p_value where id = r.id;
  select * into i from public.motor_invoices where reading_id = r.id and not voided for update;
  if found then
    v_kwh := p_value - coalesce(i.prev_value, r.prev_value);
    v_energy := case when i.kind = 'meter' then round(v_kwh * i.kwh_price, 2) else 0 end;
    amt := public._motor_round(sid, i.fee + v_energy - i.discount + i.addition);
    delta := amt - i.amount;
    update public.motor_invoices set cur_value = p_value, kwh = v_kwh, energy = v_energy, amount = amt,
           balance_after = balance_after + delta,
           note = trim(both ' ' from note || case when coalesce(p_note,'') <> '' then ' ' || p_note else '' end || ' (عُدّلت القراءة بواسطة ' || (w->>'name') || ')')
     where id = i.id;
    update public.motor_customers set balance = balance + delta, updated_at = now() where id = r.customer_id;
  else
    update public.motor_customers set updated_at = now() where id = r.customer_id;
  end if;
  return jsonb_build_object('ok', true, 'delta', coalesce(delta, 0));
end $$;

-- اسم مستخدم وكلمة مرور للزبون (فاضي = إلغاء الدخول)
create or replace function public.motor_customer_set_login(p_slug text, p_token text, p_customer uuid, p_username text, p_password text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; u text := lower(trim(coalesce(p_username,'')));
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not exists (select 1 from public.motor_customers where id = p_customer and site_id = sid) then perform public._motor_err('customer_not_found'); end if;
  if u = '' then
    update public.motor_customers set username = '' where id = p_customer;
    delete from public.motor_customer_secrets where customer_id = p_customer;
    delete from public.motor_csessions where customer_id = p_customer;
    return jsonb_build_object('ok', true, 'removed', true);
  end if;
  if u !~ '^[a-z0-9._-]{2,30}$' then perform public._motor_err('bad_username'); end if;
  if exists (select 1 from public.motor_staff where site_id = sid and lower(username) = u)
     or exists (select 1 from public.motor_customers where site_id = sid and lower(username) = u and id <> p_customer) then
    perform public._motor_err('username_taken');
  end if;
  if not exists (select 1 from public.motor_customer_secrets where customer_id = p_customer) and length(coalesce(p_password,'')) < 4 then
    perform public._motor_err('short_password');
  end if;
  if length(coalesce(p_password,'')) between 1 and 3 then perform public._motor_err('short_password'); end if;
  update public.motor_customers set username = u where id = p_customer;
  if length(coalesce(p_password,'')) >= 4 then
    insert into public.motor_customer_secrets (customer_id, password_hash) values (p_customer, public._motor_hash(p_password))
    on conflict (customer_id) do update set password_hash = excluded.password_hash, failed_count = 0, locked_until = null, updated_at = now();
    delete from public.motor_csessions where customer_id = p_customer;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- صفحة الزبون: رصيده وفواتيره وكشف حسابه (للقراءة فقط)
create or replace function public.motor_cust_me(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare st public.motor_sites%rowtype; cid uuid; c public.motor_customers%rowtype; lic jsonb;
begin
  select * into st from public.motor_sites where slug = lower(trim(coalesce(p_slug,'')));
  if not found then perform public._motor_err('not_found'); end if;
  select s.customer_id into cid from public.motor_csessions s
   where s.token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex') and s.expires_at > now() and s.site_id = st.id;
  if cid is null then perform public._motor_err('auth'); end if;
  lic := public.motor_license(st.id);
  if not st.is_active or not coalesce((lic->>'ok')::boolean,false) then perform public._motor_err('license'); end if;
  select * into c from public.motor_customers where id = cid;
  return jsonb_build_object(
    'site', jsonb_build_object('name', st.name, 'logo_url', st.logo_url, 'tagline', st.tagline, 'phone', st.phone, 'whatsapp', st.whatsapp,
             'currency', st.currency, 'lbp_rate', st.lbp_rate, 'show_second', st.show_second, 'cur_label', st.cur_label,
             'whish_qr_url', st.whish_qr_url, 'whish_phone', st.whish_phone, 'bill_period', st.bill_period, 'default_lang', st.default_lang,
             'invoice_note', st.invoice_note),
    'customer', jsonb_build_object('id', c.id, 'code', c.code, 'name', c.name, 'barcode', c.barcode, 'meter_no', c.meter_no,
             'box', c.box, 'balance', c.balance, 'is_active', c.is_active, 'mobile', c.mobile, 'mobile_cc', c.mobile_cc,
             'plan_name', (select name from public.motor_plans where id = c.plan_id)),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
        select jsonb_build_object('t','inv','id',i.id,'no',i.no,'at',i.created_at,'created_at',i.created_at,'kind',i.kind,'period',i.period,
               'prev_value',i.prev_value,'cur_value',i.cur_value,'kwh',i.kwh,'kwh_price',i.kwh_price,'fee',i.fee,
               'energy',i.energy,'discount',i.discount,'addition',i.addition,'amount',i.amount,'debit',i.amount,'credit',0,
               'balance_before',i.balance_before,'balance_after',i.balance_after,'note',i.note,
               'photo', (select r.photo_url from public.motor_readings r where r.id = i.reading_id)) as x
          from public.motor_invoices i where i.customer_id = c.id and not i.voided
        union all
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'created_at',p.created_at,'method',p.method,
               'paid_currency',p.paid_currency,'paid_amount',p.paid_amount,'amount',p.amount,'debit',0,'credit',p.amount,
               'balance_before',p.balance_before,'balance_after',p.balance_after,'staff_name',p.staff_name)
          from public.motor_payments p where p.customer_id = c.id and not p.voided
      ) q), '[]'::jsonb));
end $$;

-- ============================================================
--  20c) تعديلات المدير: الفاتورة والدفعة، الباركود، الكشف الشهري العام، النسخة الاحتياطية
-- ============================================================
create or replace function public.motor_invoice_edit(p_slug text, p_token text, p_id uuid, p_amount numeric, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; i public.motor_invoices%rowtype; delta numeric;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into i from public.motor_invoices where id = p_id and site_id = sid for update;
  if not found or i.voided then perform public._motor_err('not_found'); end if;
  if p_amount is null then perform public._motor_err('bad_amount'); end if;
  delta := p_amount - i.amount;
  update public.motor_invoices set amount = p_amount, balance_after = balance_after + delta,
         note = trim(both ' ' from coalesce(p_note, note) || case when delta <> 0 then ' (عدّلها ' || (w->>'name') || ')' else '' end)
   where id = i.id;
  update public.motor_customers set balance = balance + delta, updated_at = now() where id = i.customer_id;
  return jsonb_build_object('ok', true, 'delta', delta);
end $$;

create or replace function public.motor_payment_edit(p_slug text, p_token text, p_id uuid, p_paid numeric, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; p public.motor_payments%rowtype; st public.motor_sites%rowtype; amt numeric; delta numeric;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  select * into p from public.motor_payments where id = p_id and site_id = sid for update;
  if not found or p.voided then perform public._motor_err('not_found'); end if;
  if coalesce(p_paid,0) <= 0 then perform public._motor_err('bad_amount'); end if;
  if p.method = 'cash' and p.created_at <= coalesce((select max(created_at) from public.motor_moves
        where site_id = sid and account = 'cash' and kind = 'close'), '-infinity'::timestamptz) then
    perform public._motor_err('closed_period');
  end if;
  if exists (select 1 from public.motor_day_closes where site_id = sid and day = (p.created_at at time zone 'Asia/Beirut')::date) then
    perform public._motor_err('day_closed');
  end if;
  if p.paid_currency = st.currency then amt := p_paid;
  elsif p.paid_currency = 'LBP' then amt := round(p_paid / nullif(p.rate,0), 2);
  else amt := round(p_paid * p.rate, 0); end if;
  delta := amt - p.amount;
  update public.motor_payments set paid_amount = p_paid, amount = amt, balance_after = balance_after - delta,
         note = trim(both ' ' from coalesce(p_note, note) || case when delta <> 0 then ' (عدّلها ' || (w->>'name') || ')' else '' end)
   where id = p.id;
  update public.motor_customers set balance = balance - delta, updated_at = now() where id = p.customer_id;
  return jsonb_build_object('ok', true, 'delta', delta);
end $$;

-- باركود لكل زبون ما عندو (البادئة + رقم الزبون)
create or replace function public.motor_fill_barcodes(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; pre text; n int := 0; r record; code text;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select barcode_prefix into pre from public.motor_sites where id = sid;
  for r in select id, code from public.motor_customers where site_id = sid and barcode = '' order by code loop
    code := pre || '-' || lpad(r.code::text, 5, '0');
    while exists (select 1 from public.motor_customers where site_id = sid and lower(barcode) = lower(code)) loop
      code := code || 'X';
    end loop;
    update public.motor_customers set barcode = code, updated_at = now() where id = r.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'count', n);
end $$;

-- كشف شهري عام: سطر لكل زبون للشهر المختار
create or replace function public.motor_month_report(p_slug text, p_token text, p_period text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; per text; f timestamptz; t timestamptz;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  per := coalesce(nullif(p_period,''), (select bill_period from public.motor_sites where id = sid));
  if per !~ '^\d{4}-\d{2}$' then perform public._motor_err('bad_period'); end if;
  f := (per || '-01')::timestamp at time zone 'Asia/Beirut';
  t := ((per || '-01')::date + interval '1 month')::timestamp at time zone 'Asia/Beirut';
  return jsonb_build_object('period', per, 'rows', coalesce((select jsonb_agg(jsonb_build_object(
      'code', c.code, 'name', c.name, 'barcode', c.barcode, 'box', c.box, 'area', c.area,
      'plan', pl.name, 'collector', coalesce(sf.name, c.collector_name), 'is_active', c.is_active,
      'prev_value', r.prev_value, 'cur_value', r.value, 'kwh', case when r.id is null then null else r.value - r.prev_value end,
      'invoiced', coalesce((select sum(i.amount) from public.motor_invoices i where i.customer_id = c.id and not i.voided
                             and i.kind in ('meter','fixed') and i.period = per), 0),
      'paid', coalesce((select sum(p.amount) from public.motor_payments p where p.customer_id = c.id and not p.voided
                         and p.created_at >= f and p.created_at < t), 0),
      'paid_whish', coalesce((select sum(p.amount) from public.motor_payments p where p.customer_id = c.id and not p.voided
                         and p.method = 'whish' and p.created_at >= f and p.created_at < t), 0),
      'balance_end', c.balance
          - coalesce((select sum(i.amount) from public.motor_invoices i where i.customer_id = c.id and not i.voided and i.created_at >= t), 0)
          + coalesce((select sum(p.amount) from public.motor_payments p where p.customer_id = c.id and not p.voided and p.created_at >= t), 0),
      'balance_now', c.balance) order by c.code)
    from public.motor_customers c
    left join public.motor_plans pl on pl.id = c.plan_id
    left join public.motor_staff sf on sf.id = c.collector_id
    left join public.motor_readings r on r.customer_id = c.id and r.period = per
    where c.site_id = sid and not c.archived and c.deleted_at is null), '[]'::jsonb));
end $$;

-- نسخة احتياطية كاملة (تُنزَّل كملف Excel عند الخروج)
create or replace function public.motor_backup(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return jsonb_build_object(
    'at', now(),
    'site', (select to_jsonb(s) - 'client_id' from public.motor_sites s where s.id = sid),
    'plans', coalesce((select jsonb_agg(to_jsonb(x) - 'site_id') from public.motor_plans x where x.site_id = sid), '[]'),
    'staff', coalesce((select jsonb_agg(jsonb_build_object('name', x.name, 'username', x.username, 'role', x.role, 'phone', x.phone,
               'can_read', x.can_read, 'can_collect', x.can_collect, 'can_cut', x.can_cut, 'is_active', x.is_active))
               from public.motor_staff x where x.site_id = sid), '[]'),
    'customers', coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.code) from public.motor_customers x where x.site_id = sid), '[]'),
    'readings', coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.created_at) from public.motor_readings x where x.site_id = sid), '[]'),
    'invoices', coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.created_at) from public.motor_invoices x where x.site_id = sid), '[]'),
    'payments', coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.created_at) from public.motor_payments x where x.site_id = sid), '[]'),
    'moves', coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.created_at) from public.motor_moves x where x.site_id = sid), '[]'));
end $$;

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
           'due', (select sum(d.amount) from public.motor_salary_dues d where d.staff_id = s.id and d.period = p_period),
           'dues', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'amount', d.amount, 'note', d.note, 'at', d.created_at) order by d.created_at)
                    from public.motor_salary_dues d where d.staff_id = s.id and d.period = p_period), '[]'::jsonb),
           'balance', coalesce((select sum(d.amount) from public.motor_salary_dues d where d.staff_id = s.id), 0)
                    - coalesce((select sum(m.amount) from public.motor_moves m where m.pay_staff = s.id and m.extra->>'type' = 'salary'), 0),
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

