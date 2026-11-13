-- motorapp — الجزء 2 من 5 (شغّل الأجزاء بالترتيب)
-- ============================================================
--  5) الصفحة العامة + الدخول والخروج
-- ============================================================
create or replace function public.motor_public(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st public.motor_sites%rowtype; lic jsonb;
begin
  select * into st from public.motor_sites where slug = lower(trim(coalesce(p_slug,'')));
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  lic := public.motor_license(st.id);
  return jsonb_build_object(
    'ok', st.is_active and coalesce((lic->>'ok')::boolean,false),
    'reason', case when not st.is_active then 'inactive' else lic->>'reason' end,
    'site', jsonb_build_object('name', st.name, 'logo_url', st.logo_url, 'slug', st.slug,
                               'default_lang', st.default_lang));
end $$;

drop function if exists public.motor_login(text, text, text);
drop function if exists public.motor_login(text, text, text, text);
create or replace function public.motor_login(p_slug text, p_username text, p_password text, p_totp text default null,
  p_device text default null, p_device_label text default '')
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare st public.motor_sites%rowtype; sf public.motor_staff%rowtype; sc public.motor_staff_secrets%rowtype;
        tok text; lic jsonb; cu public.motor_customers%rowtype; cs public.motor_customer_secrets%rowtype;
begin
  select * into st from public.motor_sites where slug = lower(trim(coalesce(p_slug,'')));
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  lic := public.motor_license(st.id);
  if not st.is_active or not coalesce((lic->>'ok')::boolean,false) then
    return jsonb_build_object('ok', false, 'reason', 'license');
  end if;
  select * into sf from public.motor_staff
   where site_id = st.id and lower(username) = lower(trim(coalesce(p_username,'')));
  if not found then
    -- حساب زبون؟
    select * into cu from public.motor_customers
     where site_id = st.id and username <> '' and lower(username) = lower(trim(coalesce(p_username,'')));
    if not found then perform pg_sleep(0.4); return jsonb_build_object('ok', false, 'reason', 'bad_login'); end if;
    select * into cs from public.motor_customer_secrets where customer_id = cu.id for update;
    if not found then return jsonb_build_object('ok', false, 'reason', 'bad_login'); end if;
    if cs.locked_until is not null and cs.locked_until > now() then
      return jsonb_build_object('ok', false, 'reason', 'locked', 'minutes', ceil(extract(epoch from (cs.locked_until - now()))/60)::int);
    end if;
    if cs.password_hash <> crypt(coalesce(p_password,''), cs.password_hash) then
      update public.motor_customer_secrets set failed_count = failed_count + 1,
             locked_until = case when failed_count + 1 >= 6 then now() + interval '15 minutes' end where customer_id = cu.id;
      return jsonb_build_object('ok', false, 'reason', 'bad_login');
    end if;
    update public.motor_customer_secrets set failed_count = 0, locked_until = null where customer_id = cu.id;
    delete from public.motor_csessions where customer_id = cu.id and expires_at < now();
    tok := encode(gen_random_bytes(24),'hex');
    insert into public.motor_csessions (token_hash, customer_id, site_id) values (encode(digest(tok,'sha256'),'hex'), cu.id, st.id);
    return jsonb_build_object('ok', true, 'token', tok, 'kind', 'customer', 'name', cu.name);
  end if;
  select * into sc from public.motor_staff_secrets where staff_id = sf.id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'bad_login'); end if;
  if sc.locked_until is not null and sc.locked_until > now() then
    return jsonb_build_object('ok', false, 'reason', 'locked',
      'minutes', ceil(extract(epoch from (sc.locked_until - now()))/60)::int);
  end if;
  if sc.password_hash <> crypt(coalesce(p_password,''), sc.password_hash) then
    update public.motor_staff_secrets
       set failed_count = failed_count + 1,
           locked_until = case when failed_count + 1 >= 6 then now() + interval '15 minutes' end
     where staff_id = sf.id;
    return jsonb_build_object('ok', false, 'reason', 'bad_login');
  end if;
  if not sf.is_active then return jsonb_build_object('ok', false, 'reason', 'inactive_user'); end if;
  -- التحقق بخطوتين
  if sf.totp_enabled and coalesce(sc.totp_secret,'') <> '' then
    if coalesce(trim(p_totp),'') = '' then return jsonb_build_object('ok', false, 'need_totp', true); end if;
    if not public._motor_totp_ok(sc.totp_secret, trim(p_totp)) then
      update public.motor_staff_secrets
         set failed_count = failed_count + 1,
             locked_until = case when failed_count + 1 >= 6 then now() + interval '15 minutes' end
       where staff_id = sf.id;
      return jsonb_build_object('ok', false, 'need_totp', true, 'reason', 'bad_totp');
    end if;
  end if;
  -- قفل الجهاز: كل مستخدم (إلا المدير الأساسي) على جهاز واحد فقط
  if not sf.is_main then
    if coalesce(p_device,'') !~ '^[A-Za-z0-9-]{16,64}$' then return jsonb_build_object('ok', false, 'reason', 'device'); end if;
    if sf.device_id is null then
      update public.motor_staff set device_id = p_device, device_label = left(coalesce(p_device_label,''), 120), device_at = now() where id = sf.id;
    elsif sf.device_id <> p_device then
      return jsonb_build_object('ok', false, 'reason', 'device');
    end if;
  end if;
  update public.motor_staff_secrets set failed_count = 0, locked_until = null where staff_id = sf.id;
  delete from public.motor_sessions where staff_id = sf.id and expires_at < now();
  tok := encode(gen_random_bytes(24),'hex');
  insert into public.motor_sessions (token_hash, staff_id, site_id)
  values (encode(digest(tok,'sha256'),'hex'), sf.id, st.id);
  return jsonb_build_object('ok', true, 'token', tok, 'kind', 'staff', 'role', sf.role, 'name', sf.name);
end $$;

create or replace function public.motor_logout(p_token text)
returns void language sql security definer set search_path = public, extensions as $$
  delete from public.motor_sessions where token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex');
  delete from public.motor_csessions where token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex');
$$;

create or replace function public.motor_change_password(p_slug text, p_token text, p_old text, p_new text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare w jsonb; sc public.motor_staff_secrets%rowtype;
begin
  w := public._motor_who(p_slug, p_token);
  if w->>'staff_id' is null then perform public._motor_err('forbidden'); end if;
  select * into sc from public.motor_staff_secrets where staff_id = (w->>'staff_id')::uuid;
  if sc.password_hash <> crypt(coalesce(p_old,''), sc.password_hash) then perform public._motor_err('bad_old'); end if;
  if length(coalesce(p_new,'')) < 4 then perform public._motor_err('short_password'); end if;
  update public.motor_staff_secrets set password_hash = crypt(p_new, gen_salt('bf', 8)), updated_at = now()
   where staff_id = sc.staff_id;
  delete from public.motor_sessions where staff_id = sc.staff_id
    and token_hash <> encode(digest(p_token,'sha256'),'hex');
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  6) بيانات البداية: الهوية + الإعدادات + الأنواع + الموظفين
-- ============================================================
create or replace function public.motor_me(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; st public.motor_sites%rowtype; sid uuid; adm boolean;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid; adm := (w->>'is_admin')::boolean;
  select * into st from public.motor_sites where id = sid;
  return jsonb_build_object(
    'me', w,
    'today', public._motor_today(),
    'license', public.motor_license(sid),
    'site', to_jsonb(st) - 'client_id' - 'cust_seq' - 'invoice_seq' - 'receipt_seq' - 'wc_api_key' - 'wc_hook_secret' - 'gd_refresh',
    'plans', coalesce((select jsonb_agg(to_jsonb(p) - 'site_id' order by p.sort, p.name)
                         from public.motor_plans p where p.site_id = sid), '[]'::jsonb),
    'staff', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'role', s.role,
                         'username', case when adm then s.username end, 'phone', s.phone,
                         'is_active', s.is_active, 'read_from', s.read_from, 'read_to', s.read_to,
                         'can_collect', s.can_collect, 'can_read', s.can_read, 'can_cut', s.can_cut,
                         'totp_enabled', s.totp_enabled, 'is_main', s.is_main,
                         'salary', case when adm then s.salary end,
                         'device_set', s.device_id is not null, 'device_label', case when adm then s.device_label end,
                         'device_at', case when adm then s.device_at end,
                         'last_lat', case when coalesce((w->>'is_main')::boolean,false) then s.last_lat end, 'last_lng', case when coalesce((w->>'is_main')::boolean,false) then s.last_lng end,
                         'last_acc', case when coalesce((w->>'is_main')::boolean,false) then s.last_acc end, 'last_seen', case when coalesce((w->>'is_main')::boolean,false) then s.last_seen end)
                         order by s.role, s.name)
                         from public.motor_staff s where s.site_id = sid
                          and (adm or s.id = (w->>'staff_id')::uuid)), '[]'::jsonb));
end $$;

-- ============================================================
--  7) الزبائن
-- ============================================================
-- القائمة الخفيفة (للبحث وقوائم «بعد ما انقرى» و«بعد ما دفع») — p_since: للتحديث المباشر
create or replace function public._motor_cust_rows(p_sid uuid, p_own uuid, p_since timestamptz)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'code', c.code, 'name', c.name, 'alt_name', c.alt_name, 'barcode', c.barcode,
      'meter_no', c.meter_no, 'box', c.box, 'area', c.area, 'location_name', c.location_name,
      'zone', c.zone, 'plan_id', c.plan_id, 'balance', c.balance, 'mobile', c.mobile, 'mobile_cc', c.mobile_cc,
      'is_active', c.is_active, 'archived', c.archived, 'collector_id', c.collector_id,
      'collector_name', coalesce(sf.name, c.collector_name),
      'last_value', coalesce(c.next_prev, lr.value, c.initial_reading),
      'read_now', (rn.id is not null), 'read_now_value', rn.value, 'read_now_prev', rn.prev_value,
      'last_note', nt.body, 'last_note_by', nt.staff_name, 'last_note_at', nt.created_at,
      'updated_at', c.updated_at, 'deleted', c.deleted_at is not null) order by c.code, c.name), '[]'::jsonb)
  from public.motor_customers c
  join public.motor_sites st on st.id = c.site_id
  left join public.motor_staff sf on sf.id = c.collector_id
  left join lateral (select r.value from public.motor_readings r where r.customer_id = c.id
                     order by r.created_at desc limit 1) lr on true
  left join public.motor_readings rn on rn.customer_id = c.id and rn.period = st.bill_period
  left join lateral (select n.body, n.staff_name, n.created_at from public.motor_notes n where n.customer_id = c.id
                     order by n.created_at desc limit 1) nt on true
  where c.site_id = p_sid and (p_own is null or c.collector_id = p_own)
    and (p_since is null or c.updated_at > p_since)
    and (c.deleted_at is null or p_since is not null);
$$;
revoke all on function public._motor_cust_rows(uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function public.motor_customers(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; own uuid;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if w->>'role' = 'collector' and not (select collector_sees_all from public.motor_sites where id = sid) then
    own := (w->>'staff_id')::uuid;
  end if;
  return public._motor_cust_rows(sid, own, null);
end $$;

-- التحديث المباشر: كل شي تغيّر من آخر مرة (كل 15 ثانية من كل جهاز)
create or replace function public.motor_changes(p_slug text, p_token text, p_since timestamptz)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; own uuid; t timestamptz := clock_timestamp(); st public.motor_sites%rowtype;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  if w->>'role' = 'collector' and not st.collector_sees_all then own := (w->>'staff_id')::uuid; end if;
  return jsonb_build_object('now', t, 'period', st.bill_period, 'lbp_rate', st.lbp_rate,
    'me', w,
    'customers', public._motor_cust_rows(sid, own, coalesce(p_since, t - interval '1 minute')),
    'wa_inv', case when (w->>'is_admin')::boolean then
        (select count(*) from public.motor_invoices i where i.site_id = sid and not i.voided and i.kind in ('meter','fixed')
            and i.wa_sent_at is null and i.created_at > now() - interval '60 days') end,
    'wa_pending', case when (w->>'is_admin')::boolean then
        (select count(*) from public.motor_invoices i where i.site_id = sid and not i.voided and i.kind in ('meter','fixed')
            and i.wa_sent_at is null and i.created_at > now() - interval '60 days')
      + (select count(*) from public.motor_payments p where p.site_id = sid and not p.voided
            and p.wa_sent_at is null and p.created_at > now() - interval '60 days') end);
end $$;

create or replace function public.motor_customer_get(p_slug text, p_token text, p_id uuid, p_barcode text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype; st public.motor_sites%rowtype;
        lr public.motor_readings%rowtype; rn public.motor_readings%rowtype; pl public.motor_plans%rowtype; q text;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  if p_id is not null then
    select * into c from public.motor_customers where id = p_id and site_id = sid;
  else
    q := lower(trim(coalesce(p_barcode,'')));
    if q = '' then perform public._motor_err('not_found'); end if;
    select * into c from public.motor_customers where site_id = sid and lower(barcode) = q limit 1;
    if not found then
      select * into c from public.motor_customers where site_id = sid and lower(meter_no) = q limit 1;
    end if;
  end if;
  if c.id is null or c.deleted_at is not null then perform public._motor_err('customer_not_found', coalesce(p_barcode,'')); end if;
  if w->>'role' = 'collector' and not st.collector_sees_all and c.collector_id is distinct from (w->>'staff_id')::uuid then
    perform public._motor_err('forbidden');
  end if;
  select * into pl from public.motor_plans where id = c.plan_id;
  select * into lr from public.motor_readings where customer_id = c.id order by created_at desc limit 1;
  select * into rn from public.motor_readings where customer_id = c.id and period = st.bill_period;
  return jsonb_build_object(
    'customer', to_jsonb(c) - 'site_id',
    'has_login', exists (select 1 from public.motor_customer_secrets x where x.customer_id = c.id) and c.username <> '',
    'insurance', coalesce((select sum(case when kind = 'in' then amount else -amount end) from public.motor_insurance where customer_id = c.id), 0),
    'plan', case when pl.id is null then null else to_jsonb(pl) - 'site_id' end,
    'collector_name', coalesce((select name from public.motor_staff where id = c.collector_id), c.collector_name),
    'prev_value', coalesce(c.next_prev, lr.value, c.initial_reading),
    'baseline', lr.id is null and st.first_read_baseline and coalesce(c.initial_reading,0) = 0 and c.next_prev is null,
    'last_reading', case when lr.id is null then null else to_jsonb(lr) - 'site_id' end,
    'period', st.bill_period,
    'read_now', case when rn.id is null then null else to_jsonb(rn) - 'site_id' end,
    'unpaid_invoice', (select to_jsonb(i) - 'site_id' from public.motor_invoices i
                        where i.customer_id = c.id and not i.voided and i.kind in ('meter','fixed')
                        order by i.created_at desc limit 1),
    'notes', coalesce((select jsonb_agg(jsonb_build_object('body', n.body, 'by', n.staff_name, 'at', n.created_at)
                        order by n.created_at desc) from (select * from public.motor_notes where customer_id = c.id
                        order by created_at desc limit 15) n), '[]'::jsonb),
    'switches', coalesce((select jsonb_agg(jsonb_build_object('action', x.action, 'note', x.note, 'by', x.staff_name, 'at', x.created_at)
                        order by x.created_at desc) from (select * from public.motor_switch_log where customer_id = c.id
                        order by created_at desc limit 10) x), '[]'::jsonb));
end $$;

-- p_data: حقول الزبون (id فاضي = جديد). balance لا يتغيّر من هنا — opening_balance للزبون الجديد فقط
create or replace function public.motor_customer_save(p_slug text, p_token text, p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype; d jsonb := coalesce(p_data,'{}'::jsonb);
        newc boolean; seq integer; ob numeric; pre text; was_active boolean;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(trim(d->>'name'),'') = '' then perform public._motor_err('name_required'); end if;
  newc := coalesce(d->>'id','') = '';
  if not newc then
    select * into c from public.motor_customers where id = (d->>'id')::uuid and site_id = sid for update;
    if not found then perform public._motor_err('customer_not_found'); end if;
    was_active := c.is_active;
  else
    update public.motor_sites set cust_seq = cust_seq + 1 where id = sid returning cust_seq, barcode_prefix into seq, pre;
    c.id := gen_random_uuid(); c.site_id := sid; c.code := seq; c.balance := 0; c.created_at := now(); c.username := '';
    was_active := true;
  end if;
  if d ? 'plan_id' and nullif(d->>'plan_id','') is not null
     and not exists (select 1 from public.motor_plans where id = (d->>'plan_id')::uuid and site_id = sid) then
    perform public._motor_err('bad_plan');
  end if;
  if d ? 'collector_id' and nullif(d->>'collector_id','') is not null
     and not exists (select 1 from public.motor_staff where id = (d->>'collector_id')::uuid and site_id = sid) then
    perform public._motor_err('bad_staff');
  end if;

  c.name            := trim(d->>'name');
  c.alt_name        := coalesce(d->>'alt_name', c.alt_name, '');
  c.plan_id         := case when d ? 'plan_id' then nullif(d->>'plan_id','')::uuid else c.plan_id end;
  c.building        := coalesce(d->>'building', c.building, '');
  c.floor           := coalesce(d->>'floor', c.floor, '');
  c.side            := coalesce(d->>'side', c.side, '');
  c.box             := coalesce(d->>'box', c.box, '');
  c.generator       := coalesce(d->>'generator', c.generator, '');
  c.breaker_no      := coalesce(d->>'breaker_no', c.breaker_no, '');
  c.meter_no        := coalesce(d->>'meter_no', c.meter_no, '');
  c.barcode         := trim(coalesce(d->>'barcode', c.barcode, ''));
  c.location_name   := coalesce(d->>'location_name', c.location_name, '');
  c.location_code   := coalesce(d->>'location_code', c.location_code, '');
  c.lat             := case when d ? 'lat' then nullif(d->>'lat','')::double precision else c.lat end;
  c.lng             := case when d ? 'lng' then nullif(d->>'lng','')::double precision else c.lng end;
  c.area            := coalesce(d->>'area', c.area, '');
  c.area_code       := coalesce(d->>'area_code', c.area_code, '');
  c.zone            := coalesce(d->>'zone', c.zone, '');
  c.category        := coalesce(d->>'category', c.category, '');
  c.category2       := coalesce(d->>'category2', c.category2, '');
  c.collector_id    := case when d ? 'collector_id' then nullif(d->>'collector_id','')::uuid else c.collector_id end;
  c.collector_name  := coalesce(d->>'collector_name', c.collector_name, '');
  c.sub_date        := case when d ? 'sub_date' then nullif(d->>'sub_date','')::date else c.sub_date end;
  c.is_active       := coalesce((d->>'is_active')::boolean, c.is_active, true);
  c.credit_limit    := case when d ? 'credit_limit' then nullif(d->>'credit_limit','')::numeric else c.credit_limit end;
  c.charge_discount := coalesce(nullif(d->>'charge_discount','')::numeric, case when d ? 'charge_discount' then 0 end, c.charge_discount, 0);
  c.discount_desc   := coalesce(d->>'discount_desc', c.discount_desc, '');
  c.charge_addition := coalesce(nullif(d->>'charge_addition','')::numeric, case when d ? 'charge_addition' then 0 end, c.charge_addition, 0);
  c.addition_desc   := coalesce(d->>'addition_desc', c.addition_desc, '');
  c.initial_reading := coalesce(nullif(d->>'initial_reading','')::numeric, c.initial_reading, 0);
  c.mobile          := regexp_replace(coalesce(d->>'mobile', c.mobile, ''), '[^0-9]', '', 'g');
  c.mobile_cc       := coalesce(nullif(regexp_replace(coalesce(d->>'mobile_cc',''), '[^0-9]', '', 'g'),''), c.mobile_cc, '961');
  c.mobile2         := coalesce(d->>'mobile2', c.mobile2, '');
  c.phone           := coalesce(d->>'phone', c.phone, '');
  c.address         := coalesce(d->>'address', c.address, '');
  c.email           := coalesce(d->>'email', c.email, '');
  c.nationality     := coalesce(d->>'nationality', c.nationality, '');
  c.archived        := coalesce((d->>'archived')::boolean, c.archived, false);
  c.collect_day     := case when d ? 'collect_day' then nullif(d->>'collect_day','')::integer else c.collect_day end;
  c.notes           := coalesce(d->>'notes', c.notes, '');
  if was_active and not c.is_active then
    c.stopped_at := now(); c.stopped_by := w->>'name';
  elsif c.is_active then
    c.stopped_at := null; c.stopped_by := '';
  end if;
  -- الاستيراد: تاريخ التوقيف ومين أوقفه كما هم بالملف
  if not c.is_active and nullif(d->>'stopped_at','') is not null then
    begin
      c.stopped_at := (d->>'stopped_at')::timestamp at time zone 'Asia/Beirut';
    exception when others then null;
    end;
    c.stopped_by := coalesce(nullif(d->>'stopped_by',''), c.stopped_by, '');
  end if;
  if newc and c.barcode = '' then c.barcode := pre || '-' || lpad(seq::text, 5, '0'); end if;
  if c.barcode <> '' and exists (select 1 from public.motor_customers x where x.site_id = sid
        and lower(x.barcode) = lower(c.barcode) and x.id <> c.id) then
    perform public._motor_err('barcode_taken', c.barcode);
  end if;
  c.updated_at := now();

  if newc then
    insert into public.motor_customers values (c.*);
    ob := coalesce(nullif(d->>'opening_balance','')::numeric, 0);
    if ob <> 0 then
      update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
      insert into public.motor_invoices (site_id, no, customer_id, kind, amount, balance_before, balance_after, note, staff_id, staff_name)
      values (sid, seq, c.id, 'opening', ob, 0, ob, coalesce(d->>'opening_note','رصيد افتتاحي'),
              (w->>'staff_id')::uuid, w->>'name');
      update public.motor_customers set balance = ob where id = c.id;
      c.balance := ob;
    end if;
  else
    update public.motor_customers x set
      name = c.name, alt_name = c.alt_name, plan_id = c.plan_id, building = c.building, floor = c.floor, side = c.side,
      box = c.box, generator = c.generator, breaker_no = c.breaker_no, meter_no = c.meter_no, barcode = c.barcode,
      location_name = c.location_name, location_code = c.location_code, lat = c.lat, lng = c.lng, area = c.area,
      area_code = c.area_code, zone = c.zone, category = c.category, category2 = c.category2,
      collector_id = c.collector_id, collector_name = c.collector_name, sub_date = c.sub_date, is_active = c.is_active,
      stopped_at = c.stopped_at, stopped_by = c.stopped_by, credit_limit = c.credit_limit,
      charge_discount = c.charge_discount, discount_desc = c.discount_desc, charge_addition = c.charge_addition,
      addition_desc = c.addition_desc, initial_reading = c.initial_reading, mobile = c.mobile, mobile_cc = c.mobile_cc,
      mobile2 = c.mobile2, phone = c.phone, address = c.address, email = c.email, nationality = c.nationality,
      archived = c.archived, collect_day = c.collect_day, notes = c.notes, updated_at = c.updated_at
    where x.id = c.id;
  end if;
  return to_jsonb(c) - 'site_id';
end $$;

create or replace function public.motor_customer_delete(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into c from public.motor_customers where id = p_id and site_id = sid and deleted_at is null for update;
  if not found then perform public._motor_err('customer_not_found'); end if;
  update public.motor_customers set deleted_at = now(), updated_at = now() where id = c.id;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  values (sid, 'customer', c.id, '#' || c.code || ' ' || c.name, jsonb_build_object('balance', c.balance, 'barcode', c.barcode), w->>'name');
  return jsonb_build_object('ok', true, 'trash', true);
end $$;

-- استيراد من Excel: p_rows مصفوفة كائنات بنفس أسماء حقول motor_customer_save
-- + service (اسم نوع الاشتراك) + collector_name + opening_balance
-- الزبون الموجود (نفس الباركود، أو نفس رقم العداد إذا ما في باركود) بيتحدّث بدون ما يمسّ رصيده
create or replace function public.motor_import(p_slug text, p_token text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; r jsonb; ex uuid; pid uuid; stid uuid; nm text; svc text; amps numeric;
        added int := 0; updated int := 0; skipped int := 0; plans_new int := 0; errs jsonb := '[]'::jsonb; i int := 0;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if jsonb_typeof(p_rows) <> 'array' then perform public._motor_err('bad_data'); end if;
  if jsonb_array_length(p_rows) > 5000 then perform public._motor_err('too_many'); end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    i := i + 1;
    nm := trim(coalesce(r->>'name',''));
    if nm = '' then skipped := skipped + 1; continue; end if;
    begin
      -- نوع الاشتراك من عمود «الخدمة» (6A، 10A …) — بينعمل تلقائياً إذا مش موجود
      pid := null; svc := upper(trim(coalesce(r->>'service','')));
      if svc <> '' then
        select id into pid from public.motor_plans where site_id = sid and lower(name) = lower(svc);
        if pid is null then
          amps := nullif(regexp_replace(svc, '[^0-9.]', '', 'g'), '')::numeric;
          insert into public.motor_plans (site_id, name, amps, kind, fee, sort)
          values (sid, svc, coalesce(amps,0), 'meter', 0, coalesce(amps,0)::int)
          returning id into pid;
          plans_new := plans_new + 1;
        end if;
        r := r || jsonb_build_object('plan_id', pid);
      end if;
      -- الجابي حسب الاسم (إذا موجود كموظف)
      stid := null;
      if coalesce(trim(r->>'collector_name'),'') <> '' then
        select id into stid from public.motor_staff where site_id = sid and lower(trim(name)) = lower(trim(r->>'collector_name')) limit 1;
        if stid is not null then r := r || jsonb_build_object('collector_id', stid); end if;
      end if;
      -- المواقع الوهمية → بلا موقع
      if not public._motor_geo_ok(nullif(r->>'lat','')::double precision, nullif(r->>'lng','')::double precision) then
        r := r || jsonb_build_object('lat', '', 'lng', '');
      end if;
      ex := null;
      if coalesce(trim(r->>'barcode'),'') <> '' then
        select id into ex from public.motor_customers where site_id = sid and lower(barcode) = lower(trim(r->>'barcode'));
      elsif coalesce(trim(r->>'meter_no'),'') <> '' then
        select id into ex from public.motor_customers where site_id = sid and meter_no = trim(r->>'meter_no') limit 1;
      end if;
      if ex is not null then
        update public.motor_customers set deleted_at = null where id = ex and deleted_at is not null;
        delete from public.motor_trash where kind = 'customer' and ref_id = ex;
        perform public.motor_customer_save(p_slug, p_token, (r - 'opening_balance') || jsonb_build_object('id', ex));
        updated := updated + 1;
      else
        perform public.motor_customer_save(p_slug, p_token, (r - 'id') || jsonb_build_object('opening_note', 'رصيد سابق (استيراد)'));
        added := added + 1;
      end if;
    exception when others then
      skipped := skipped + 1;
      if jsonb_array_length(errs) < 30 then
        errs := errs || jsonb_build_object('row', i, 'name', nm, 'error', sqlerrm);
      end if;
    end;
  end loop;
  return jsonb_build_object('ok', true, 'added', added, 'updated', updated, 'skipped', skipped,
                            'plans_new', plans_new, 'errors', errs);
end $$;

-- ============================================================
--  8) كشف حساب الزبون (فيه العداد السابق والحالي لكل فاتورة)
-- ============================================================
create or replace function public.motor_statement(p_slug text, p_token text, p_customer uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype; st public.motor_sites%rowtype;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  select * into c from public.motor_customers where id = p_customer and site_id = sid;
  if not found then perform public._motor_err('customer_not_found'); end if;
  if w->>'role' = 'collector' and not st.collector_sees_all and c.collector_id is distinct from (w->>'staff_id')::uuid then
    perform public._motor_err('forbidden');
  end if;
  return jsonb_build_object(
    'customer', jsonb_build_object('id', c.id, 'code', c.code, 'name', c.name, 'barcode', c.barcode,
                 'meter_no', c.meter_no, 'balance', c.balance, 'mobile', c.mobile, 'mobile_cc', c.mobile_cc,
                 'box', c.box, 'area', c.area, 'plan_name', (select name from public.motor_plans where id = c.plan_id)),
    'rows', coalesce((select jsonb_agg(x order by x->>'at', x->>'t') from (
        select jsonb_build_object('t','inv','id',i.id,'no',i.no,'at',i.created_at,'kind',i.kind,'period',i.period,
               'prev_value',i.prev_value,'cur_value',i.cur_value,'kwh',i.kwh,'kwh_price',i.kwh_price,'fee',i.fee,
               'energy',i.energy,'discount',i.discount,'addition',i.addition,
               'debit',greatest(i.amount,0),'credit',greatest(-i.amount,0),'balance_before',i.balance_before,'balance_after',i.balance_after,
               'note',i.note,'staff',i.staff_name,'voided',i.voided,'items',i.items,
               'photo', (select r.photo_url from public.motor_readings r where r.id = i.reading_id)) as x
          from public.motor_invoices i where i.customer_id = c.id
        union all
        select jsonb_build_object('t','pay','id',p.id,'no',p.no,'at',p.created_at,'method',p.method,
               'paid_currency',p.paid_currency,'paid_amount',p.paid_amount,'rate',p.rate,
               'balance_before',p.balance_before,'balance_after',p.balance_after,
               'debit',0,'credit',p.amount,'note',p.note,'staff',p.staff_name,'voided',p.voided)
          from public.motor_payments p where p.customer_id = c.id
      ) q), '[]'::jsonb));
end $$;

-- ============================================================
--  9) أخذ العداد → قراءة + فاتورة بعملية واحدة
-- ============================================================
drop function if exists public.motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision);
create or replace function public.motor_read(p_slug text, p_token text, p_customer uuid, p_value numeric,
  p_photo text, p_lat double precision, p_lng double precision, p_accuracy double precision default null,
  p_remote boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; st public.motor_sites%rowtype; c public.motor_customers%rowtype;
        pl public.motor_plans%rowtype; prev numeric; d integer; rid uuid; seq integer;
        kwh numeric; price numeric; fee numeric; energy numeric; amt numeric; inv public.motor_invoices%rowtype;
        today date := public._motor_today(); baseline boolean := false;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid for update;   -- يرتّب الأرقام المتسلسلة
  select * into c from public.motor_customers where id = p_customer and site_id = sid for update;
  if not found then perform public._motor_err('customer_not_found'); end if;
  if not (w->>'can_read')::boolean then perform public._motor_err('forbidden'); end if;
  if w->>'role' = 'collector' then
    if not st.collector_sees_all and c.collector_id is distinct from (w->>'staff_id')::uuid then
      perform public._motor_err('forbidden');
    end if;
    -- فترة أخذ العداد ثابتة: من 26 لآخر يوم بالشهر، وبشباط من 23
    if extract(day from today) < public._motor_read_start(today) then
      perform public._motor_err('out_of_window', to_char(today, 'YYYY-MM') || '-' || public._motor_read_start(today));
    end if;
  end if;
  if not c.is_active then perform public._motor_err('customer_inactive'); end if;
  if exists (select 1 from public.motor_readings where customer_id = c.id and period = st.bill_period) then
    perform public._motor_err('already_read', st.bill_period);
  end if;
  if p_value is null or p_value < 0 then perform public._motor_err('bad_value'); end if;
  if st.require_photo and coalesce(p_photo,'') = '' and not (w->>'is_admin')::boolean then perform public._motor_err('photo_required'); end if;
  if coalesce(p_photo,'') <> '' and p_photo !~ ('^/img/motor/' || sid::text || '/') then
    perform public._motor_err('bad_photo');
  end if;
  -- قراءة عن بعد: الزبون بعت صورة العداد — لا موقع ولا فحص مسافة
  if coalesce(p_remote, false) then p_lat := null; p_lng := null; p_accuracy := null; end if;
  if st.require_gps and not coalesce(p_remote, false) and not public._motor_geo_ok(p_lat, p_lng) and not (w->>'is_admin')::boolean then perform public._motor_err('gps_required'); end if;

  select value into prev from public.motor_readings where customer_id = c.id order by created_at desc limit 1;
  if not found then
    prev := coalesce(c.initial_reading, 0);
    baseline := st.first_read_baseline and coalesce(c.initial_reading, 0) = 0 and c.next_prev is null;
  end if;
  if c.next_prev is not null then prev := c.next_prev; end if;   -- المدير حدّد العداد السابق
  if baseline then prev := p_value; end if;     -- أول قراءة = عداد أولي، بلا استهلاك
  if p_value < prev then perform public._motor_err('lower_than_prev', prev::text); end if;

  d := null;
  if public._motor_geo_ok(p_lat, p_lng) and public._motor_geo_ok(c.lat, c.lng) then
    d := public._motor_dist(c.lat, c.lng, p_lat, p_lng);   -- تسجيل المسافة فقط، بلا منع
  end if;

  insert into public.motor_readings (site_id, customer_id, period, prev_value, value, photo_url, lat, lng, accuracy,
                                     dist_m, staff_id, staff_name, remote)
  values (sid, c.id, st.bill_period, prev, p_value, coalesce(p_photo,''), p_lat, p_lng, p_accuracy, d,
          (w->>'staff_id')::uuid, w->>'name', coalesce(p_remote, false))
  returning id into rid;

  -- أول قراءة ميدانية لزبون بلا موقع: منثبّت موقعه (الدقة لازم تكون منيحة)
  if not public._motor_geo_ok(c.lat, c.lng) and public._motor_geo_ok(p_lat, p_lng) and coalesce(p_accuracy, 0) <= 60 then
    update public.motor_customers set lat = p_lat, lng = p_lng where id = c.id;
  end if;

  select * into pl from public.motor_plans where id = c.plan_id;
  kwh := p_value - prev;
  fee := coalesce(pl.fee, 0);
  if coalesce(pl.kind,'meter') = 'meter' then
    price := coalesce(pl.kwh_price, st.kwh_price, 0);
    energy := kwh * price;
  else
    price := 0; energy := 0;
  end if;
  amt := public._motor_round(sid, fee + energy - coalesce(c.charge_discount,0) + coalesce(c.charge_addition,0));

  update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
  insert into public.motor_invoices (site_id, no, customer_id, period, kind, reading_id, plan_name, prev_value, cur_value,
         kwh, kwh_price, fee, energy, discount, addition, amount, balance_before, balance_after, staff_id, staff_name)
  values (sid, seq, c.id, st.bill_period, coalesce(pl.kind,'meter'), rid, coalesce(pl.name,''), prev, p_value,
          kwh, price, fee, round(energy,2), coalesce(c.charge_discount,0), coalesce(c.charge_addition,0), amt,
          c.balance, c.balance + amt, (w->>'staff_id')::uuid, w->>'name')
  returning * into inv;
  if baseline then update public.motor_invoices set note = 'قراءة أولى (عداد أولي)' where id = inv.id; inv.note := 'قراءة أولى (عداد أولي)'; end if;
  update public.motor_customers set balance = balance + amt, next_prev = null, updated_at = now() where id = c.id;

  return jsonb_build_object('ok', true, 'invoice', to_jsonb(inv) - 'site_id', 'dist_m', d, 'reading_id', rid, 'baseline', baseline);
end $$;

-- فواتير الاشتراك المقطوع (بلا عداد) لدورة الفوترة الحالية — دفعة وحدة
create or replace function public.motor_bill_fixed(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; st public.motor_sites%rowtype; c record; amt numeric; seq integer; n int := 0;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid for update;
  for c in select cu.*, pl.fee as pfee, pl.name as pname from public.motor_customers cu
             join public.motor_plans pl on pl.id = cu.plan_id
            where cu.site_id = sid and cu.is_active and not cu.archived and cu.deleted_at is null and pl.kind = 'fixed'
              and not exists (select 1 from public.motor_invoices i where i.customer_id = cu.id
                               and i.period = st.bill_period and i.kind in ('meter','fixed') and not i.voided)
            for update of cu
  loop
    amt := public._motor_round(sid, c.pfee - coalesce(c.charge_discount,0) + coalesce(c.charge_addition,0));
    update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
    insert into public.motor_invoices (site_id, no, customer_id, period, kind, plan_name, fee, discount, addition,
           amount, balance_before, balance_after, staff_id, staff_name)
    values (sid, seq, c.id, st.bill_period, 'fixed', c.pname, c.pfee, coalesce(c.charge_discount,0),
            coalesce(c.charge_addition,0), amt, c.balance, c.balance + amt, (w->>'staff_id')::uuid, w->>'name');
    update public.motor_customers set balance = balance + amt, updated_at = now() where id = c.id;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'count', n, 'period', st.bill_period);
end $$;

-- إلغاء فاتورة (والقراءة المربوطة فيها بتنحذف حتى ينعاد أخذ العداد)
create or replace function public.motor_invoice_void(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; i public.motor_invoices%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into i from public.motor_invoices where id = p_id and site_id = sid for update;
  if not found then perform public._motor_err('not_found'); end if;
  if i.voided then return jsonb_build_object('ok', true); end if;
  update public.motor_invoices set voided = true, voided_at = now(), voided_by = w->>'name', reading_id = null,
         voided_reading = (select to_jsonb(r) from public.motor_readings r where r.id = i.reading_id) where id = i.id;
  if i.reading_id is not null then delete from public.motor_readings where id = i.reading_id; end if;
  -- فاتورة مشتريات: البنود من المخزون بترجع عليه
  if i.kind = 'sale' then
    update public.motor_stock st set qty = st.qty + (it->>'qty')::numeric, updated_by = w->>'name', updated_at = now()
      from jsonb_array_elements(i.items) it where it->>'stock_id' is not null and st.id = (it->>'stock_id')::uuid and st.site_id = sid;
    insert into public.motor_stock_moves (site_id, item_id, item_name, kind, qty, unit_price, taker, note, by_name)
    select sid, (it->>'stock_id')::uuid, it->>'name', 'void', (it->>'qty')::numeric, (it->>'price')::numeric, '', 'إلغاء فاتورة مشتريات #' || i.no, w->>'name'
      from jsonb_array_elements(i.items) it where it->>'stock_id' is not null;
  end if;
  update public.motor_customers set balance = balance - i.amount, updated_at = now() where id = i.customer_id;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  values (sid, 'invoice', i.id, 'فاتورة #' || i.no || coalesce(' ' || nullif(i.period,''), '') || ' — ' ||
          (select name from public.motor_customers where id = i.customer_id), jsonb_build_object('amount', i.amount), w->>'name');
  return jsonb_build_object('ok', true);
end $$;

-- قيد يدوي على الزبون (موجب = دين عليه، سالب = له)
create or replace function public.motor_adjust(p_slug text, p_token text, p_customer uuid, p_amount numeric, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; c public.motor_customers%rowtype; seq integer; inv public.motor_invoices%rowtype;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if coalesce(p_amount,0) = 0 then perform public._motor_err('bad_amount'); end if;
  select * into c from public.motor_customers where id = p_customer and site_id = sid for update;
  if not found then perform public._motor_err('customer_not_found'); end if;
  update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
  insert into public.motor_invoices (site_id, no, customer_id, kind, amount, balance_before, balance_after, note, staff_id, staff_name)
  values (sid, seq, c.id, 'adjust', p_amount, c.balance, c.balance + p_amount, coalesce(p_note,''),
          (w->>'staff_id')::uuid, w->>'name')
  returning * into inv;
  update public.motor_customers set balance = balance + p_amount, updated_at = now() where id = c.id;
  return jsonb_build_object('ok', true, 'invoice', to_jsonb(inv) - 'site_id');
end $$;

-- ============================================================
--  10) القبض
-- ============================================================
create or replace function public.motor_pay(p_slug text, p_token text, p_customer uuid, p_paid numeric,
  p_currency text, p_method text, p_note text default '', p_lat double precision default null, p_lng double precision default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; st public.motor_sites%rowtype; c public.motor_customers%rowtype; amt numeric; seq integer;
        pay public.motor_payments%rowtype; cur text := upper(coalesce(p_currency,'')); m text := lower(coalesce(p_method,'cash'));
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  if not (w->>'can_collect')::boolean then perform public._motor_err('forbidden'); end if;
  select * into st from public.motor_sites where id = sid for update;
  select * into c from public.motor_customers where id = p_customer and site_id = sid for update;
  if not found then perform public._motor_err('customer_not_found'); end if;
  if w->>'role' = 'collector' and not st.collector_sees_all and c.collector_id is distinct from (w->>'staff_id')::uuid then
    perform public._motor_err('forbidden');
  end if;
  if cur = '' then cur := st.currency; end if;
  if cur not in ('USD','LBP') then perform public._motor_err('bad_currency'); end if;
  if m not in ('cash','whish') then perform public._motor_err('bad_method'); end if;
  if m = 'whish' and not (w->>'is_admin')::boolean then perform public._motor_err('whish_admin'); end if;
  if coalesce(p_paid,0) <= 0 then perform public._motor_err('bad_amount'); end if;
  if cur = st.currency then amt := p_paid;
  elsif coalesce(st.lbp_rate,0) <= 0 then perform public._motor_err('no_rate');
  elsif cur = 'LBP' then amt := round(p_paid / st.lbp_rate, 2);      -- أساسي دولار، مقبوض ليرة
  else amt := round(p_paid * st.lbp_rate, 0);                         -- أساسي ليرة، مقبوض دولار
  end if;
  update public.motor_sites set receipt_seq = receipt_seq + 1 where id = sid returning receipt_seq into seq;
  insert into public.motor_payments (site_id, no, customer_id, amount, paid_currency, paid_amount, rate, method,
         balance_before, balance_after, note, lat, lng, staff_id, staff_name)
  values (sid, seq, c.id, amt, cur, p_paid, case when cur = st.currency then 0 else st.lbp_rate end, m,
          c.balance, c.balance - amt, coalesce(p_note,''), p_lat, p_lng, (w->>'staff_id')::uuid, w->>'name')
  returning * into pay;
  update public.motor_customers set balance = balance - amt, updated_at = now() where id = c.id;
  return jsonb_build_object('ok', true, 'payment', to_jsonb(pay) - 'site_id',
    'invoice', (select to_jsonb(i) - 'site_id' from public.motor_invoices i
                 where i.customer_id = c.id and not i.voided and i.kind in ('meter','fixed')
                 order by i.created_at desc limit 1));
end $$;

create or replace function public.motor_payment_void(p_slug text, p_token text, p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; p public.motor_payments%rowtype;
begin
  w := public._motor_who(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into p from public.motor_payments where id = p_id and site_id = sid for update;
  if not found then perform public._motor_err('not_found'); end if;
  if p.voided then return jsonb_build_object('ok', true); end if;
  -- الجابي بيلغي إيصالو هوّي بس، قبل ما يسلّم المصاري (قبل إقفال صندوقو أو أي تسليم للمكتب)
  if not (w->>'is_admin')::boolean then
    if not coalesce((w->>'can_collect')::boolean, false) or p.staff_id is distinct from (w->>'staff_id')::uuid then perform public._motor_err('forbidden'); end if;
    if p.created_at <= coalesce((select max(created_at) from public.motor_moves where staff_id = p.staff_id and account = 'collector'), '-infinity'::timestamptz) then
      perform public._motor_err('handed_over');
    end if;
  end if;
  if p.method = 'cash' and p.created_at <= coalesce((select max(created_at) from public.motor_moves
        where site_id = sid and account = 'cash' and kind = 'close'), '-infinity'::timestamptz) then
    perform public._motor_err('closed_period');
  end if;
  if exists (select 1 from public.motor_day_closes where site_id = sid and day = (p.created_at at time zone 'Asia/Beirut')::date) then
    perform public._motor_err('day_closed');
  end if;
  update public.motor_payments set voided = true, voided_at = now(), voided_by = w->>'name' where id = p.id;
  update public.motor_customers set balance = balance + p.amount, updated_at = now() where id = p.customer_id;
  insert into public.motor_trash (site_id, kind, ref_id, label, data, deleted_by)
  values (sid, 'payment', p.id, 'إيصال #' || p.no || ' — ' || (select name from public.motor_customers where id = p.customer_id),
          jsonb_build_object('amount', p.amount), w->>'name');
  return jsonb_build_object('ok', true);
end $$;

