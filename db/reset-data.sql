-- ============================================================
--  تصفير كامل — LibanApps
--
--  ⚠️  هذا الملف يحذف بيانات نهائياً. لا رجعة.
--
--  يحذف: كل المطاعم وأقسامها وأصنافها،
--         كل الطلبات والفواتير، كل الزبائن والاشتراكات والمفاتيح،
--         التراخيص القديمة، وربط أصحاب المطاعم بمطاعمهم.
--
--  لا يحذف: ملفات التخزين (تُمسح يدوياً من Storage — انظر الأسفل).
--
--  يُبقي: الجداول والدوال والسياسات (البنية كما هي)،
--         قائمة البرامج (menu / alum / trade)،
--         حسابك كمشرف منصة،
--         بيانات الدفع تُحذف مع مطاعمها تلقائياً.
--
--  الاستعمال: الصقه كاملاً في SQL Editor واضغط Run.
-- ============================================================

begin;

-- ملاحظة: الصور ما بتنحذف من هون — Supabase بتمنع الحذف المباشر
-- من جداول التخزين. امسحها من: Storage ← افتح الـbucket ←
-- علّم الكل ← Delete. (الأربعة: logos · items · banners · invoices)

-- 1) ربط أصحاب المطاعم — الحسابات نفسها تبقى في Authentication
delete from public.restaurant_users;

-- 2) المطاعم — يتسلسل الحذف إلى:
--    categories · items · banners · promos · orders · order_items
--    · payment_credentials · licenses
delete from public.restaurants;

-- 3) الزبائن — يتسلسل إلى subscriptions
delete from public.clients;

-- 4) تصفير عدّاد الطلبات (احتياطي — المطاعم انحذفت أصلاً)
update public.restaurants set order_seq = 0;

commit;

-- ============================================================
--  تحقّق: المفروض كل الأرقام صفر ما عدا products و platform_admins
-- ============================================================
select 'clients'            as t, count(*) from public.clients
union all select 'subscriptions',        count(*) from public.subscriptions
union all select 'restaurants',          count(*) from public.restaurants
union all select 'categories',           count(*) from public.categories
union all select 'items',                count(*) from public.items
union all select 'orders',               count(*) from public.orders
union all select 'order_items',          count(*) from public.order_items
union all select 'banners',              count(*) from public.banners
union all select 'promos',               count(*) from public.promos
union all select 'licenses',             count(*) from public.licenses
union all select 'payment_credentials',  count(*) from public.payment_credentials
union all select 'restaurant_users',     count(*) from public.restaurant_users
union all select '— products (يبقى)',    count(*) from public.products
union all select '— admins (يبقى)',      count(*) from public.platform_admins;

-- ============================================================
--  بعد التشغيل، امسح الصور يدوياً:
--  Storage ← logos ← علّم الكل ← Delete
--  كرّرها لـ items و banners و invoices
--
--  ملاحظة: حسابات أصحاب المطاعم
--  ما بتنحذف من هون. امسحها يدوياً من:
--  Authentication ← Users ← علّم الحساب ← Delete
--  لا تحذف حسابك أنت — بتخسر الدخول للوحة.
-- ============================================================
