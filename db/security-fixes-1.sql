-- ============================================================
--  إصلاحات أمان — المجموعة الأولى (27/09/2026)
--  شغّله على مشروع LibanApps (moriwmhlgugmjzddwfgv) — آمن للتكرار.
-- ============================================================

-- ------------------------------------------------------------
-- 1) (حرج) تفعيل الاشتراك مجاناً: provision_purchase كانت تُستدعى
--    بالمفتاح العام دون تسجيل دخول. من الآن: مفتاح الخدمة (الـ Worker) فقط.
--    نفس الشيء لـ provision_addon وexpire_stale_purchases إن وُجدتا.
-- ------------------------------------------------------------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname in ('provision_purchase','provision_addon','expire_stale_purchases')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- ------------------------------------------------------------
-- 2) حساب رابط البرنامج (/portal) لا يصل إلى المتجر الإلكتروني وبوابات الدفع
-- ------------------------------------------------------------
create or replace function public.is_portal_user()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.portal_users where user_id = auth.uid());
$$;

create or replace function public.store_owned(sid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or (not public.is_portal_user() and exists (
    select 1 from public.stores s
    where s.id = sid and s.client_id = public.my_client_id()));
$$;

drop policy if exists own_stores on public.stores;
create policy own_stores on public.stores for all to authenticated
  using (public.store_owned(id))
  with check (public.is_admin() or (not public.is_portal_user() and public.owns(client_id)));

-- ------------------------------------------------------------
-- 3) ملفات الصور: لا أحد يستبدل أو يحذف ملفات غيره،
--    وسجل الفواتير لم يعد قابلاً للاستعراض (الروابط المباشرة تبقى تعمل)
-- ------------------------------------------------------------
do $$ begin
  execute 'drop policy if exists "libanapps read media" on storage.objects';
  execute 'create policy "libanapps read media" on storage.objects for select to anon, authenticated
           using (bucket_id in (''logos'',''items'',''banners''))';
  execute 'drop policy if exists "libanapps update media" on storage.objects';
  execute 'create policy "libanapps update media" on storage.objects for update to authenticated
           using (bucket_id in (''logos'',''items'',''banners'') and (owner = auth.uid() or public.is_admin()))
           with check (bucket_id in (''logos'',''items'',''banners'') and (owner = auth.uid() or public.is_admin()))';
  execute 'drop policy if exists "libanapps delete media" on storage.objects';
  execute 'create policy "libanapps delete media" on storage.objects for delete to authenticated
           using (bucket_id in (''logos'',''items'',''banners'') and (owner = auth.uid() or public.is_admin()))';
exception when others then
  raise notice 'storage policies skipped: %', sqlerrm;
end $$;

-- ------------------------------------------------------------
-- 4) صاحب المطعم لا يغيّر رابط مطعمه (slug) ولا المؤسسة المرتبط بها —
--    هذا لمشرف المنصة (لوحة /super) أو السيرفر فقط
-- ------------------------------------------------------------
create or replace function public.lock_restaurant_identity()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.slug is distinct from old.slug or new.client_id is distinct from old.client_id)
     and coalesce(auth.role(), '') <> 'service_role'
     and not public.is_admin() then
    raise exception 'لا يمكن تغيير رابط المطعم أو المؤسسة المرتبط بها إلا من إدارة المنصة';
  end if;
  return new;
end $$;

drop trigger if exists trg_lock_restaurant_identity on public.restaurants;
create trigger trg_lock_restaurant_identity
  before update on public.restaurants
  for each row execute function public.lock_restaurant_identity();

-- تحقّق: يجب أن تكون النتيجة false لكل الصفوف
select p.oid::regprocedure as fn, has_function_privilege('anon', p.oid, 'execute') as anon_can_call
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('provision_purchase','provision_addon','expire_stale_purchases');
