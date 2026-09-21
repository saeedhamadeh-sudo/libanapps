-- ============================================================
--  إصلاح: مزامنة المستخدمين ببرنامج الصناعيين
--  المطابقة صارت على المفتاح الأساسي (client_id, id)
--  والاسم بيضل فريد داخل كل مؤسسة
-- ============================================================

-- فهارس الأسماء: فريدة داخل الزبون (بدون lower ليطابق ما يطلبه البرنامج)
drop index if exists public.alum_app_users_uq;
create unique index if not exists alum_app_users_uq
  on public.alum_app_users (client_id, username);

drop index if exists public.alum_customer_accounts_uq;
create unique index if not exists alum_customer_accounts_uq
  on public.alum_customer_accounts (client_id, username);

drop index if exists public.alum_worker_accounts_uq;
create unique index if not exists alum_worker_accounts_uq
  on public.alum_worker_accounts (client_id, username);

-- تحقّق: المفتاح الأساسي والفهارس
select conname, pg_get_constraintdef(oid) as def
from pg_constraint
where conrelid = 'public.alum_app_users'::regclass and contype = 'p'
union all
select indexname, indexdef from pg_indexes
where schemaname='public' and indexname like 'alum_%_uq';
