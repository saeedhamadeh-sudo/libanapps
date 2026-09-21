-- ============================================================
--  مستخدمو برنامج الصناعيين — عرض وإصلاح
--  البرنامج بيولّد ADMIN و SUPERADMIN تلقائياً لكل زبون جديد
--  (SUPERADMIN كلمة مروره الافتراضية: itech@2027 — غيّرها)
-- ============================================================

-- ---------- مين موجود لكل زبون ----------
select c.name as "الزبون", u.username, u.role,
       case when upper(u.username)='SUPERADMIN' then u.password else '••••' end as "كلمة المرور"
from public.alum_app_users u
join public.clients c on c.id = u.client_id
order by c.name, u.username;

-- ---------- زبون ما عنده مستخدمين؟ ----------
--  بيصير إذا فتح البرنامج ولسا ما سجّل دخول أول مرة.
--  الحل الأسهل: يفتح /alum ويدخل بـ ADMIN / 0000 — البرنامج بيولّدهم.
select c.name as "زبون بلا مستخدمين"
from public.clients c
join public.subscriptions s on s.client_id = c.id and s.product_code = 'alum'
where not exists (
  select 1 from public.alum_app_users u where u.client_id = c.id
);
