-- ============================================================
--  إلغاء حسابات SUPERADMIN من مؤسسات الزبائن
--
--  ما عاد إلها لزوم: الدخول الإداري صار من لوحة /super
--  عبر رابط /alum?c=<هوية الزبون> بجلستك أنت —
--  بيتخطّى الدخول الداخلي و2FA، وبيسمح لك تعدّل أي مستخدم.
-- ============================================================

-- شوف شو رح ينحذف
select c.name as "الزبون", u.username, u.role
from public.alum_app_users u
join public.clients c on c.id = u.client_id
where upper(u.username) = 'SUPERADMIN';

-- الحذف
delete from public.alum_app_users where upper(username) = 'SUPERADMIN';

-- تأكد إنو كل زبون ضلّ عنده مستخدم واحد على الأقل
select c.name as "الزبون", count(u.*) as "عدد المستخدمين"
from public.clients c
join public.subscriptions s on s.client_id = c.id and s.product_code = 'alum'
left join public.alum_app_users u on u.client_id = c.id
group by c.name
order by 2;
