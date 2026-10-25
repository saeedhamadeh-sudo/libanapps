-- ============================================================
--  إصلاح يدوي لاشتراكات التوصيل الصحيحة
--  دروفيا: مقعدين | سناك أتاك: مقعد واحد | أديز: بلا اشتراك
-- ============================================================

-- أولاً: ألغِ كل شي ونبدأ نظيف
update public.restaurants
set delivery_active     = false,
    delivery_expires_at = null,
    delivery_capacity   = 1;

delete from public.delivery_seats;

-- ============================================================
-- دروفيا — active + مقعدين إضافيين (capacity=3)
-- ============================================================
update public.restaurants
set delivery_active     = true,
    delivery_expires_at = now() + interval '1 year',
    delivery_capacity   = 3,
    dlv_included        = 1
where slug = 'drovia';

insert into public.delivery_seats(restaurant_id, expires_at, source, note)
select id, now() + interval '1 year', 'cash', 'مقعد إضافي'
from public.restaurants where slug='drovia';

insert into public.delivery_seats(restaurant_id, expires_at, source, note)
select id, now() + interval '1 year', 'cash', 'مقعد إضافي'
from public.restaurants where slug='drovia';

-- ============================================================
-- سناك أتاك — active + مقعد واحد إضافي (capacity=2)
-- ============================================================
update public.restaurants
set delivery_active     = true,
    delivery_expires_at = now() + interval '1 year',
    delivery_capacity   = 2,
    dlv_included        = 1
where slug = 'snackattack';

insert into public.delivery_seats(restaurant_id, expires_at, source, note)
select id, now() + interval '1 year', 'cash', 'مقعد إضافي'
from public.restaurants where slug='snackattack';

-- ============================================================
-- أديز ريستو — بلا اشتراك
-- ============================================================
update public.restaurants
set delivery_active     = false,
    delivery_expires_at = null,
    delivery_capacity   = 1
where slug = 'addysresto';

-- ============================================================
-- تحقق
-- ============================================================
select name_ar, slug, delivery_active, delivery_expires_at::date, delivery_capacity
from public.restaurants order by name_ar;

select r.name_ar, count(s.id) as seats
from public.restaurants r
left join public.delivery_seats s on s.restaurant_id=r.id
group by r.name_ar;
