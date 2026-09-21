-- ============================================================
--  إصلاح ترتيب المنتجات والأقسام
--  بيعطي كل صنف رقماً متسلسلاً داخل قسمه (1، 2، 3…)
--  شغّله مرة وحدة — بعدها الترتيب بيستقر
--  ما بيحذف ولا بيغيّر أي بيانات غير الترتيب
-- ============================================================

-- المنتجات: ترقيم داخل كل قسم
with numbered as (
  select id,
         row_number() over (
           partition by restaurant_id, coalesce(category_id::text,'')
           order by nullif(sort,0) nulls last, name_ar
         ) as n
  from public.items
)
update public.items i
set sort = numbered.n
from numbered
where numbered.id = i.id;

-- الأقسام: ترقيم داخل كل مطعم
with cnum as (
  select id,
         row_number() over (
           partition by restaurant_id
           order by nullif(sort,0) nulls last, name_ar
         ) as n
  from public.categories
)
update public.categories c
set sort = cnum.n
from cnum
where cnum.id = c.id;

-- تحقق
select r.slug, c.name_ar as القسم, c.sort as ترتيب_القسم,
       i.name_ar as الصنف, i.sort as ترتيب_الصنف
from public.items i
join public.categories c on c.id = i.category_id
join public.restaurants r on r.id = i.restaurant_id
order by r.slug, c.sort, i.sort;
