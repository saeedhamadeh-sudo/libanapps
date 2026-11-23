-- إلغاء تسعيرة شهر: الفواتير المعمولة بتضل على سعرها، والعدادات الجديدة لهالشهر بتحتاج تسعيرة من جديد
create or replace function public.motor_month_price_delete(p_slug text, p_token text, p_period text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid;
begin
  w := public._motor_admin(p_slug, p_token);
  sid := (w->>'site_id')::uuid;
  delete from public.motor_month_prices where site_id = sid and period = p_period;
  if not found then perform public._motor_err('not_found'); end if;
  return jsonb_build_object('ok', true);
end $$;
grant execute on function public.motor_month_price_delete(text, text, text) to anon, authenticated;
