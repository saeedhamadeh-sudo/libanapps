-- motorapp — الجزء 4 من 5 (شغّل الأجزاء بالترتيب)
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
      -- المقبوض بالشهر: إيصالات هالبرنامج + إيصالات البرنامج السابق (مستوردة من كشف الحساب) بتاريخها
      'paid', coalesce((select sum(p.amount) from public.motor_payments p where p.customer_id = c.id and not p.voided
                         and p.created_at >= f and p.created_at < t), 0)
            - coalesce((select sum(i.amount) from public.motor_invoices i where i.customer_id = c.id and not i.voided
                         and i.imported and i.kind = 'adjust' and i.amount < 0 and i.note like 'ايصال%' and i.period = per), 0),
      'paid_whish', coalesce((select sum(p.amount) from public.motor_payments p where p.customer_id = c.id and not p.voided
                         and p.method = 'whish' and p.created_at >= f and p.created_at < t), 0)
            - coalesce((select sum(i.amount) from public.motor_invoices i where i.customer_id = c.id and not i.voided
                         and i.imported and i.kind = 'adjust' and i.amount < 0 and i.note like 'ايصال%' and i.period = per
                         and (i.note ilike '%whish%' or i.note like '%ويش%')), 0),
      -- الرصيد آخر الشهر: الفاتورة بتنحسب بشهرها (period) مش بتاريخ إدخالها — مهم للفواتير المستوردة
      'balance_end', coalesce((select sum(i.amount) from public.motor_invoices i where i.customer_id = c.id and not i.voided
                     and (case when i.period <> '' then i.period else to_char(i.created_at at time zone 'Asia/Beirut','YYYY-MM') end) <= per), 0)
          - coalesce((select sum(p.amount) from public.motor_payments p where p.customer_id = c.id and not p.voided and p.created_at < t), 0),
      'other', coalesce((select sum(i.amount) from public.motor_invoices i where i.customer_id = c.id and not i.voided and i.kind not in ('meter','fixed')
                     and not (i.imported and i.kind = 'adjust' and i.amount < 0 and i.note like 'ايصال%')
                     and (case when i.period <> '' then i.period else to_char(i.created_at at time zone 'Asia/Beirut','YYYY-MM') end) = per), 0),
      'balance_start', coalesce((select sum(i.amount) from public.motor_invoices i where i.customer_id = c.id and not i.voided
                     and (case when i.period <> '' then i.period else to_char(i.created_at at time zone 'Asia/Beirut','YYYY-MM') end) < per), 0)
          - coalesce((select sum(p.amount) from public.motor_payments p where p.customer_id = c.id and not p.voided and p.created_at < f), 0),
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
    'paged', true);   -- الجداول الكبيرة بتنسحب على دفعات (motor_backup_page) حتى ما يصير timeout
end $$;

create or replace function public.motor_backup_page(p_slug text, p_token text, p_table text, p_offset integer default 0, p_limit integer default 2000)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; lim int := least(greatest(coalesce(p_limit, 2000), 1), 5000); off int := greatest(coalesce(p_offset, 0), 0);
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_table = 'customers' then
    return coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.code, x.id) from
      (select * from public.motor_customers where site_id = sid order by code, id offset off limit lim) x), '[]');
  elsif p_table = 'readings' then
    return coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.created_at, x.id) from
      (select * from public.motor_readings where site_id = sid order by created_at, id offset off limit lim) x), '[]');
  elsif p_table = 'invoices' then
    return coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.created_at, x.id) from
      (select * from public.motor_invoices where site_id = sid order by created_at, id offset off limit lim) x), '[]');
  elsif p_table = 'payments' then
    return coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.created_at, x.id) from
      (select * from public.motor_payments where site_id = sid order by created_at, id offset off limit lim) x), '[]');
  elsif p_table = 'moves' then
    return coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.created_at, x.id) from
      (select * from public.motor_moves where site_id = sid order by created_at, id offset off limit lim) x), '[]');
  elsif p_table = 'insurance' then
    return coalesce((select jsonb_agg(to_jsonb(x) - 'site_id' order by x.created_at, x.id) from
      (select * from public.motor_insurance where site_id = sid order by created_at, id offset off limit lim) x), '[]');
  end if;
  perform public._motor_err('bad_data');
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
  elsif tr.kind = 'insurance' then
    insert into public.motor_insurance select (jsonb_populate_record(null::public.motor_insurance, tr.data)).*;
    update public.motor_insurance set move_id = null where id = tr.ref_id;
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
--  20f2) المدير الأساسي بيفوت على حساب أي موظف من جهازو (بلا كلمة سر وبلا قفل جهاز)
-- ============================================================
create or replace function public.motor_impersonate(p_slug text, p_token text, p_staff uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sf public.motor_staff%rowtype; tok text;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not coalesce((w->>'is_main')::boolean,false) then perform public._motor_err('main_only'); end if;
  select * into sf from public.motor_staff where id = p_staff and site_id = sid;
  if not found then perform public._motor_err('bad_staff'); end if;
  if sf.id::text = w->>'staff_id' then perform public._motor_err('bad_staff'); end if;
  if not sf.is_active then perform public._motor_err('inactive_user'); end if;
  tok := encode(gen_random_bytes(24),'hex');
  insert into public.motor_sessions (token_hash, staff_id, site_id, expires_at, impersonated_by)
  values (encode(digest(tok,'sha256'),'hex'), sf.id, sid, now() + interval '12 hours', w->>'name');
  return jsonb_build_object('ok', true, 'token', tok, 'name', sf.name, 'role', sf.role);
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

