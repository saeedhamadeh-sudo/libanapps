-- ============================================================
--  إصلاحات أمان — المجموعة الثانية (27/09/2026)
--  شغّله على مشروع LibanApps بعد secure-apps.sql — آمن للتكرار.
-- ============================================================

-- ------------------------------------------------------------
-- 1) مشرف المنصة المفعّل عليه التحقق بخطوتين لا يُعتبر مشرفاً
--    إلا إذا دخل بالرمز (aal2). كلمة السر وحدها لا تكفي بعد الآن.
-- ------------------------------------------------------------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.platform_admins where user_id = auth.uid())
     and (coalesce(auth.jwt()->>'aal', 'aal1') = 'aal2'
          or not exists (select 1 from auth.mfa_factors f
                          where f.user_id = auth.uid() and f.status = 'verified'));
$$;

-- ------------------------------------------------------------
-- 2) حسابات الرابط الجديدة ببريد عشوائي (لا يمكن تسجيله مسبقاً)
-- ------------------------------------------------------------
alter table public.portal_users add column if not exists email text;

-- ------------------------------------------------------------
-- 3) حساب SUPERADMIN بكلمة السر الثابتة itech@2027 (كانت مكتوبة في كود
--    برنامج التجارة على GitHub) — نغيّرها إلى كلمة سر عشوائية لا يعرفها أحد.
--    الدخول الإداري على أي مؤسسة صار من لوحة /super.
-- ------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['trade_app_users','alum_app_users'] loop
    if to_regclass('public.' || t) is not null then
      execute format($q$
        update public.%1$I u set password = encode(extensions.gen_random_bytes(18), 'hex')
         where upper(u.username) = 'SUPERADMIN'
           and (u.password = 'itech@2027'
                or exists (select 1 from public.app_account_secrets s
                            where s.tbl = %1$L and s.client_id = u.client_id and s.id = u.id
                              and s.password_hash = extensions.crypt('itech@2027', s.password_hash)))
      $q$, t);
    end if;
  end loop;
end $$;

-- تحقّق: يجب ألا يبقى أي حساب بكلمة السر الافتراضية
select 'trade' as app, count(*) as default_superadmin_left
from public.trade_app_users u
left join public.app_account_secrets s on s.tbl = 'trade_app_users' and s.client_id = u.client_id and s.id = u.id
where upper(u.username) = 'SUPERADMIN'
  and (u.password = 'itech@2027' or s.password_hash = extensions.crypt('itech@2027', s.password_hash));
