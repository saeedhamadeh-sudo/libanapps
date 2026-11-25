-- ============================================================
--  motorapp: العداد بينحفظ بلا فاتورة. الفاتورة بتصدر بس لما يكون سعر الشهر محدّد
--  ونكون وصلنا لـ1 من الشهر يلي بعدو (مثلاً عدادات تشرين الثاني بتتفوتر من 1 كانون الأول).
--  «أخذ عداد وإنهاء الحساب»: بسعر بيحطّو المدير، فاتورة فورية وإشعار فوري.
-- ============================================================
alter table public.motor_readings add column if not exists inv_pending boolean not null default false;
create index if not exists motor_readings_pending on public.motor_readings (site_id) where inv_pending;

-- أول يوم مسموح فيه فوترة/إشعار دورة p_per
create or replace function public._motor_bill_from(p_per text)
returns date language sql immutable as $$
  select (to_date(left(p_per,7) || '-01', 'YYYY-MM-DD') + interval '1 month')::date;
$$;

-- إصدار فاتورة لعداد محفوظ بلا فاتورة
create or replace function public._motor_issue_reading(p_rid uuid, p_price numeric, p_staff uuid default null, p_staff_name text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.motor_readings%rowtype; st public.motor_sites%rowtype; c public.motor_customers%rowtype; pl public.motor_plans%rowtype;
        kwh numeric; price numeric; fee numeric; energy numeric; amt numeric; seq integer; inv public.motor_invoices%rowtype; i_per text; disc numeric;
begin
  select * into r from public.motor_readings where id = p_rid for update;
  if not found then return null; end if;
  if exists (select 1 from public.motor_invoices where reading_id = r.id and not voided) then
    update public.motor_readings set inv_pending = false where id = r.id; return null;
  end if;
  select * into st from public.motor_sites where id = r.site_id;
  select * into c from public.motor_customers where id = r.customer_id for update;
  select * into pl from public.motor_plans where id = c.plan_id;
  i_per := left(r.period, 7);
  kwh := r.value - r.prev_value;
  fee := coalesce(pl.fee, 0);
  if coalesce(pl.kind,'meter') = 'meter' then
    price := coalesce(p_price, public._motor_month_price(r.site_id, i_per), 0);
    energy := greatest(kwh - coalesce(c.kwh_free, 0), 0) * price;
  else price := 0; energy := 0; end if;
  disc := coalesce(c.charge_discount,0) + round((fee + energy) * coalesce(c.charge_discount_pct,0) / 100, 2);
  amt := public._motor_round(r.site_id, fee + energy - disc + coalesce(c.charge_addition,0));
  update public.motor_sites set invoice_seq = invoice_seq + 1 where id = r.site_id returning invoice_seq into seq;
  insert into public.motor_invoices (site_id, no, customer_id, period, kind, reading_id, plan_name, prev_value, cur_value,
         kwh, kwh_price, fee, energy, discount, addition, amount, balance_before, balance_after, staff_id, staff_name)
  values (r.site_id, seq, c.id, i_per, coalesce(pl.kind,'meter'), r.id, coalesce(pl.name,''), r.prev_value, r.value,
          kwh, price, fee, round(energy,2), disc, coalesce(c.charge_addition,0), amt,
          c.balance, c.balance + amt, coalesce(p_staff, r.staff_id), coalesce(p_staff_name, r.staff_name))
  returning * into inv;
  update public.motor_invoices set free_kwh = case when coalesce(pl.kind,'meter') = 'meter' and coalesce(c.kwh_free,0) > 0 then c.kwh_free else free_kwh end,
         disc_pct = coalesce(c.charge_discount_pct, 0),
         price_fixed = coalesce(pl.kind,'meter') = 'meter' and p_price is not null,
         price_auto  = coalesce(pl.kind,'meter') = 'meter' and p_price is null,
         note = case when r.period ~ '^\d{4}-\d{2}-\d{2}$' then 'قراءة خارج الدورة (تصفية حساب)' else note end
   where id = inv.id returning * into inv;
  update public.motor_customers set balance = balance + amt, updated_at = now() where id = c.id;
  update public.motor_readings set inv_pending = false where id = r.id;
  return to_jsonb(inv) - 'site_id';
end $$;
revoke all on function public._motor_issue_reading(uuid,numeric,uuid,text) from public, anon, authenticated;

-- كل العدادات المعلّقة يلي صار وقت فوترتها (سعر محدّد + وصلنا لـ1 من الشهر بعدها)
create or replace function public._motor_issue_due(p_site uuid default null)
returns integer language plpgsql security definer set search_path = public as $$
declare x record; n integer := 0;
begin
  for x in select r.id from public.motor_readings r
            where r.inv_pending and (p_site is null or r.site_id = p_site)
              and public._motor_month_price(r.site_id, left(r.period,7)) is not null
              and public._motor_today() >= public._motor_bill_from(r.period)
            order by r.created_at loop
    perform public._motor_issue_reading(x.id, null);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public._motor_issue_due(uuid) from public, anon, authenticated;
create or replace function public.motor_issue_due_cron()
returns integer language sql security definer set search_path = public as $$ select public._motor_issue_due(null); $$;
revoke all on function public.motor_issue_due_cron() from public, anon, authenticated;
grant execute on function public.motor_issue_due_cron() to service_role;

-- عدد العدادات المعلّقة (لصفحة سعر الشهر)
create or replace function public.motor_pending_readings(p_slug text, p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_who(p_slug, p_token); sid := (w->>'site_id')::uuid;
  return coalesce((select jsonb_object_agg(per, n) from (
     select left(r.period,7) per, count(*) n from public.motor_readings r
      where r.site_id = sid and r.inv_pending
      group by 1) q), '{}'::jsonb);
end $$;
revoke all on function public.motor_pending_readings(text,text) from public, anon;
grant execute on function public.motor_pending_readings(text,text) to anon, authenticated;

-- motor_read: p_close = أخذ عداد وإنهاء الحساب (المدير، بسعر)، غير هيك العداد بيتعلّق لحتى يصير وقت الفوترة
do $$
declare d text; g text;
begin
  select pg_get_functiondef('public.motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision,boolean,numeric,boolean)'::regprocedure) into d;
  d := replace(d, 'p_next boolean DEFAULT false)', 'p_next boolean DEFAULT false, p_close boolean DEFAULT false)');
  d := replace(d, 'mp numeric; expl boolean;', 'mp numeric; expl boolean; defer boolean := false;');
  d := replace(d, '  if not adm then p_price := null; end if;',
    '  if not adm then p_price := null; p_close := false; end if;' || chr(10) ||
    '  if coalesce(p_close,false) and p_price is null and coalesce((select pl0.kind from public.motor_plans pl0 join public.motor_customers c0 on c0.plan_id = pl0.id where c0.id = p_customer),''meter'') = ''meter'' then perform public._motor_err(''price_required''); end if;');
  d := replace(d, E'\n  kwh := p_value - prev;',
    E'\n  defer := not coalesce(p_close,false) and (public._motor_month_price(sid, i_per) is null or today < public._motor_bill_from(i_per));' ||
    E'\n  if defer then' ||
    E'\n    update public.motor_readings set inv_pending = true where id = rid;' ||
    E'\n    update public.motor_customers set next_prev = null, updated_at = now() where id = c.id;' ||
    E'\n    return jsonb_build_object(''ok'', true, ''invoice'', null, ''pending'', true, ''bill_from'', public._motor_bill_from(i_per), ''period'', i_per, ''dist_m'', d, ''reading_id'', rid, ''baseline'', baseline, ''interim'', interim);' ||
    E'\n  end if;' ||
    E'\n  kwh := p_value - prev;');
  d := replace(d, E'  update public.motor_customers set balance = balance + amt, next_prev = null',
    E'  if coalesce(p_close,false) then update public.motor_invoices set note = ''إنهاء حساب'' where id = inv.id; inv.note := ''إنهاء حساب''; end if;\n  update public.motor_customers set balance = balance + amt, next_prev = null');
  if position('p_close' in d) = 0 or position('defer :=' in d) = 0 or position('إنهاء حساب' in d) = 0 then raise exception 'patch failed'; end if;
  drop function public.motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision,boolean,numeric,boolean);
  execute d;
  revoke all on function public.motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision,boolean,numeric,boolean,boolean) from public;
  grant execute on function public.motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision,boolean,numeric,boolean,boolean) to anon, authenticated, service_role;
end $$;

-- تحديد سعر الشهر: إذا وصلنا لوقت الفوترة بتصدر فواتير العدادات المعلّقة فوراً
do $$
declare d text;
begin
  select pg_get_functiondef('public.motor_month_price_set(text,text,text,numeric)'::regprocedure) into d;
  if position('_motor_issue_due' in d) = 0 then
    d := replace(d, E'  return jsonb_build_object(''ok'', true, ''period'', p_period, ''price'', p_price, ''recalc'', n, ''delta'', tot);',
      E'  return jsonb_build_object(''ok'', true, ''period'', p_period, ''price'', p_price, ''recalc'', n, ''delta'', tot, ''issued'', public._motor_issue_due(sid), ''bill_from'', public._motor_bill_from(p_period));');
    if position('_motor_issue_due' in d) = 0 then raise exception 'patch2 failed'; end if;
    execute d;
  end if;
end $$;

-- إشعارات قيمة الفاتورة: مش قبل 1 من الشهر يلي بعد الدورة (إلا فواتير إنهاء الحساب / بسعر محدّد)
do $$
declare d text;
begin
  select pg_get_functiondef('public.motor_inv_wa_claim(integer)'::regprocedure) into d;
  if position('_motor_bill_from' in d) = 0 then
    d := replace(d, 'and (i.price_fixed or exists (select 1 from public.motor_month_prices m where m.site_id = st.id and m.period = i.period))',
      'and (i.price_fixed or (exists (select 1 from public.motor_month_prices m where m.site_id = st.id and m.period = i.period) and public._motor_today() >= public._motor_bill_from(i.period)))');
    if position('_motor_bill_from' in d) = 0 then raise exception 'patch3 failed'; end if;
    execute d;
  end if;
end $$;
