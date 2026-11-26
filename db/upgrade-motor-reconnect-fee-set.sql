-- تحديد رسوم إعادة وصل الخط من صفحة «فتح/قطع اشتراك» (المدير والمدير الأساسي)
create or replace function public.motor_reconnect_fee_set(p_slug text, p_token text, p_fee numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb;
begin
  w := public._motor_admin(p_slug, p_token);
  if p_fee is null or p_fee < 0 or p_fee > 100000 then perform public._motor_err('bad_amount'); end if;
  update public.motor_sites set reconnect_fee = round(p_fee, 2) where id = (w->>'site_id')::uuid;
  return jsonb_build_object('ok', true, 'fee', round(p_fee, 2));
end $$;
revoke all on function public.motor_reconnect_fee_set(text,text,numeric) from public;
grant execute on function public.motor_reconnect_fee_set(text,text,numeric) to anon, authenticated;
