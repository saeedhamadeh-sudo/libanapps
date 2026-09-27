-- ============================================================
--  حساب خاص لرابط البرنامج (/portal/<slug>) لكل مؤسسة
--
--  قبل هذا التعديل كان الرابط يُدخل أي زائر بحساب صاحب المؤسسة نفسه
--  على المنصة (صفحة الحساب، الاشتراكات، الشراء والإلغاء).
--  الآن يُدخل الرابط بحساب خاص بالمؤسسة، يصل إلى بيانات البرنامج فقط.
--
--  شغّله مرة واحدة على مشروع LibanApps (moriwmhlgugmjzddwfgv) — آمن للتكرار.
-- ============================================================

-- 1) جدول ربط حساب الرابط بالمؤسسة (يكتب فيه الـ Worker فقط بمفتاح الخدمة)
create table if not exists public.portal_users (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  client_id  uuid not null unique references public.clients(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.portal_users enable row level security;
-- بلا سياسات: لا يقرأه ولا يكتب فيه إلا مفتاح الخدمة والدوال المعرّفة بـ security definer

-- 2) مؤسسة المستخدم الحالي: حساب رابطها أولاً، وإلا صاحب المؤسسة
--    (تستخدمها سياسات بيانات البرامج عبر owns() و app_access)
create or replace function public.my_client_id()
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(
    (select p.client_id from public.portal_users p where p.user_id = auth.uid() limit 1),
    (select c.id from public.clients c where c.user_id = auth.uid() limit 1)
  );
$$;

-- 3) حساب الرابط لا يُربط تلقائياً بأي مؤسسة كصاحب لها
create or replace function public.autolink_my_client()
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid; myemail text;
begin
  if auth.uid() is null then return null; end if;
  if exists (select 1 from public.portal_users where user_id = auth.uid()) then return null; end if;
  select id into cid from public.clients where user_id = auth.uid();
  if cid is not null then return cid; end if;

  select lower(email) into myemail from auth.users where id = auth.uid();

  -- الزبون الذي يملك مطعماً هذا المستخدم عضو فيه
  select c.id into cid
    from public.clients c
    join public.restaurants r on r.client_id = c.id
    join public.restaurant_users ru on ru.restaurant_id = r.id
   where ru.user_id = auth.uid() and c.user_id is null
   limit 1;

  if cid is not null then
    update public.clients set user_id = auth.uid() where id = cid;
  end if;
  return cid;
end $$;

-- 4) تحقّق: يجب أن تظهر كل جداول البرنامجين (alum_ و trade_) وسياستها تستخدم owns(client_id)
select tablename, policyname, qual
from pg_policies
where schemaname = 'public' and (tablename like 'alum\_%' or tablename like 'trade\_%')
order by tablename;

-- ============================================================
--  5) (اختياري، مرة واحدة) إلغاء الجلسات القديمة التي أعطاها الرابط سابقاً
--  كل من فتح رابط برنامج قبل هذا التعديل بقي داخلاً بحساب صاحب المؤسسة.
--  هذا يُخرج كل أصحاب المؤسسات من كل الأجهزة (يدخلون من جديد بالبريد وكلمة المرور).
--  لا يمسّ حسابات مشرفي المنصة. خلال ساعة كحد أقصى تنتهي الجلسات المفتوحة حالياً.
--  أزل علامتي التعليق (--) من السطرين التاليين ثم شغّلهما:
-- ============================================================
-- delete from auth.sessions where user_id in (select user_id from public.clients where user_id is not null)
--   and user_id not in (select user_id from public.platform_admins);
