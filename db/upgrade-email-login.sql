-- ============================================================
--  LibanApps — دخول بالبريد الإلكتروني:
--   • مدير المنصة بيحط بريد دخول لأي زبون من /super (حتى لو سجّل بواتساب أو ما إلو حساب)
--   • الزبون اللي سجّل بواتساب بيضيف بريد + كلمة مرور من صفحة حسابه
--  التعديل الفعلي على الحسابات بيصير بالـWorker بمفتاح الخدمة؛ هون بس دالة بحث.
--  آمن للتشغيل أكثر من مرة.
-- ============================================================
create or replace function public.auth_user_by_email(p_email text)
returns uuid language sql stable security definer set search_path = public, auth as $$
  select id from auth.users where lower(email) = lower(trim(coalesce(p_email,''))) limit 1;
$$;
revoke all on function public.auth_user_by_email(text) from public, anon, authenticated;
grant execute on function public.auth_user_by_email(text) to service_role;
