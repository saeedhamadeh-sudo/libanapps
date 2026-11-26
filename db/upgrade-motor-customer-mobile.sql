-- تعديل رقم جوال الزبون بسرعة من صفحات الإرسال (المدير والمدير الأساسي)
create or replace function public.motor_customer_mobile(p_slug text, p_token text, p_customer uuid, p_cc text, p_mobile text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; cc text; mb text; c public.motor_customers%rowtype;
begin
  w := public._motor_admin(p_slug, p_token); sid := (w->>'site_id')::uuid;
  cc := regexp_replace(coalesce(p_cc,''), '\D', '', 'g'); if cc = '' then cc := '961'; end if;
  mb := regexp_replace(coalesce(p_mobile,''), '\D', '', 'g');
  if mb like '00' || cc || '%' then mb := substr(mb, length(cc) + 3); elsif mb like cc || '%' and length(mb) > length(cc) + 6 then mb := substr(mb, length(cc) + 1); end if;
  mb := regexp_replace(mb, '^0+', '');
  if mb <> '' and (length(mb) < 6 or length(mb) > 12) then perform public._motor_err('bad_mobile'); end if;
  update public.motor_customers set mobile_cc = cc, mobile = mb, updated_at = now() where id = p_customer and site_id = sid returning * into c;
  if not found then perform public._motor_err('customer_not_found'); end if;
  return jsonb_build_object('ok', true, 'mobile', c.mobile, 'mobile_cc', c.mobile_cc, 'name', c.name, 'code', c.code);
end $$;
revoke all on function public.motor_customer_mobile(text,text,uuid,text,text) from public;
grant execute on function public.motor_customer_mobile(text,text,uuid,text,text) to anon, authenticated;
