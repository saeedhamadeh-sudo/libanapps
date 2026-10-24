-- ============================================================
--  فروع المطعم — نظام كامل
--  شغّله مرة وحدة على مشروع المنصة
--  آمن للتشغيل أكثر من مرة (if not exists / or replace)
-- ============================================================

-- ============================================================
-- 1) أقسام فرعية — parent_id على categories
-- ============================================================
alter table public.categories
  add column if not exists parent_id uuid references public.categories(id) on delete cascade;
-- name_fr اختياري
alter table public.categories add column if not exists name_fr text default '';

-- ============================================================
-- 2) جدول الفروع
-- ============================================================
create table if not exists public.restaurant_branches (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  name_ar       text not null,
  name_en       text not null default '',
  phone         text default '',
  whatsapp      text default '',   -- رقم واتساب لاستقبال الطلبات (بصيغة 9611234567)
  address_ar    text default '',
  address_en    text default '',
  -- ساعات العمل: { "sun":[], "mon":[{"open":"09:00","close":"22:00"}], ... }
  -- مصفوفة فترات لكل يوم (اثنين بيدعم: صباحي + مسائي)
  -- يوم مع مصفوفة فاضية = مغلق هالأسبوع
  work_hours    jsonb not null default '{
    "sun":[],"mon":[{"open":"09:00","close":"22:00"}],"tue":[{"open":"09:00","close":"22:00"}],
    "wed":[{"open":"09:00","close":"22:00"}],"thu":[{"open":"09:00","close":"22:00"}],
    "fri":[],"sat":[{"open":"09:00","close":"22:00"}]
  }'::jsonb,
  timezone      text not null default 'Asia/Beirut',
  force_closed  boolean not null default false,   -- إغلاق طارئ يدوي
  force_closed_msg_ar text default '',             -- رسالة اختيارية للإغلاق الطارئ
  force_closed_msg_en text default '',
  is_active     boolean not null default true,
  sort          integer not null default 0,
  created_at    timestamptz not null default now()
);
create index if not exists branches_rest_idx on public.restaurant_branches (restaurant_id, sort);

-- ============================================================
-- 3) توفر الأصناف بالفروع (نخزّن الاستثناءات فقط)
-- الافتراض: كل صنف متوفر بكل الفروع
-- نخزّن فقط: صنف غير متوفر بفرع معين
-- ============================================================
create table if not exists public.item_branch_override (
  item_id   uuid not null references public.items(id) on delete cascade,
  branch_id uuid not null references public.restaurant_branches(id) on delete cascade,
  is_available boolean not null default false,  -- false = مش متوفر بهالفرع
  primary key (item_id, branch_id)
);

-- ============================================================
-- 4) موظفو الفروع
-- ============================================================
-- أولاً نضيف جدول موظفين إذا ما كان موجوداً
create table if not exists public.restaurant_staff (
  id            uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants(id) on delete cascade,
  name          text not null,
  role          text not null default 'staff',  -- 'branch_manager' | 'driver' | 'staff'
  phone         text default '',
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

-- ربط موظف بفرع (موظف ممكن يكون بأكثر من فرع)
create table if not exists public.branch_staff (
  branch_id  uuid not null references public.restaurant_branches(id) on delete cascade,
  staff_id   uuid not null references public.restaurant_staff(id) on delete cascade,
  role       text not null default 'staff',  -- 'manager' | 'driver' | 'staff'
  primary key (branch_id, staff_id)
);

-- ============================================================
-- 5) تحديث جدول orders — إضافة branch_id + حقول القبول/الرفض
-- ============================================================
alter table public.orders
  add column if not exists branch_id uuid references public.restaurant_branches(id) on delete set null;
alter table public.orders
  add column if not exists branch_status text not null default 'pending'
  check (branch_status in ('pending','accepted','rejected'));
alter table public.orders
  add column if not exists rejection_reason text default '';
alter table public.orders
  add column if not exists driver_id uuid references public.restaurant_staff(id) on delete set null;
alter table public.orders
  add column if not exists branch_updated_at timestamptz;

create index if not exists orders_branch_idx on public.orders (branch_id, created_at desc);

-- ============================================================
-- 6) دالة: هل الفرع مفتوح الآن؟
-- ============================================================
create or replace function public.branch_is_open(p_branch_id uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  b  public.restaurant_branches%rowtype;
  tz text;
  now_local timestamptz;
  dow text;
  now_time time;
  periods jsonb;
  p jsonb;
begin
  select * into b from public.restaurant_branches where id = p_branch_id;
  if not found or not b.is_active then return false; end if;
  if b.force_closed then return false; end if;

  tz := coalesce(b.timezone, 'Asia/Beirut');
  now_local := now() at time zone tz;
  dow := lower(to_char(now_local, 'Dy'));  -- 'mon','tue',...
  -- Postgres to_char Dy: Mon,Tue,Wed,Thu,Fri,Sat,Sun
  -- نحوّلها لثلاثة أحرف صغيرة
  dow := lower(substr(to_char(now_local, 'Dy'), 1, 3));
  now_time := now_local::time;

  periods := b.work_hours -> dow;
  if periods is null or jsonb_array_length(periods) = 0 then return false; end if;

  for p in select * from jsonb_array_elements(periods)
  loop
    if now_time >= (p->>'open')::time and now_time < (p->>'close')::time then
      return true;
    end if;
  end loop;
  return false;
end $$;

-- ============================================================
-- 7) RLS — الفروع يشوفها الكل (قراءة) ويعدّلها صاحب المطعم
-- ============================================================
alter table public.restaurant_branches enable row level security;
drop policy if exists "branches_read"   on public.restaurant_branches;
drop policy if exists "branches_write"  on public.restaurant_branches;
create policy "branches_read" on public.restaurant_branches
  for select using (true);
create policy "branches_write" on public.restaurant_branches
  for all using (public.is_member(restaurant_id))
  with check (public.is_member(restaurant_id));

alter table public.item_branch_override enable row level security;
drop policy if exists "ibo_read"  on public.item_branch_override;
drop policy if exists "ibo_write" on public.item_branch_override;
create policy "ibo_read" on public.item_branch_override for select using (true);
create policy "ibo_write" on public.item_branch_override
  for all using (
    exists (select 1 from public.items i
            join public.restaurant_branches b on b.id = item_branch_override.branch_id
            where i.id = item_branch_override.item_id
              and public.is_member(i.restaurant_id))
  )
  with check (
    exists (select 1 from public.items i
            join public.restaurant_branches b on b.id = item_branch_override.branch_id
            where i.id = item_branch_override.item_id
              and public.is_member(i.restaurant_id))
  );

alter table public.restaurant_staff enable row level security;
drop policy if exists "staff_member"   on public.restaurant_staff;
create policy "staff_member" on public.restaurant_staff
  for all using (public.is_member(restaurant_id))
  with check (public.is_member(restaurant_id));

alter table public.branch_staff enable row level security;
drop policy if exists "bs_member" on public.branch_staff;
create policy "bs_member" on public.branch_staff
  for all using (
    exists (select 1 from public.restaurant_branches b
            where b.id = branch_staff.branch_id and public.is_member(b.restaurant_id))
  )
  with check (
    exists (select 1 from public.restaurant_branches b
            where b.id = branch_staff.branch_id and public.is_member(b.restaurant_id))
  );

-- ============================================================
-- 8) تحقق
-- ============================================================
select 'restaurant_branches' as tbl, count(*) from public.restaurant_branches
union all
select 'item_branch_override', count(*) from public.item_branch_override
union all
select 'restaurant_staff', count(*) from public.restaurant_staff
union all
select 'branch_staff', count(*) from public.branch_staff;
