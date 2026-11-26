-- رسوم إعادة وصل الخط (خدمة — ما بتنزل بالمخزون) + البيع بلا مخزون كافي (الكمية بتصير بالسالب)
-- + بنود حرّة (مش من المخزون) مسموحة للمدير كمان
alter table public.motor_sites add column if not exists reconnect_fee numeric not null default 0;

-- قفل الأسعار: بس على أصناف المخزون. البند الحر (خدمة / شي مش بالمخزون) بيمرق متل ما هو
create or replace function public._motor_sale_lock(p_sid uuid, p_items jsonb, p_sale uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare x jsonb; s public.motor_stock%rowtype; pr numeric; out jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_items) <> 'array' then return p_items; end if;
  for x in select * from jsonb_array_elements(p_items) loop
    if coalesce(x->>'stock_id','') = '' then out := out || jsonb_build_array(x); continue; end if;
    select * into s from public.motor_stock where id = (x->>'stock_id')::uuid and site_id = p_sid;
    if not found then perform public._motor_err('bad_data'); end if;
    pr := null;
    if p_sale is not null then
      select (it->>'price')::numeric into pr from public.motor_invoices i, jsonb_array_elements(i.items) it
       where i.id = p_sale and i.site_id = p_sid and it->>'stock_id' = s.id::text limit 1;
    end if;
    out := out || jsonb_build_array(x || jsonb_build_object('name', s.name, 'price', coalesce(pr, s.unit_price, 0)));
  end loop;
  return out;
end $$;
revoke all on function public._motor_sale_lock(uuid,jsonb,uuid) from public, anon, authenticated;

do $$
declare d text;
begin
  -- البيع حتى لو خلص المخزون: الكمية بتنزل تحت الصفر
  select pg_get_functiondef('public.motor_sale_add(text,text,uuid,jsonb,text)'::regprocedure) into d;
  if position('stock_low' in d) > 0 then
    d := replace(d, E'      if s.qty < q then perform public._motor_err(''stock_low'', s.name || '': '' || s.qty::text); end if;\n', '');
    if position('stock_low' in d) > 0 then raise exception 'stock_low patch'; end if;
    execute d;
  end if;

  -- إعادة الوصل: فاتورة «إعادة وصل خط» بقيمة الرسوم، إلا إذا المدير اختار «بدون رسوم»
  select pg_get_functiondef('public.motor_set_active(text,text,uuid,boolean,text,double precision,double precision)'::regprocedure) into d;
  d := replace(d, 'p_lng double precision DEFAULT NULL::double precision)', 'p_lng double precision DEFAULT NULL::double precision, p_fee numeric DEFAULT NULL::numeric, p_no_fee boolean DEFAULT false)');
  d := replace(d, 'declare w jsonb; sid uuid; c public.motor_customers%rowtype;', 'declare w jsonb; sid uuid; c public.motor_customers%rowtype; adm boolean; fee numeric; seq integer; inv public.motor_invoices%rowtype;');
  d := replace(d, E'  return jsonb_build_object(''ok'', true, ''is_active'', p_active);',
E'  adm := coalesce((w->>''is_admin'')::boolean, false);
  if not adm then p_fee := null; p_no_fee := false; end if;
  if adm and p_fee is not null then
    if p_fee < 0 or p_fee > 100000 then perform public._motor_err(''bad_amount''); end if;
    update public.motor_sites set reconnect_fee = p_fee where id = sid;   -- آخر قيمة بتصير الافتراضية
  end if;
  if p_active then
    fee := coalesce(p_fee, (select reconnect_fee from public.motor_sites where id = sid), 0);
    if fee > 0 and not coalesce(p_no_fee, false) then
      update public.motor_sites set invoice_seq = invoice_seq + 1 where id = sid returning invoice_seq into seq;
      insert into public.motor_invoices (site_id, no, customer_id, period, kind, amount, items, balance_before, balance_after, note, staff_id, staff_name, wa_sent_at)
      values (sid, seq, c.id, to_char(public._motor_today(), ''YYYY-MM''), ''sale'', fee,
              jsonb_build_array(jsonb_build_object(''name'', ''إعادة وصل خط'', ''qty'', 1, ''price'', fee, ''total'', fee, ''stock_id'', null)),
              c.balance, c.balance + fee, ''إعادة وصل خط'' || coalesce('' — '' || nullif(trim(p_note),''''), ''''), (w->>''staff_id'')::uuid, w->>''name'', now())
      returning * into inv;
      update public.motor_customers set balance = balance + fee, updated_at = now() where id = c.id;
    end if;
  end if;
  return jsonb_build_object(''ok'', true, ''is_active'', p_active, ''invoice'', case when inv.id is null then null else to_jsonb(inv) - ''site_id'' end);');
  if position('p_no_fee' in d) = 0 or position('إعادة وصل خط' in d) = 0 or position('adm boolean' in d) = 0 then raise exception 'set_active patch'; end if;
  drop function public.motor_set_active(text,text,uuid,boolean,text,double precision,double precision);
  execute d;
  revoke all on function public.motor_set_active(text,text,uuid,boolean,text,double precision,double precision,numeric,boolean) from public;
  grant execute on function public.motor_set_active(text,text,uuid,boolean,text,double precision,double precision,numeric,boolean) to anon, authenticated, service_role;
end $$;
