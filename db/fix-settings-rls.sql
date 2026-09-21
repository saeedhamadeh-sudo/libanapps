-- ============================================================
--  إصلاح: حفظ إعدادات الموقع
--  الجدول كان بلا سياسة قراءة، فالتحديث كان بينرفض بصمت
--  (لأن Supabase بيرجّع الصف بعد التحديث)
--  الأسرار (Whish) بتضل محمية — القراءة للمشرف فقط
-- ============================================================

drop policy if exists adm_settings_read on public.platform_settings;
create policy adm_settings_read on public.platform_settings
  for select to authenticated
  using (public.is_admin());

drop policy if exists adm_settings on public.platform_settings;
create policy adm_settings on public.platform_settings
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- تحقّق: لازم يطلع سطرين
select policyname, cmd from pg_policies
where schemaname='public' and tablename='platform_settings';
