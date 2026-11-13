-- motorapp — الجزء 3 من 5 (شغّل الأجزاء بالترتيب)
-- ============================================================
--  11) جدول عدادات الشهر
-- ============================================================
create or replace function public.motor_month(p_slug text, p_token text, p_period text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; per text; mine boolean;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  per := coalesce(nullif(p_period,''), (select bill_period from public.motor_sites where id = sid));
  mine := w->>'role' = 'collector';
  return jsonb_build_object('period', per, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'at', r.created_at, 'customer_id', c.id, 'code', c.code, 'name', c.name, 'barcode', c.barcode,
      'box', c.box, 'area', c.area, 'prev_value', r.prev_value, 'value', r.value, 'kwh', r.value - r.prev_value,
      'photo', r.photo_url, 'lat', r.lat, 'lng', r.lng, 'accuracy', r.accuracy, 'dist_m', r.dist_m, 'remote', r.remote,
      'staff_id', r.staff_id, 'staff', r.staff_name,
      'invoice_id', i.id, 'invoice_no', i.no, 'amount', i.amount, 'balance_after', i.balance_after)
      order by r.created_at desc)
    from public.motor_readings r
    join public.motor_customers c on c.id = r.customer_id
    left join public.motor_invoices i on i.reading_id = r.id
    where r.site_id = sid and r.period = per and (not mine or r.staff_id = (w->>'staff_id')::uuid)), '[]'::jsonb),
    'total_active', (select count(*) from public.motor_customers where site_id = sid and is_active and not archived),
    'total_read', (select count(*) from public.motor_readings where site_id = sid and period = per));
end $$;

-- ============================================================
--  12) الإعدادات / أنواع الاشتراك / الموظفين  (المدير فقط)
-- ============================================================
create or replace function public.motor_settings_save(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; d jsonb := coalesce(p_data,'{}'::jsonb); st public.motor_sites%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if d ? 'bill_period' and (d->>'bill_period') !~ '^\d{4}-(0[1-9]|1[0-2])$' then perform public._motor_err('bad_period'); end if;
  if d ? 'currency' and (d->>'currency') not in ('USD','LBP') then perform public._motor_err('bad_currency'); end if;
  update public.motor_sites set
    name           = coalesce(nullif(trim(d->>'name'),''), name),
    logo_url       = coalesce(d->>'logo_url', logo_url),
    phone          = coalesce(d->>'phone', phone),
    whatsapp       = coalesce(regexp_replace(d->>'whatsapp','[^0-9]','','g'), whatsapp),
    address        = coalesce(d->>'address', address),
    currency       = coalesce(d->>'currency', currency),
    lbp_rate       = coalesce(nullif(d->>'lbp_rate','')::numeric, lbp_rate),
    show_second    = coalesce((d->>'show_second')::boolean, show_second),
    kwh_price      = coalesce(nullif(d->>'kwh_price','')::numeric, kwh_price),
    round_step     = coalesce(nullif(d->>'round_step','')::numeric, round_step),
    bill_period    = coalesce(d->>'bill_period', bill_period),
    max_distance_m = coalesce(nullif(d->>'max_distance_m','')::integer, max_distance_m),
    require_photo  = coalesce((d->>'require_photo')::boolean, require_photo),
    require_gps    = coalesce((d->>'require_gps')::boolean, require_gps),
    first_read_baseline = coalesce((d->>'first_read_baseline')::boolean, first_read_baseline),
    collector_sees_all = coalesce((d->>'collector_sees_all')::boolean, collector_sees_all),
    barcode_prefix = coalesce(nullif(upper(regexp_replace(d->>'barcode_prefix','[^A-Za-z0-9]','','g')),''), barcode_prefix),
    invoice_note   = coalesce(d->>'invoice_note', invoice_note),
    tagline        = coalesce(d->>'tagline', tagline),
    whish_qr_url   = coalesce(d->>'whish_qr_url', whish_qr_url),
    whish_phone    = coalesce(d->>'whish_phone', whish_phone),
    cur_label      = coalesce(left(trim(d->>'cur_label'), 10), cur_label),
    wa_from_office = coalesce((d->>'wa_from_office')::boolean, wa_from_office),
    default_lang   = case when d->>'default_lang' in ('ar','en','fr') then d->>'default_lang' else default_lang end
  where id = sid returning * into st;
  return to_jsonb(st) - 'client_id' - 'cust_seq' - 'invoice_seq' - 'receipt_seq' - 'wc_api_key' - 'wc_hook_secret';
end $$;

create or replace function public.motor_plan_save(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; d jsonb := coalesce(p_data,'{}'::jsonb); p public.motor_plans%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(trim(d->>'name'),'') = '' then perform public._motor_err('name_required'); end if;
  if coalesce(d->>'kind','meter') not in ('meter','fixed') then perform public._motor_err('bad_kind'); end if;
  if exists (select 1 from public.motor_plans x where x.site_id = sid and lower(x.name) = lower(trim(d->>'name'))
             and x.id::text <> coalesce(d->>'id','')) then
    perform public._motor_err('name_taken');
  end if;
  if coalesce(d->>'id','') = '' then
    insert into public.motor_plans (site_id, name, amps, kind, fee, kwh_price, is_active, sort)
    values (sid, trim(d->>'name'), coalesce(nullif(d->>'amps','')::numeric,0), coalesce(d->>'kind','meter'),
            coalesce(nullif(d->>'fee','')::numeric,0), nullif(d->>'kwh_price','')::numeric,
            coalesce((d->>'is_active')::boolean,true), coalesce(nullif(d->>'sort','')::int,0))
    returning * into p;
  else
    update public.motor_plans set name = trim(d->>'name'), amps = coalesce(nullif(d->>'amps','')::numeric,0),
           kind = coalesce(d->>'kind','meter'), fee = coalesce(nullif(d->>'fee','')::numeric,0),
           kwh_price = nullif(d->>'kwh_price','')::numeric, is_active = coalesce((d->>'is_active')::boolean,true),
           sort = coalesce(nullif(d->>'sort','')::int, sort)
     where id = (d->>'id')::uuid and site_id = sid returning * into p;
    if p.id is null then perform public._motor_err('not_found'); end if;
  end if;
  return to_jsonb(p) - 'site_id';
end $$;

create or replace function public.motor_plan_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if exists (select 1 from public.motor_customers where plan_id = p_id and deleted_at is null) then perform public._motor_err('plan_in_use'); end if;
  update public.motor_customers set plan_id = null where plan_id = p_id;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  select sid, 'plan', x.id, x.name, to_jsonb(x), w->>'name' from public.motor_plans x where x.id = p_id and x.site_id = sid;
  delete from public.motor_plans where id = p_id and site_id = sid;
  return jsonb_build_object('ok', true);
end $$;

-- p_password فاضي = ما تتغيّر (إلزامي للموظف الجديد)
create or replace function public.motor_staff_save(p_slug text, p_token text, p_data jsonb, p_password text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare w jsonb; sid uuid; d jsonb := coalesce(p_data,'{}'::jsonb); s public.motor_staff%rowtype; u text;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  u := lower(trim(coalesce(d->>'username','')));
  if coalesce(trim(d->>'name'),'') = '' then perform public._motor_err('name_required'); end if;
  if u !~ '^[a-z0-9._-]{2,30}$' then perform public._motor_err('bad_username'); end if;
  if coalesce(d->>'role','collector') not in ('admin','collector') then perform public._motor_err('bad_role'); end if;
  if exists (select 1 from public.motor_staff x where x.site_id = sid and lower(x.username) = u
             and x.id::text <> coalesce(d->>'id','')) then perform public._motor_err('username_taken'); end if;
  if not coalesce((w->>'is_main')::boolean,false) and ((coalesce(d->>'role','collector') = 'admin' and coalesce(d->>'id','') <> coalesce(w->>'staff_id',''))
       or exists (select 1 from public.motor_staff x where x.id::text = coalesce(d->>'id','') and x.role = 'admin' and x.id::text <> coalesce(w->>'staff_id',''))) then
    perform public._motor_err('main_only');
  end if;
  if nullif(d->>'read_from','') is not null and nullif(d->>'read_to','') is not null
     and (d->>'read_from')::date > (d->>'read_to')::date then perform public._motor_err('bad_window'); end if;
  if coalesce(d->>'id','') = '' then
    if length(coalesce(p_password,'')) < 4 then perform public._motor_err('short_password'); end if;
    insert into public.motor_staff (site_id, name, username, phone, role, is_active, read_from, read_to, can_collect, can_read, can_cut)
    values (sid, trim(d->>'name'), u, coalesce(d->>'phone',''), coalesce(d->>'role','collector'),
            coalesce((d->>'is_active')::boolean,true), nullif(d->>'read_from','')::date, nullif(d->>'read_to','')::date,
            coalesce((d->>'can_collect')::boolean,true), coalesce((d->>'can_read')::boolean,true), coalesce((d->>'can_cut')::boolean,false))
    returning * into s;
    update public.motor_staff set salary = coalesce(nullif(d->>'salary','')::numeric, 0) where id = s.id returning * into s;
  else
    -- الموظف ما بيقدر يشيل صلاحية المدير عن حالو
    if (d->>'id') = w->>'staff_id' and coalesce(d->>'role','collector') <> 'admin' then perform public._motor_err('self_demote'); end if;
    if (d->>'id') = w->>'staff_id' and not coalesce((d->>'is_active')::boolean,true) then perform public._motor_err('self_demote'); end if;
    update public.motor_staff set name = trim(d->>'name'), username = u, phone = coalesce(d->>'phone',''),
           role = coalesce(d->>'role','collector'), is_active = coalesce((d->>'is_active')::boolean,true),
           read_from = nullif(d->>'read_from','')::date, read_to = nullif(d->>'read_to','')::date,
           can_collect = coalesce((d->>'can_collect')::boolean,true),
           can_read = coalesce((d->>'can_read')::boolean,true), can_cut = coalesce((d->>'can_cut')::boolean,false),
           salary = coalesce(nullif(d->>'salary','')::numeric, salary)
     where id = (d->>'id')::uuid and site_id = sid returning * into s;
    -- المدير الأساسي يضل مدير ومفعّل
    if s.is_main and (s.role <> 'admin' or not s.is_active) then perform public._motor_err('self_demote'); end if;
    if s.id is null then perform public._motor_err('not_found'); end if;
    if length(coalesce(p_password,'')) between 1 and 3 then perform public._motor_err('short_password'); end if;
    if not s.is_active then delete from public.motor_sessions where staff_id = s.id; end if;
  end if;
  if length(coalesce(p_password,'')) >= 4 then
    insert into public.motor_staff_secrets (staff_id, password_hash) values (s.id, crypt(p_password, gen_salt('bf', 8)))
    on conflict (staff_id) do update set password_hash = excluded.password_hash, failed_count = 0, locked_until = null, updated_at = now();
    delete from public.motor_sessions where staff_id = s.id
      and token_hash <> encode(digest(coalesce(p_token,''),'sha256'),'hex');
  end if;
  return to_jsonb(s) - 'site_id' - 'last_lat' - 'last_lng' - 'last_acc';
end $$;

-- فترة أخذ العدادات لكل الجباة دفعة وحدة
create or replace function public.motor_window_all(p_slug text, p_token text, p_from date, p_to date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; n int;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_from is not null and p_to is not null and p_from > p_to then perform public._motor_err('bad_window'); end if;
  update public.motor_staff set read_from = p_from, read_to = p_to where site_id = sid and role = 'collector';
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'count', n);
end $$;

create or replace function public.motor_staff_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_id::text = w->>'staff_id' then perform public._motor_err('self_demote'); end if;
  if exists (select 1 from public.motor_staff where id = p_id and (is_main or (role = 'admin' and not coalesce((w->>'is_main')::boolean,false)))) then
    perform public._motor_err('main_only');
  end if;
  if exists (select 1 from public.motor_payments where staff_id = p_id)
     or exists (select 1 from public.motor_readings where staff_id = p_id)
     or exists (select 1 from public.motor_moves where staff_id = p_id) then
    -- عندو حركات: منوقّفو بدل الحذف حتى يضل كشف حسابو
    update public.motor_staff set is_active = false where id = p_id and site_id = sid;
    delete from public.motor_sessions where staff_id = p_id;
    return jsonb_build_object('ok', true, 'deactivated', true);
  end if;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  select sid, 'staff', x.id, x.name || ' (' || x.username || ')', to_jsonb(x), w->>'name' from public.motor_staff x where x.id = p_id and x.site_id = sid;
  delete from public.motor_staff where id = p_id and site_id = sid;
  return jsonb_build_object('ok', true, 'deleted', true);
end $$;

-- ============================================================
--  13) كشف حساب الجابي  (له: المقبوض نقداً — عليه: ما سلّمه للمكتب)
-- ============================================================
create or replace function public.motor_collector_statement(p_slug text, p_token text, p_staff uuid,
  p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; sf public.motor_staff%rowtype; opening numeric; f date; t date;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not (w->>'is_admin')::boolean and p_staff::text is distinct from w->>'staff_id' then perform public._motor_err('forbidden'); end if;
  select * into sf from public.motor_staff where id = p_staff and site_id = sid;
  if not found then perform public._motor_err('not_found'); end if;
  f := coalesce(p_from, date '2000-01-01'); t := coalesce(p_to, date '2999-12-31');
  -- رصيد ما قبل الفترة
  opening := coalesce((select sum(amount) from public.motor_payments where staff_id = sf.id and method = 'cash'
                         and not voided and (created_at at time zone 'Asia/Beirut')::date < f), 0)
           - coalesce((select sum(amount) from public.motor_moves where staff_id = sf.id and account = 'collector'
                         and (created_at at time zone 'Asia/Beirut')::date < f), 0);
  return jsonb_build_object(
    'staff', jsonb_build_object('id', sf.id, 'name', sf.name, 'role', sf.role),
    'opening', opening,
    'balance_now', coalesce((select sum(amount) from public.motor_payments where staff_id = sf.id and method = 'cash' and not voided), 0)
                 - coalesce((select sum(amount) from public.motor_moves where staff_id = sf.id and account = 'collector'), 0),
    'readings', (select count(*) from public.motor_readings where staff_id = sf.id
                   and (created_at at time zone 'Asia/Beirut')::date between f and t),
    'whish_total', coalesce((select sum(amount) from public.motor_payments where staff_id = sf.id and method = 'whish'
                   and not voided and (created_at at time zone 'Asia/Beirut')::date between f and t), 0),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'customer',c.name,'code',c.code,'customer_id',c.id,
               'method',p.method,'paid_currency',p.paid_currency,'paid_amount',p.paid_amount,
               'debit', case when p.method = 'cash' then p.amount else 0 end, 'credit', 0, 'amount', p.amount,
               'note', p.note, 'voided', p.voided) as x
          from public.motor_payments p join public.motor_customers c on c.id = p.customer_id
         where p.staff_id = sf.id and (p.created_at at time zone 'Asia/Beirut')::date between f and t
        union all
        select jsonb_build_object('t','move','id',m.id,'at',m.created_at,'kind',m.kind,'debit',
               case when m.amount < 0 then -m.amount else 0 end,'credit', case when m.amount > 0 then m.amount else 0 end,
               'note',m.note,'by',m.by_name)
          from public.motor_moves m
         where m.staff_id = sf.id and m.account = 'collector' and (m.created_at at time zone 'Asia/Beirut')::date between f and t
      ) q), '[]'::jsonb));
end $$;

-- ============================================================
--  14) كشف حساب Whish  (له: المقبوض عبر Whish — عليه: السحوبات)
-- ============================================================
create or replace function public.motor_whish_statement(p_slug text, p_token text, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; f date; t date; opening numeric;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  f := coalesce(p_from, date '2000-01-01'); t := coalesce(p_to, date '2999-12-31');
  opening := coalesce((select sum(amount) from public.motor_payments where site_id = sid and method = 'whish' and not voided
                         and (created_at at time zone 'Asia/Beirut')::date < f), 0)
           + coalesce((select sum(case when kind = 'withdraw' then -abs(amount) else amount end) from public.motor_moves
                         where site_id = sid and account = 'whish' and (created_at at time zone 'Asia/Beirut')::date < f), 0);
  return jsonb_build_object('opening', opening,
    'balance_now', coalesce((select sum(amount) from public.motor_payments where site_id = sid and method = 'whish' and not voided), 0)
                 + coalesce((select sum(case when kind = 'withdraw' then -abs(amount) else amount end) from public.motor_moves
                              where site_id = sid and account = 'whish'), 0),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'customer',c.name,'code',c.code,'customer_id',c.id,
               'debit',0,'credit',p.amount,'paid_currency',p.paid_currency,'paid_amount',p.paid_amount,
               'staff',p.staff_name,'note',p.note,'voided',p.voided) as x
          from public.motor_payments p join public.motor_customers c on c.id = p.customer_id
         where p.site_id = sid and p.method = 'whish' and (p.created_at at time zone 'Asia/Beirut')::date between f and t
        union all
        select jsonb_build_object('t','move','id',m.id,'at',m.created_at,'kind',m.kind,
               'debit', case when m.kind = 'withdraw' then abs(m.amount) when m.amount < 0 then -m.amount else 0 end,
               'credit', case when m.kind = 'withdraw' then 0 when m.amount > 0 then m.amount else 0 end,
               'note',m.note,'staff',m.by_name)
          from public.motor_moves m
         where m.site_id = sid and m.account = 'whish' and (m.created_at at time zone 'Asia/Beirut')::date between f and t
      ) q), '[]'::jsonb));
end $$;

-- حركة: تسليم جابي (handover, amount > 0) / سحب أو إيداع Whish / تسوية
create or replace function public.motor_move_add(p_slug text, p_token text, p_account text, p_staff uuid,
  p_kind text, p_amount numeric, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; m public.motor_moves%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_account not in ('collector','whish','cash') then perform public._motor_err('bad_account'); end if;
  if coalesce(p_amount,0) = 0 then perform public._motor_err('bad_amount'); end if;
  if p_account = 'collector' then
    if p_kind not in ('handover','adjust') then perform public._motor_err('bad_kind'); end if;
    if not exists (select 1 from public.motor_staff where id = p_staff and site_id = sid) then perform public._motor_err('bad_staff'); end if;
  elsif p_account = 'whish' then
    if p_kind not in ('withdraw','deposit','adjust') then perform public._motor_err('bad_kind'); end if;
    p_staff := null;
  else
    if p_kind not in ('in','out','adjust') then perform public._motor_err('bad_kind'); end if;
    p_staff := null;
  end if;
  insert into public.motor_moves (site_id, account, staff_id, kind, amount, note, by_name)
  values (sid, p_account, p_staff, p_kind, case when p_kind in ('handover','withdraw','deposit','in','out') then abs(p_amount) else p_amount end,
          coalesce(p_note,''), w->>'name')
  returning * into m;
  return jsonb_build_object('ok', true, 'move', to_jsonb(m) - 'site_id');
end $$;

create or replace function public.motor_move_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  if exists (select 1 from public.motor_moves m where m.id = p_id and (m.kind = 'close'
       or ((m.account = 'cash' or (m.account = 'collector' and m.kind = 'handover')) and m.created_at <= coalesce((select max(created_at)
            from public.motor_moves where site_id = m.site_id and account = 'cash' and kind = 'close'), '-infinity'::timestamptz)))) then
    perform public._motor_err('closed_period');
  end if;
  if exists (select 1 from public.motor_moves m join public.motor_day_closes dc on dc.site_id = m.site_id
              and dc.day = (m.created_at at time zone 'Asia/Beirut')::date where m.id = p_id) then
    perform public._motor_err('day_closed');
  end if;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  select m.site_id, 'move', m.id, m.account || ' / ' || m.kind || ' — ' || m.amount, to_jsonb(m), w->>'name'
    from public.motor_moves m where m.id = p_id and m.site_id = (w->>'site_id')::uuid;
  delete from public.motor_moves where id = p_id and site_id = (w->>'site_id')::uuid;
  return jsonb_build_object('ok', found);
end $$;

-- ============================================================
--  15) الصندوق (المكتب)
--      له: القبض النقدي من المدير/صاحب الاشتراك + تسليمات الجباة + إيداع
--      عليه: مصاريف/سحب + السحب عند الإقفال
-- ============================================================
create or replace function public._motor_cash_bal(p_sid uuid, p_before timestamptz default null)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select sum(p.amount) from public.motor_payments p left join public.motor_staff s on s.id = p.staff_id
                    where p.site_id = p_sid and p.method = 'cash' and not p.voided and (p.staff_id is null or s.role = 'admin')
                      and (p_before is null or p.created_at < p_before)), 0)
       + coalesce((select sum(m.amount) from public.motor_moves m where m.site_id = p_sid and m.account = 'collector' and m.kind = 'handover'
                      and (p_before is null or m.created_at < p_before)), 0)
       + coalesce((select sum(case when m.kind in ('out','close') then -abs(m.amount) else m.amount end)
                     from public.motor_moves m where m.site_id = p_sid and m.account = 'cash'
                      and (p_before is null or m.created_at < p_before)), 0);
$$;
revoke all on function public._motor_cash_bal(uuid, timestamptz) from public, anon, authenticated;

create or replace function public.motor_cash_statement(p_slug text, p_token text, p_from date default null, p_to date default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; f date; t date;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  f := coalesce(p_from, date '2000-01-01'); t := coalesce(p_to, date '2999-12-31');
  return jsonb_build_object(
    'opening', public._motor_cash_bal(sid, (f::timestamp at time zone 'Asia/Beirut')),
    'balance_now', public._motor_cash_bal(sid, null),
    'last_close', (select jsonb_build_object('at', m.created_at, 'by', m.by_name, 'extra', m.extra, 'amount', m.amount)
                     from public.motor_moves m where m.site_id = sid and m.account = 'cash' and m.kind = 'close'
                     order by m.created_at desc limit 1),
    'rows', coalesce((select jsonb_agg(x order by x->>'at') from (
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'customer',c.name,'code',c.code,'customer_id',c.id,
               'credit',p.amount,'debit',0,'paid_currency',p.paid_currency,'paid_amount',p.paid_amount,
               'staff',p.staff_name,'note',p.note,'voided',p.voided) as x
          from public.motor_payments p join public.motor_customers c on c.id = p.customer_id
          left join public.motor_staff s on s.id = p.staff_id
         where p.site_id = sid and p.method = 'cash' and (p.staff_id is null or s.role = 'admin')
           and (p.created_at at time zone 'Asia/Beirut')::date between f and t
        union all
        select jsonb_build_object('t','move','id',m.id,'at',m.created_at,'kind', case when m.account = 'collector' then 'handover' else m.kind end,
               'credit', case when m.account = 'collector' or m.kind = 'in' or (m.kind = 'adjust' and m.amount > 0) then abs(m.amount) else 0 end,
               'debit',  case when m.kind in ('out','close') or (m.kind = 'adjust' and m.amount < 0) then abs(m.amount) else 0 end,
               'staff', case when m.account = 'collector' then (select name from public.motor_staff where id = m.staff_id) else m.by_name end,
               'by', m.by_name, 'note', m.note, 'extra', m.extra)
          from public.motor_moves m
         where m.site_id = sid and (m.account = 'cash' or (m.account = 'collector' and m.kind = 'handover'))
           and (m.created_at at time zone 'Asia/Beirut')::date between f and t
      ) q), '[]'::jsonb));
end $$;

-- إقفال الصندوق (المدير فقط): المعدود فعلياً + المسحوب. الفرق بينسجّل تسوية، والباقي بيكمّل للفترة الجاية
create or replace function public.motor_cash_close(p_slug text, p_token text, p_counted numeric, p_withdraw numeric, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; expct numeric; diff numeric;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  perform 1 from public.motor_sites where id = sid for update;
  if p_counted is null or p_counted < 0 or coalesce(p_withdraw,0) < 0 or coalesce(p_withdraw,0) > p_counted then
    perform public._motor_err('bad_amount');
  end if;
  expct := public._motor_cash_bal(sid, null);
  diff := p_counted - expct;
  if diff <> 0 then
    insert into public.motor_moves (site_id, account, kind, amount, note, by_name, created_at)
    values (sid, 'cash', 'adjust', diff, 'فرق الإقفال', w->>'name', clock_timestamp());
  end if;
  insert into public.motor_moves (site_id, account, kind, amount, note, by_name, extra, created_at)
  values (sid, 'cash', 'close', coalesce(p_withdraw,0), coalesce(p_note,''), w->>'name',
          jsonb_build_object('expected', expct, 'counted', p_counted, 'diff', diff, 'carried', p_counted - coalesce(p_withdraw,0)),
          clock_timestamp() + interval '1 millisecond');
  return jsonb_build_object('ok', true, 'expected', expct, 'counted', p_counted, 'diff', diff,
                            'carried', p_counted - coalesce(p_withdraw,0));
end $$;

-- ============================================================
--  16) فتح/قطع الاشتراك + ملاحظات الموظفين
-- ============================================================
create or replace function public.motor_set_active(p_slug text, p_token text, p_customer uuid, p_active boolean,
  p_note text default '', p_lat double precision default null, p_lng double precision default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not (w->>'can_cut')::boolean then perform public._motor_err('forbidden'); end if;
  select * into c from public.motor_customers where id = p_customer and site_id = sid for update;
  if not found then perform public._motor_err('customer_not_found'); end if;
  if c.is_active = coalesce(p_active,false) then return jsonb_build_object('ok', true, 'is_active', c.is_active); end if;
  update public.motor_customers set is_active = p_active,
         stopped_at = case when p_active then null else now() end,
         stopped_by = case when p_active then '' else w->>'name' end,
         updated_at = now()
   where id = c.id;
  insert into public.motor_switch_log (site_id, customer_id, action, note, lat, lng, staff_id, staff_name)
  values (sid, c.id, case when p_active then 'connect' else 'cut' end, coalesce(p_note,''), p_lat, p_lng,
          (w->>'staff_id')::uuid, w->>'name');
  return jsonb_build_object('ok', true, 'is_active', p_active);
end $$;

create or replace function public.motor_note_add(p_slug text, p_token text, p_customer uuid, p_body text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(trim(p_body),'') = '' then perform public._motor_err('bad_data'); end if;
  if not exists (select 1 from public.motor_customers where id = p_customer and site_id = sid) then
    perform public._motor_err('customer_not_found');
  end if;
  insert into public.motor_notes (site_id, customer_id, body, staff_id, staff_name)
  values (sid, p_customer, left(trim(p_body), 500), (w->>'staff_id')::uuid, w->>'name');
  update public.motor_customers set updated_at = now() where id = p_customer;
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  17) مواقع الموظفين على الخريطة
-- ============================================================
create or replace function public.motor_ping(p_slug text, p_token text, p_lat double precision, p_lng double precision,
  p_acc double precision default null)
returns void language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_who(p_slug, p_token);
  if w->>'staff_id' is null or not public._motor_geo_ok(p_lat, p_lng) then return; end if;
  update public.motor_staff set last_lat = p_lat, last_lng = p_lng, last_acc = p_acc, last_seen = now()
   where id = (w->>'staff_id')::uuid;
end $$;

create or replace function public.motor_staff_map(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  if not coalesce((w->>'is_main')::boolean, false) then perform public._motor_err('forbidden'); end if;
  sid := (w->>'site_id')::uuid;
  return jsonb_build_object('staff', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'role', s.role,
           'lat', s.last_lat, 'lng', s.last_lng, 'acc', s.last_acc, 'seen', s.last_seen, 'is_active', s.is_active,
           'reads_today', (select count(*) from public.motor_readings r where r.staff_id = s.id
                             and (r.created_at at time zone 'Asia/Beirut')::date = public._motor_today()),
           'pays_today', (select count(*) from public.motor_payments p where p.staff_id = s.id and not p.voided
                             and (p.created_at at time zone 'Asia/Beirut')::date = public._motor_today())))
         from public.motor_staff s where s.site_id = sid and s.last_lat is not null), '[]'::jsonb),
    'readings', coalesce((select jsonb_agg(jsonb_build_object('lat', r.lat, 'lng', r.lng, 'name', c.name, 'staff', r.staff_name, 'at', r.created_at))
         from public.motor_readings r join public.motor_customers c on c.id = r.customer_id
         where r.site_id = sid and r.lat is not null and (r.created_at at time zone 'Asia/Beirut')::date = public._motor_today()), '[]'::jsonb));
end $$;

-- ============================================================
--  18) التحقق بخطوتين للموظفين
-- ============================================================
create or replace function public.motor_2fa_setup(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare w jsonb; sec text; st public.motor_sites%rowtype; u text;
begin
  w := public._motor_who(p_slug, p_token);
  if w->>'staff_id' is null then perform public._motor_err('forbidden'); end if;
  -- نفس المفتاح إذا ضغط «تفعيل» أكثر من مرة (حتى ما يصير الـQR الممسوح قديم)
  select totp_pending into sec from public.motor_staff_secrets where staff_id = (w->>'staff_id')::uuid;
  if coalesce(sec,'') = '' then
    sec := public._motor_b32_encode(gen_random_bytes(20));
    update public.motor_staff_secrets set totp_pending = sec where staff_id = (w->>'staff_id')::uuid;
  end if;
  select * into st from public.motor_sites where id = (w->>'site_id')::uuid;
  select username into u from public.motor_staff where id = (w->>'staff_id')::uuid;
  -- الرابط بأحرف إنكليزية فقط (الأحرف العربية كانت تخرب الـQR)
  return jsonb_build_object('secret', sec,
    'uri', 'otpauth://totp/LibanApps%20Motor:' || st.slug || '-' || regexp_replace(u, '[^a-z0-9._-]', '', 'g') ||
           '?secret=' || sec || '&issuer=LibanApps%20Motor&algorithm=SHA1&digits=6&period=30');
end $$;

create or replace function public.motor_2fa_enable(p_slug text, p_token text, p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sc public.motor_staff_secrets%rowtype;
begin
  w := public._motor_who(p_slug, p_token);
  if w->>'staff_id' is null then perform public._motor_err('forbidden'); end if;
  select * into sc from public.motor_staff_secrets where staff_id = (w->>'staff_id')::uuid;
  if coalesce(sc.totp_pending,'') = '' or not public._motor_totp_ok(sc.totp_pending, trim(coalesce(p_code,''))) then
    perform public._motor_err('bad_totp');
  end if;
  update public.motor_staff_secrets set totp_secret = totp_pending, totp_pending = null where staff_id = sc.staff_id;
  update public.motor_staff set totp_enabled = true where id = sc.staff_id;
  return jsonb_build_object('ok', true);
end $$;

-- الموظف يلغي 2FA عن حالو (بالرمز) — أو المدير يلغيه لأي موظف (p_staff)
create or replace function public.motor_2fa_disable(p_slug text, p_token text, p_code text default null, p_staff uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; target uuid; sc public.motor_staff_secrets%rowtype;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_staff is not null and p_staff::text is distinct from w->>'staff_id' then
    if not (w->>'is_admin')::boolean then perform public._motor_err('forbidden'); end if;
    if not exists (select 1 from public.motor_staff where id = p_staff and site_id = sid) then perform public._motor_err('bad_staff'); end if;
    if exists (select 1 from public.motor_staff where id = p_staff and role = 'admin') and not coalesce((w->>'is_main')::boolean,false) then
      perform public._motor_err('main_only');
    end if;
    target := p_staff;
  else
    target := (w->>'staff_id')::uuid;
    if target is null then perform public._motor_err('forbidden'); end if;
    select * into sc from public.motor_staff_secrets where staff_id = target;
    if not public._motor_totp_ok(sc.totp_secret, trim(coalesce(p_code,''))) then perform public._motor_err('bad_totp'); end if;
  end if;
  update public.motor_staff_secrets set totp_secret = null, totp_pending = null where staff_id = target;
  update public.motor_staff set totp_enabled = false where id = target;
  return jsonb_build_object('ok', true);
end $$;

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
        from (select distinct on (i0.customer_id) i0.* from public.motor_invoices i0
               where i0.site_id = sid and not i0.voided and i0.kind in ('meter','fixed') and i0.wa_sent_at is null
                 and i0.created_at > now() - make_interval(days => greatest(1, coalesce(p_days,60)))
               order by i0.customer_id, i0.created_at desc) i
        join public.motor_customers c on c.id = i.customer_id
      union all
      select jsonb_build_object('t','pay','id',p.id,'at',p.created_at,'pay',to_jsonb(p) - 'site_id',
             'inv', (select to_jsonb(i) - 'site_id' from public.motor_invoices i where i.customer_id = p.customer_id
                      and not i.voided and i.kind in ('meter','fixed') and i.created_at <= p.created_at
                      order by i.created_at desc limit 1),
             'customer', jsonb_build_object('id',c.id,'code',c.code,'name',c.name,'mobile',c.mobile,'mobile_cc',c.mobile_cc,'box',c.box))
        from (select distinct on (p0.customer_id) p0.* from public.motor_payments p0
               where p0.site_id = sid and not p0.voided and p0.wa_sent_at is null
                 and p0.created_at > now() - make_interval(days => greatest(1, coalesce(p_days,60)))
               order by p0.customer_id, p0.created_at desc) p
        join public.motor_customers c on c.id = p.customer_id
       where not exists (   -- انبعتلو إشعار دفع بهالدورة (بعد آخر فاتورة)
               select 1 from public.motor_payments px
                where px.customer_id = p.customer_id and not px.voided and px.wa_sent_at is not null
                  and px.created_at >= coalesce((select max(ix.created_at) from public.motor_invoices ix
                                                  where ix.customer_id = p.customer_id and not ix.voided and ix.kind in ('meter','fixed')), '-infinity'::timestamptz))
    ) q), '[]'::jsonb);
end $$;

create or replace function public.motor_wa_mark(p_slug text, p_token text, p_kind text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; cid uuid; at0 timestamptz;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if p_kind = 'inv' then
    select customer_id, created_at into cid, at0 from public.motor_invoices where id = p_id and site_id = sid;
    -- الفاتورة وكل الفواتير الأقدم يلّي ما انبعتت لنفس الزبون
    update public.motor_invoices set wa_sent_at = now(), wa_sent_by = w->>'name'
     where site_id = sid and customer_id = cid and wa_sent_at is null and kind in ('meter','fixed') and created_at <= at0;
  elsif p_kind = 'pay' then
    select customer_id into cid from public.motor_payments where id = p_id and site_id = sid;
    update public.motor_payments set wa_sent_at = now(), wa_sent_by = w->>'name'
     where site_id = sid and customer_id = cid and wa_sent_at is null;
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

