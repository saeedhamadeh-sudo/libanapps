-- ============================================================
--  حساب رابط البرنامج (portal_users) لا يمكن أن يصبح صاحب مؤسسة
--  (يمنع إنشاء مؤسسة أو ربطها به من صفحة الحساب أو أي دالة أخرى)
--  شغّله بعد upgrade-portal-users.sql — آمن للتكرار.
-- ============================================================
create or replace function public.block_portal_owner()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.user_id is not null and exists (select 1 from public.portal_users where user_id = new.user_id) then
    raise exception 'هذا حساب رابط البرنامج ولا يمكن استخدامه كحساب على المنصة';
  end if;
  return new;
end $$;

drop trigger if exists trg_block_portal_owner on public.clients;
create trigger trg_block_portal_owner
  before insert or update of user_id on public.clients
  for each row execute function public.block_portal_owner();

-- تحقّق: يجب ألا يظهر أي صف
select c.id, c.name from public.clients c
join public.portal_users p on p.user_id = c.user_id;
