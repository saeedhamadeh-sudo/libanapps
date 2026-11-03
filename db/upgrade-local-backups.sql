-- ============================================================
--  نسخ احتياطية للنسخة المحلية (LibanApps Local)
--  البرنامج المثبّت على كمبيوتر الزبون بيرفع نسخة مشفّرة (AES-256) من بياناته
--  لهالـbucket، بمجلد باسم هوية المؤسسة. كلمة سر التشفير عند الزبون بس —
--  حتى من لوحة Supabase ما فيك تقرا محتوى النسخة.
--  شغّله مرة وحدة — آمن للتكرار.
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit)
values ('local-backups', 'local-backups', false, 524288000)   -- 500MB للنسخة الوحدة
on conflict (id) do update set public = false;

-- كل مؤسسة بتشوف وبترفع وبتمحي بمجلدها بس:  local-backups/<client_id>/...
drop policy if exists local_backups_select on storage.objects;
create policy local_backups_select on storage.objects for select to authenticated
  using (bucket_id = 'local-backups' and (storage.foldername(name))[1] = public.my_client_id()::text);

drop policy if exists local_backups_insert on storage.objects;
create policy local_backups_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'local-backups' and (storage.foldername(name))[1] = public.my_client_id()::text);

drop policy if exists local_backups_update on storage.objects;
create policy local_backups_update on storage.objects for update to authenticated
  using (bucket_id = 'local-backups' and (storage.foldername(name))[1] = public.my_client_id()::text)
  with check (bucket_id = 'local-backups' and (storage.foldername(name))[1] = public.my_client_id()::text);

drop policy if exists local_backups_delete on storage.objects;
create policy local_backups_delete on storage.objects for delete to authenticated
  using (bucket_id = 'local-backups' and (storage.foldername(name))[1] = public.my_client_id()::text);
