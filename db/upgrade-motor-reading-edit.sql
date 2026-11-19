-- تعديل العداد (المدير + المدير الأساسي): آخر قراءة للزبون بأي دورة، مع إمكانية تصحيح العداد السابق
drop function if exists public.motor_reading_edit(text, text, uuid, numeric, text);
create or replace function public.motor_reading_edit(p_slug text, p_token text, p_reading uuid, p_value numeric, p_note text default '', p_prev numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; r public.motor_readings%rowtype; i public.motor_invoices%rowtype; st public.motor_sites%rowtype;
        v_kwh numeric; v_energy numeric; amt numeric; delta numeric; nd numeric; old_v numeric; old_p numeric;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  select * into st from public.motor_sites where id = sid;
  select * into r from public.motor_readings where id = p_reading and site_id = sid for update;
  if not found then perform public._motor_err('not_found'); end if;
  if exists (select 1 from public.motor_readings x where x.customer_id = r.customer_id and x.created_at > r.created_at) then
    perform public._motor_err('not_latest');
  end if;
  old_v := r.value; old_p := r.prev_value;
  -- تصحيح العداد السابق (إذا انكتب غلط)
  if p_prev is not null and p_prev <> r.prev_value then
    if p_prev < 0 then perform public._motor_err('bad_value'); end if;
    update public.motor_readings set prev_value = p_prev where id = r.id;
    update public.motor_invoices set prev_value = p_prev where reading_id = r.id and not voided;
    r.prev_value := p_prev;
  -- first_base: أول قراءة اعتُمدت عداداً أولياً (السابق = الحالي) → السابق بيصير القيمة الجديدة
  elsif p_value is not null and st.first_read_baseline and r.prev_value = r.value
     and not exists (select 1 from public.motor_readings x where x.customer_id = r.customer_id and x.created_at < r.created_at)
     and coalesce((select initial_reading from public.motor_customers where id = r.customer_id), 0) = 0 then
    update public.motor_readings set prev_value = p_value where id = r.id;
    update public.motor_invoices set prev_value = p_value where reading_id = r.id and not voided;
    r.prev_value := p_value;
  end if;
  if p_value is null or p_value < r.prev_value then perform public._motor_err('lower_than_prev', r.prev_value::text); end if;
  update public.motor_readings set value = p_value where id = r.id;
  select * into i from public.motor_invoices where reading_id = r.id and not voided for update;
  if found then
    v_kwh := p_value - r.prev_value;
    v_energy := case when i.kind = 'meter' then round(v_kwh * i.kwh_price, 2) else 0 end;
    nd := i.discount - round((i.fee + i.energy) * i.disc_pct / 100, 2) + round((i.fee + v_energy) * i.disc_pct / 100, 2);
    amt := public._motor_round(sid, i.fee + v_energy - nd + i.addition);
    delta := amt - i.amount;
    update public.motor_invoices set prev_value = r.prev_value, cur_value = p_value, kwh = v_kwh, energy = v_energy, discount = nd, amount = amt,
           balance_after = balance_after + delta,
           note = trim(both ' ' from note || case when coalesce(p_note,'') <> '' then ' ' || p_note else '' end
                  || ' (عُدّل العداد بواسطة ' || (w->>'name') || ': ' || old_p::text || '→' || old_v::text || ' صار ' || r.prev_value::text || '→' || p_value::text || ')')
     where id = i.id;
    update public.motor_customers set balance = balance + delta, updated_at = now() where id = r.customer_id;
  else
    update public.motor_customers set updated_at = now() where id = r.customer_id;
  end if;
  return jsonb_build_object('ok', true, 'delta', coalesce(delta, 0));
end $$;
grant execute on function public.motor_reading_edit(text, text, uuid, numeric, text, numeric) to anon, authenticated;

