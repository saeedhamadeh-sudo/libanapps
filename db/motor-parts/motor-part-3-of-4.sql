-- motorapp — الجزء 3 من 4. شغّل الأجزاء بالترتيب (1 ثم 2 …) كل جزء لحاله في Supabase SQL Editor.
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
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'customer',c.name,'code',c.code,
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
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'customer',c.name,'code',c.code,
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
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'customer',c.name,'code',c.code,
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
  sec := public._motor_b32_encode(gen_random_bytes(20));
  update public.motor_staff_secrets set totp_pending = sec where staff_id = (w->>'staff_id')::uuid;
  select * into st from public.motor_sites where id = (w->>'site_id')::uuid;
  select username into u from public.motor_staff where id = (w->>'staff_id')::uuid;
  return jsonb_build_object('secret', sec,
    'uri', 'otpauth://totp/' || replace(coalesce(nullif(st.name,''), st.slug),' ','%20') || ':' || u ||
           '?secret=' || sec || '&issuer=LibanApps%20Motor&digits=6&period=30');
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
create or replace function public.motor_wa_outbox(p_slug text, p_token text, p_days integer default 60)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  return coalesce((select jsonb_agg(x order by x->>'at') from (
      select jsonb_build_object('t','inv','id',i.id,'at',i.created_at,'inv',to_jsonb(i) - 'site_id',
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

