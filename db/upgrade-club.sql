-- ============================================================
--  LibanApps — برنامج «إدارة النوادي» (Club Manager)   code = club
--
--  بيضيف:
--   • منتج جديد club (بادئة المفتاح CLUB)
--   • جداول: النوادي، الفرق، المستويات، التلاميذ، بيانات الدخول،
--     الدفعات، الميداليات، سجل المستويات، الحضور، أجهزة الباب
--   • دخول التلميذ باسم مستخدم وكلمة مرور (بدون حساب Supabase)
--   • شاشة الباب: قائمة الوجوه + التحقق من الاشتراك وتسجيل الحضور
--   • مخزن صور جديد: club
--
--  آمن للتشغيل أكثر من مرة — ما بيحذف ولا بيغيّر بيانات موجودة.
--  شرط مسبق: schema.sql + upgrade-website.sql + upgrade-apps-tenancy.sql
--            + security-fixes-1.sql (فيها is_portal_user)
-- ============================================================

create extension if not exists "pgcrypto";

-- ============================================================
--  0) ملاحظة: الملف ما بيعيد تعريف my_client_id / owns عن قصد —
--     بيستعمل النسخة الموجودة (اللي بتعرف حسابات portal_users).
-- ============================================================

-- ============================================================
--  1) المنتج
-- ============================================================
insert into public.products (code, name_ar, name_en, prefix) values
  ('club', 'إدارة النوادي', 'LibanApps Club', 'CLUB')
on conflict (code) do nothing;

-- مدة التجربة الخاصة بالبرنامج: 7 أيام
alter table public.products add column if not exists trial_days integer;
update public.products set trial_days = 7 where code = 'club' and trial_days is null;

-- سعر التجديد لكل باقة (فاضي = نفس سعر الباقة)
alter table public.plans add column if not exists renew_price_usd numeric(10,2);

-- الباقة: 500$ أول سنة — التجديد 200$ سنويًا
insert into public.plans (product_code, name_ar, name_en, days, price_usd, renew_price_usd, badge_ar, features_ar, features_en, sort)
select 'club', 'إدارة النادي — سنة', 'Club Manager — 1 year', 365, 500, 200, 'جديد',
  array['ملف كامل لكل تلميذ: صورة، مستوى، ميداليات، حضور',
        'اشتراكات شهرية: أيام متبقية ومبلغ مستحق تلقائيًا',
        'بطاقة عضوية CR80 جاهزة للطباعة PDF مع QR',
        'فتح الباب بالتعرّف على الوجه أو بطاقة QR',
        'حساب دخول لكل تلميذ يرى فيه ملفه كاملًا',
        'تذكير وإيصالات على واتساب بضغطة',
        'التجديد السنوي 200$'],
  array['Full profile per student: photo, level, medals, attendance',
        'Monthly subscriptions: days left and amount due, automatically',
        'Printable CR80 membership card PDF with QR',
        'Door opening by face recognition or QR card',
        'Login for every student to view their full profile',
        'WhatsApp reminders and receipts in one tap',
        'Yearly renewal $200'], 6
where not exists (select 1 from public.plans where product_code = 'club');

-- إعدادات برنامج النوادي من لوحة /super
create or replace function public.admin_club_product(
  p_price numeric, p_renew numeric, p_trial integer, p_active boolean default true
) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update public.products set trial_days = greatest(0, least(60, coalesce(p_trial, 7))) where code = 'club';
  update public.plans set price_usd = greatest(0, coalesce(p_price, price_usd)),
                          renew_price_usd = greatest(0, coalesce(p_renew, renew_price_usd)),
                          is_active = coalesce(p_active, is_active)
   where product_code = 'club';
  return jsonb_build_object('ok', true);
end $$;

-- التجديد يدفع «سعر التجديد» إذا محدَّد للباقة (مثلاً النوادي: 200$ بدل 500$)
create or replace function public.start_renewal(p_plan uuid, p_sub uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pl public.plans%rowtype; s public.subscriptions%rowtype; cid uuid; pid bigint; amt numeric;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select id into cid from public.clients where user_id = auth.uid();
  if cid is null then raise exception 'no client'; end if;
  select * into s from public.subscriptions where id = p_sub and client_id = cid;
  if not found then raise exception 'subscription not found'; end if;
  select * into pl from public.plans where id = p_plan and is_active;
  if not found then raise exception 'plan not found'; end if;
  if pl.product_code <> s.product_code then raise exception 'plan/product mismatch'; end if;
  -- التجربة المجانية ما بتنحسب تجديد: أول دفعة بعد التجربة بسعر السنة الأولى
  amt := case when s.plan = 'trial' then pl.price_usd
              else coalesce(pl.renew_price_usd, pl.price_usd) end;
  insert into public.purchases (user_id, client_id, plan_id, product_code,
                               amount_usd, days, slug, biz_name, renew_of)
  values (auth.uid(), cid, pl.id, pl.product_code, amt, pl.days, coalesce(s.ref_slug,''), '', s.id)
  returning id into pid;
  return jsonb_build_object('purchase_id', pid, 'amount', amt);
end $$;

-- ============================================================
--  2) الجداول
-- ============================================================
create table if not exists public.clubs (
  id               uuid primary key default gen_random_uuid(),
  client_id        uuid not null references public.clients(id) on delete cascade,
  slug             text unique not null,
  name             text not null default '',
  sport            text default '',
  logo_url         text default '',
  whatsapp         text default '',          -- أرقام فقط مع رمز الدولة
  phone            text default '',
  address          text default '',
  primary_color    text not null default '#0f766e',
  accent_color     text not null default '#f59e0b',
  currency_symbol  text not null default '$',
  default_fee      numeric(12,2) not null default 0,
  expiring_days    integer not null default 5  check (expiring_days between 0 and 60),
  grace_days       integer not null default 0  check (grace_days between 0 and 30),
  default_lang     text not null default 'ar' check (default_lang in ('ar','en','fr')),
  timezone         text not null default 'Asia/Beirut',
  card_note        text default '',
  door_open_url    text default '',          -- رابط تشغيل الريليه (Shelly / ESP32 ...)
  door_open_method text not null default 'GET' check (door_open_method in ('GET','POST')),
  door_open_body   text default '',
  door_threshold   numeric(4,2) not null default 0.50 check (door_threshold between 0.30 and 0.70),
  door_qr_enabled  boolean not null default true,
  door_face_enabled boolean not null default true,
  student_seq      integer not null default 0,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now()
);
create index if not exists clubs_client_idx on public.clubs (client_id);

do $$ begin
  alter table public.clubs add constraint clubs_slug_format
    check (slug ~ '^[a-z0-9][a-z0-9-]{1,30}$');
exception when duplicate_object then null; end $$;

create or replace function public.clubs_lock_fields()
returns trigger language plpgsql as $$
begin
  if not public.is_admin() then
    if new.slug <> old.slug then raise exception 'slug is locked'; end if;
    if new.client_id <> old.client_id then raise exception 'owner is locked'; end if;
    if new.student_seq <> old.student_seq and current_setting('club.seq', true) is distinct from '1' then
      new.student_seq := old.student_seq;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists clubs_lock on public.clubs;
create trigger clubs_lock before update on public.clubs
  for each row execute function public.clubs_lock_fields();

create table if not exists public.club_groups (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs(id) on delete cascade,
  name        text not null,
  schedule    text default '',               -- مثال: الإثنين والأربعاء 5-7
  coach       text default '',
  monthly_fee numeric(12,2),                 -- فاضي = قسط النادي الافتراضي
  sort        integer not null default 0,
  is_active   boolean not null default true
);
create index if not exists club_groups_idx on public.club_groups (club_id, sort);

create table if not exists public.club_levels (
  id       uuid primary key default gen_random_uuid(),
  club_id  uuid not null references public.clubs(id) on delete cascade,
  name     text not null,
  color    text not null default '#64748b',
  sort     integer not null default 0
);
create index if not exists club_levels_idx on public.club_levels (club_id, sort);

create table if not exists public.club_students (
  id            uuid primary key default gen_random_uuid(),
  club_id       uuid not null references public.clubs(id) on delete cascade,
  code          text not null default '',
  full_name     text not null,
  photo_url     text default '',
  birth_date    date,
  gender        text default '' check (gender in ('','m','f')),
  phone         text default '',
  parent_name   text default '',
  parent_phone  text default '',
  address       text default '',
  group_id      uuid references public.club_groups(id) on delete set null,
  level_id      uuid references public.club_levels(id) on delete set null,
  level_since   date,
  monthly_fee   numeric(12,2),               -- فاضي = قسط الفرقة أو النادي
  joined_at     date not null default current_date,
  paid_until    date,                        -- آخر يوم مدفوع (شامل)
  username      text,
  face          jsonb not null default '[]'::jsonb,   -- بصمات الوجه [[128 رقم], ...]
  face_updated_at timestamptz,
  face_count    integer not null default 0,
  card_token    text not null default encode(gen_random_bytes(12),'hex'),
  notes         text default '',
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);
alter table public.club_students add column if not exists face_count integer not null default 0;
create index if not exists club_students_idx on public.club_students (club_id, full_name);
create unique index if not exists club_students_code_uq on public.club_students (club_id, code);
create unique index if not exists club_students_user_uq on public.club_students (club_id, lower(username))
  where username is not null and username <> '';
create unique index if not exists club_students_card_uq on public.club_students (card_token);

-- كلمات المرور والقفل — بدون أي سياسة قراءة (لا أحد يقرأها مباشرة)
create table if not exists public.club_student_secrets (
  student_id    uuid primary key references public.club_students(id) on delete cascade,
  password_hash text not null,
  failed_count  integer not null default 0,
  locked_until  timestamptz,
  updated_at    timestamptz not null default now()
);

create table if not exists public.club_sessions (
  token_hash  text primary key,
  student_id  uuid not null references public.club_students(id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '60 days'
);
create index if not exists club_sessions_student_idx on public.club_sessions (student_id);

create table if not exists public.club_payments (
  id           uuid primary key default gen_random_uuid(),
  club_id      uuid not null references public.clubs(id) on delete cascade,
  student_id   uuid not null references public.club_students(id) on delete cascade,
  amount       numeric(12,2) not null default 0,
  months       integer not null default 1 check (months between 1 and 36),
  period_from  date not null,
  period_to    date not null,
  method       text not null default 'cash' check (method in ('cash','whish','card','transfer','other')),
  note         text default '',
  created_at   timestamptz not null default now()
);
create index if not exists club_payments_idx on public.club_payments (club_id, created_at desc);
create index if not exists club_payments_st_idx on public.club_payments (student_id, period_to desc);

create table if not exists public.club_achievements (
  id          uuid primary key default gen_random_uuid(),
  club_id     uuid not null references public.clubs(id) on delete cascade,
  student_id  uuid not null references public.club_students(id) on delete cascade,
  title       text not null,                       -- البطولة / المباراة
  opponent    text default '',
  event_date  date,
  place       text not null default 'gold' check (place in ('gold','silver','bronze','participation','other')),
  category    text default '',                     -- فئة الوزن / العمر ...
  image_url   text default '',
  note        text default '',
  created_at  timestamptz not null default now()
);
create index if not exists club_ach_idx on public.club_achievements (student_id, event_date desc);

create table if not exists public.club_level_history (
  id          bigint generated always as identity primary key,
  club_id     uuid not null references public.clubs(id) on delete cascade,
  student_id  uuid not null references public.club_students(id) on delete cascade,
  level_name  text not null,
  level_color text default '',
  changed_at  timestamptz not null default now()
);
create index if not exists club_lvh_idx on public.club_level_history (student_id, changed_at desc);

create table if not exists public.club_attendance (
  id          bigint generated always as identity primary key,
  club_id     uuid not null references public.clubs(id) on delete cascade,
  student_id  uuid references public.club_students(id) on delete cascade,
  at          timestamptz not null default now(),
  method      text not null default 'face' check (method in ('face','qr','manual')),
  allowed     boolean not null default true,
  reason      text default '',
  door_name   text default ''
);
create index if not exists club_att_idx on public.club_attendance (club_id, at desc);
create index if not exists club_att_st_idx on public.club_attendance (student_id, at desc);

-- أجهزة الباب: المفتاح نفسه ما بينحفظ — بس الـhash
create table if not exists public.club_doors (
  id           uuid primary key default gen_random_uuid(),
  club_id      uuid not null references public.clubs(id) on delete cascade,
  name         text not null default '',
  key_hash     text not null unique,
  last_seen_at timestamptz,
  revoked      boolean not null default false,
  created_at   timestamptz not null default now()
);
create index if not exists club_doors_idx on public.club_doors (club_id);

-- ---------- البنية الجسدية والإصابات ----------
-- خيارات يحددها مدير النادي (يضيف ويحذف منها)
alter table public.clubs add column if not exists body_options   text[] not null
  default array['ممتازة','جيدة','متوسطة','تحتاج إلى متابعة'];
alter table public.clubs add column if not exists injury_options text[] not null
  default array['التواء الكاحل','إصابة الركبة','إصابة الكتف','آلام الظهر','كسر سابق','إصابة الرأس / ارتجاج'];

alter table public.club_students add column if not exists weight_kg    numeric(5,1);
alter table public.club_students add column if not exists height_cm    numeric(5,1);
alter table public.club_students add column if not exists body_status  text not null default '';
alter table public.club_students add column if not exists injuries     text[] not null default '{}';
alter table public.club_students add column if not exists injury_notes text not null default '';

-- سجل القياسات: كل تغيير بالوزن أو الطول أو البنية بينحفظ تلقائيًا
create table if not exists public.club_body_log (
  id          bigint generated always as identity primary key,
  club_id     uuid not null references public.clubs(id) on delete cascade,
  student_id  uuid not null references public.club_students(id) on delete cascade,
  measured_on date not null default current_date,
  weight_kg   numeric(5,1),
  height_cm   numeric(5,1),
  body_status text default '',
  created_at  timestamptz not null default now()
);
create index if not exists club_body_log_idx on public.club_body_log (student_id, measured_on desc);

-- ============================================================
--  3) المحفّزات (Triggers)
-- ============================================================
-- رقم التلميذ التسلسلي داخل النادي (0001، 0002 ...)
create or replace function public.club_students_before_ins()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare n integer;
begin
  perform set_config('club.seq', '1', true);
  update public.clubs set student_seq = student_seq + 1 where id = new.club_id
  returning student_seq into n;
  perform set_config('club.seq', '0', true);
  if coalesce(new.code,'') = '' then new.code := lpad(n::text, 4, '0'); end if;
  if new.username is not null then new.username := lower(trim(new.username)); end if;
  if new.username = '' then new.username := null; end if;
  if new.level_id is not null and new.level_since is null then new.level_since := current_date; end if;
  new.face_count := case when jsonb_typeof(new.face) = 'array' then jsonb_array_length(new.face) else 0 end;
  return new;
end $$;
drop trigger if exists club_students_ins on public.club_students;
create trigger club_students_ins before insert on public.club_students
  for each row execute function public.club_students_before_ins();

create or replace function public.club_students_before_upd()
returns trigger language plpgsql as $$
begin
  if new.club_id <> old.club_id then raise exception 'club is locked'; end if;
  if new.username is not null then new.username := lower(trim(new.username)); end if;
  if new.username = '' then new.username := null; end if;
  if new.level_id is distinct from old.level_id then new.level_since := current_date; end if;
  if new.face is distinct from old.face then
    if jsonb_typeof(new.face) <> 'array' then new.face := '[]'::jsonb; end if;
    if jsonb_array_length(new.face) > 8 then raise exception 'too many face samples'; end if;
    new.face_updated_at := now();
    new.face_count := jsonb_array_length(new.face);
  end if;
  return new;
end $$;
drop trigger if exists club_students_upd on public.club_students;
create trigger club_students_upd before update on public.club_students
  for each row execute function public.club_students_before_upd();

-- سجل المستويات (ترقية الحزام/الدرجة)
create or replace function public.club_students_level_log()
returns trigger language plpgsql security definer set search_path = public as $$
declare lv public.club_levels%rowtype;
begin
  if new.level_id is not null and (tg_op = 'INSERT' or new.level_id is distinct from old.level_id) then
    select * into lv from public.club_levels where id = new.level_id;
    if found then
      insert into public.club_level_history (club_id, student_id, level_name, level_color)
      values (new.club_id, new.id, lv.name, lv.color);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists club_students_lvl on public.club_students;
create trigger club_students_lvl after insert or update of level_id on public.club_students
  for each row execute function public.club_students_level_log();

create or replace function public.club_students_body_log()
returns trigger language plpgsql security definer set search_path = public as $$
declare tz text; d date;
begin
  if tg_op = 'INSERT' then
    if new.weight_kg is null and new.height_cm is null and coalesce(new.body_status,'') = '' then return new; end if;
  elsif new.weight_kg is not distinct from old.weight_kg and new.height_cm is not distinct from old.height_cm
        and coalesce(new.body_status,'') = coalesce(old.body_status,'') then
    return new;
  end if;
  select timezone into tz from public.clubs where id = new.club_id;
  d := (now() at time zone coalesce(tz,'Asia/Beirut'))::date;
  -- قياس واحد باليوم: تعديل بنفس اليوم بيحدّث نفس السطر
  update public.club_body_log set weight_kg = new.weight_kg, height_cm = new.height_cm, body_status = new.body_status
   where student_id = new.id and measured_on = d;
  if not found then
    insert into public.club_body_log (club_id, student_id, measured_on, weight_kg, height_cm, body_status)
    values (new.club_id, new.id, d, new.weight_kg, new.height_cm, new.body_status);
  end if;
  return new;
end $$;
drop trigger if exists club_students_body on public.club_students;
create trigger club_students_body after insert or update of weight_kg, height_cm, body_status on public.club_students
  for each row execute function public.club_students_body_log();

-- ============================================================
--  4) الصلاحيات (RLS)
-- ============================================================
create or replace function public.club_owned(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or (not public.is_portal_user() and exists (
    select 1 from public.clubs c
    where c.id = cid and c.client_id = public.my_client_id()));
$$;

alter table public.clubs                enable row level security;
alter table public.club_groups          enable row level security;
alter table public.club_levels          enable row level security;
alter table public.club_students        enable row level security;
alter table public.club_student_secrets enable row level security;
alter table public.club_sessions        enable row level security;
alter table public.club_payments        enable row level security;
alter table public.club_achievements    enable row level security;
alter table public.club_level_history   enable row level security;
alter table public.club_attendance      enable row level security;
alter table public.club_doors           enable row level security;
alter table public.club_body_log        enable row level security;

drop policy if exists own_clubs on public.clubs;
create policy own_clubs on public.clubs for all to authenticated
  using (public.club_owned(id))
  with check (public.is_admin() or (not public.is_portal_user() and public.owns(client_id)));

do $$
declare t text;
begin
  foreach t in array array['club_groups','club_levels','club_students','club_achievements','club_attendance','club_body_log']
  loop
    execute format('drop policy if exists own_%1$s on public.%1$s', t);
    execute format('create policy own_%1$s on public.%1$s for all to authenticated
                    using (public.club_owned(club_id)) with check (public.club_owned(club_id))', t);
  end loop;
end $$;

-- الدفعات: قراءة وحذف — الإضافة عبر club_add_payment فقط (لتمديد الاشتراك بشكل صحيح)
drop policy if exists own_club_payments_sel on public.club_payments;
create policy own_club_payments_sel on public.club_payments for select to authenticated
  using (public.club_owned(club_id));

drop policy if exists own_club_lvh on public.club_level_history;
create policy own_club_lvh on public.club_level_history for select to authenticated
  using (public.club_owned(club_id));
drop policy if exists own_club_lvh_del on public.club_level_history;
create policy own_club_lvh_del on public.club_level_history for delete to authenticated
  using (public.club_owned(club_id));

drop policy if exists own_club_doors on public.club_doors;
create policy own_club_doors on public.club_doors for select to authenticated
  using (public.club_owned(club_id));

-- club_student_secrets / club_sessions: بدون سياسات — عبر الدوال فقط

-- ============================================================
--  5) الترخيص والإنشاء
-- ============================================================
create or replace function public.club_license(cid uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cl public.clubs%rowtype; s public.subscriptions%rowtype;
begin
  select * into cl from public.clubs where id = cid;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select * into s from public.subscriptions
   where client_id = cl.client_id and product_code = 'club' and ref_slug = cl.slug
   order by expires_at desc limit 1;
  if not found then return jsonb_build_object('ok', false, 'reason', 'no_subscription'); end if;
  return jsonb_build_object(
    'ok',        (s.status = 'active' and s.expires_at > now()),
    'reason',    case when s.status <> 'active' then 'suspended'
                      when s.expires_at <= now() then 'expired' else 'active' end,
    'plan',      s.plan,
    'trial',     (s.plan = 'trial'),
    'expires_at', s.expires_at,
    'days_left', greatest(0, ceil(extract(epoch from (s.expires_at - now()))/86400))::int);
end $$;

create or replace function public.club_slug_available(p_slug text)
returns boolean language sql stable security definer set search_path = public as $$
  select lower(trim(coalesce(p_slug,''))) ~ '^[a-z0-9][a-z0-9-]{1,30}$'
     and not exists (select 1 from public.clubs where slug = lower(trim(p_slug)))
     and not exists (select 1 from public.subscriptions
                     where product_code = 'club' and ref_slug = lower(trim(p_slug)));
$$;

create or replace function public._make_club(p_client uuid, p_slug text, p_name text)
returns public.clubs language plpgsql security definer set search_path = public as $$
declare c public.clients%rowtype; cl public.clubs;
begin
  select * into c from public.clients where id = p_client;
  insert into public.clubs (client_id, slug, name, whatsapp, phone)
  values (p_client, p_slug, coalesce(nullif(trim(p_name),''), p_slug),
          regexp_replace(coalesce(c.phone,''),'\D','','g'), coalesce(c.phone,''))
  returning * into cl;
  insert into public.club_levels (club_id, name, color, sort) values
    (cl.id, 'مبتدئ',  '#94a3b8', 1),
    (cl.id, 'متوسط',  '#0ea5e9', 2),
    (cl.id, 'متقدّم', '#f59e0b', 3),
    (cl.id, 'محترف',  '#111827', 4);
  return cl;
end $$;
revoke all on function public._make_club(uuid, text, text) from public, anon, authenticated;

create or replace function public.admin_new_club(
  p_client uuid, p_slug text, p_biz text, p_days integer, p_price numeric default 0
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_slug text; cl public.clubs; s public.subscriptions;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  v_slug := lower(trim(coalesce(p_slug,'')));
  if v_slug !~ '^[a-z0-9][a-z0-9-]{1,30}$' then raise exception 'invalid slug'; end if;
  if not public.club_slug_available(v_slug) then raise exception 'slug taken'; end if;
  cl := public._make_club(p_client, v_slug, p_biz);
  insert into public.subscriptions (client_id, product_code, key, plan, expires_at,
                                    price_usd, ref_slug, notes)
  values (p_client, 'club', public.gen_license_key('club'),
          case when p_days <= 7 then 'trial' when p_days <= 31 then 'monthly' else 'yearly' end,
          now() + make_interval(days => greatest(1, p_days)),
          coalesce(p_price,0), v_slug, 'إصدار يدوي')
  returning * into s;
  return jsonb_build_object('ok', true, 'key', s.key, 'expires_at', s.expires_at, 'slug', v_slug);
end $$;

-- تجربة مجانية (7 أيام افتراضيًا — تتغيّر من /super)
create or replace function public.start_club_trial(p_slug text, p_biz text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare cid uuid; v_slug text; d integer; s public.subscriptions; cl public.clubs;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select id into cid from public.clients where user_id = auth.uid();
  if cid is null then raise exception 'complete your profile first'; end if;
  if exists (select 1 from public.subscriptions where client_id = cid and product_code = 'club') then
    return jsonb_build_object('ok', false, 'reason', 'لديك اشتراك أو تجربة سابقة لهذا البرنامج');
  end if;
  v_slug := lower(trim(coalesce(p_slug,'')));
  if v_slug !~ '^[a-z0-9][a-z0-9-]{1,30}$' then
    return jsonb_build_object('ok', false, 'reason', 'يجب أن يكون الرابط بأحرف إنكليزية وأرقام وشَرطة، بطول بين 2 و31 حرفًا');
  end if;
  if not public.club_slug_available(v_slug) then
    return jsonb_build_object('ok', false, 'reason', 'هذا الرابط محجوز — اختر رابطًا آخر');
  end if;
  select coalesce(trial_days, 7) into d from public.products where code = 'club';
  if coalesce(d,0) <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'التجربة المجانية غير متاحة حاليًا لهذا البرنامج');
  end if;
  cl := public._make_club(cid, v_slug, p_biz);
  insert into public.subscriptions (client_id, product_code, key, plan, expires_at, price_usd, ref_slug, notes)
  values (cid, 'club', public.gen_license_key('club'), 'trial',
          now() + make_interval(days => d), 0, v_slug, 'تجربة مجانية')
  returning * into s;
  return jsonb_build_object('ok', true, 'key', s.key, 'expires_at', s.expires_at,
                            'days', d, 'slug', v_slug, 'subscription_id', s.id);
end $$;

-- إذا انعمل اشتراك club بدون نادي (مثلاً من الشراء) — منبني النادي أول ما يفتح اللوحة
create or replace function public.ensure_club(p_slug text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_slug text; cl public.clubs; cid uuid; s public.subscriptions;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  v_slug := lower(trim(coalesce(p_slug,'')));
  select * into cl from public.clubs where slug = v_slug;
  if found then
    if not public.club_owned(cl.id) then raise exception 'not allowed'; end if;
    return to_jsonb(cl);
  end if;
  cid := public.my_client_id();
  if cid is null then raise exception 'no client'; end if;
  select * into s from public.subscriptions
   where client_id = cid and product_code = 'club' and ref_slug = v_slug limit 1;
  if not found then raise exception 'no subscription for this club'; end if;
  select * into cl from public._make_club(cid, v_slug, '');
  return to_jsonb(cl);
end $$;

-- ============================================================
--  6) حالة الاشتراك (أيام متبقية / مستحق)
-- ============================================================
create or replace function public._club_today(p_tz text)
returns date language sql stable as $$
  select (now() at time zone coalesce(nullif(p_tz,''),'Asia/Beirut'))::date;
$$;

create or replace function public._club_fee(st public.club_students)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(st.monthly_fee,
                  (select g.monthly_fee from public.club_groups g where g.id = st.group_id),
                  (select c.default_fee from public.clubs c where c.id = st.club_id), 0);
$$;

-- state: active | expiring | expired | none
create or replace function public._club_status(p_paid_until date, p_fee numeric, p_today date,
                                               p_expiring integer, p_grace integer default 0)
returns jsonb language plpgsql immutable as $$
declare d integer; m integer := 0; a interval; st text;
begin
  if p_paid_until is null then
    return jsonb_build_object('state','none','days_left',0,'owed_months',1,
                              'owed', coalesce(p_fee,0),'door_ok', false);
  end if;
  d := p_paid_until - p_today;
  if d >= 0 then
    st := case when d < coalesce(p_expiring,5) then 'expiring' else 'active' end;
  else
    st := 'expired';
    a := age(p_today, p_paid_until);
    m := (extract(year from a)*12 + extract(month from a))::int
         + case when extract(day from a) > 0 then 1 else 0 end;
    m := greatest(1, m);
  end if;
  return jsonb_build_object('state', st, 'days_left', greatest(d,0) + case when d >= 0 then 1 else 0 end,
                            'overdue_days', greatest(-d,0),
                            'owed_months', m, 'owed', round(m * coalesce(p_fee,0), 2),
                            'door_ok', d >= -coalesce(p_grace,0));
end $$;

-- ============================================================
--  7) دوال المدير
-- ============================================================
-- تسجيل دفعة وتمديد الاشتراك
--  p_from: 'continue' = من بعد آخر فترة مدفوعة (يدفع المتأخر)
--          'today'    = من اليوم (يتجاهل الأشهر الفائتة)
create or replace function public.club_add_payment(
  p_student uuid, p_months integer, p_amount numeric, p_method text default 'cash',
  p_note text default '', p_from text default 'continue'
) returns jsonb language plpgsql security definer set search_path = public as $$
declare st public.club_students%rowtype; cl public.clubs%rowtype;
        v_today date; v_from date; v_to date; v_id uuid;
begin
  select * into st from public.club_students where id = p_student for update;
  if not found or not public.club_owned(st.club_id) then raise exception 'not allowed'; end if;
  select * into cl from public.clubs where id = st.club_id;
  if p_months is null or p_months < 1 or p_months > 36 then raise exception 'invalid months'; end if;
  if coalesce(p_method,'cash') not in ('cash','whish','card','transfer','other') then
    raise exception 'invalid method'; end if;

  v_today := public._club_today(cl.timezone);
  if st.paid_until is null then
    v_from := v_today;
  elsif st.paid_until >= v_today then
    v_from := st.paid_until + 1;                -- لسه فعّال: منكمّل من بعد آخر يوم
  elsif p_from = 'today' then
    v_from := v_today;
  else
    v_from := st.paid_until + 1;                -- منتهي ومنكمّل الدورة (بيسدّ المتأخر)
  end if;
  v_to := (v_from + make_interval(months => p_months))::date - 1;

  insert into public.club_payments (club_id, student_id, amount, months, period_from, period_to, method, note)
  values (st.club_id, st.id, coalesce(p_amount,0), p_months, v_from, v_to,
          coalesce(p_method,'cash'), coalesce(p_note,''))
  returning id into v_id;

  update public.club_students set paid_until = v_to where id = st.id;
  return jsonb_build_object('ok', true, 'id', v_id, 'period_from', v_from, 'period_to', v_to);
end $$;

-- حذف دفعة: منرجّع «مدفوع لغاية» لآخر فترة باقية
create or replace function public.club_delete_payment(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.club_payments%rowtype; v_to date;
begin
  select * into p from public.club_payments where id = p_id;
  if not found or not public.club_owned(p.club_id) then raise exception 'not allowed'; end if;
  delete from public.club_payments where id = p_id;
  select max(period_to) into v_to from public.club_payments where student_id = p.student_id;
  update public.club_students set paid_until = v_to where id = p.student_id;
  return jsonb_build_object('ok', true, 'paid_until', v_to);
end $$;

-- اسم المستخدم وكلمة المرور للتلميذ
create or replace function public.club_set_login(p_student uuid, p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare st public.club_students%rowtype; u text;
begin
  select * into st from public.club_students where id = p_student;
  if not found or not public.club_owned(st.club_id) then raise exception 'not allowed'; end if;
  u := lower(trim(coalesce(p_username,'')));
  if u !~ '^[a-z0-9._-]{3,30}$' then raise exception 'invalid username'; end if;
  if exists (select 1 from public.club_students
             where club_id = st.club_id and lower(username) = u and id <> st.id) then
    raise exception 'username taken';
  end if;
  update public.club_students set username = u where id = st.id;
  if coalesce(p_password,'') <> '' then
    if length(p_password) < 4 then raise exception 'password too short'; end if;
    insert into public.club_student_secrets (student_id, password_hash)
    values (st.id, crypt(p_password, gen_salt('bf', 8)))
    on conflict (student_id) do update set password_hash = excluded.password_hash,
      failed_count = 0, locked_until = null, updated_at = now();
    delete from public.club_sessions where student_id = st.id;   -- تسجيل خروج من كل الأجهزة
  end if;
  return jsonb_build_object('ok', true, 'username', u,
    'has_password', exists (select 1 from public.club_student_secrets where student_id = st.id));
end $$;

create or replace function public.club_login_status(p_club uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when not public.club_owned(p_club) then '[]'::jsonb else
    coalesce(jsonb_agg(s.student_id), '[]'::jsonb) end
  from public.club_student_secrets s
  join public.club_students st on st.id = s.student_id
  where st.club_id = p_club;
$$;

-- بطاقة ضاعت: رمز QR جديد (البطاقة القديمة بتوقف)
create or replace function public.club_new_card_token(p_student uuid)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare st public.club_students%rowtype; t text;
begin
  select * into st from public.club_students where id = p_student;
  if not found or not public.club_owned(st.club_id) then raise exception 'not allowed'; end if;
  t := encode(gen_random_bytes(12),'hex');
  update public.club_students set card_token = t where id = st.id;
  return t;
end $$;

-- جهاز باب جديد — المفتاح بيرجع مرة وحدة بس
create or replace function public.club_new_door(p_club uuid, p_name text default '')
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare k text; d public.club_doors%rowtype;
begin
  if not public.club_owned(p_club) then raise exception 'not allowed'; end if;
  k := encode(gen_random_bytes(18),'hex');
  insert into public.club_doors (club_id, name, key_hash)
  values (p_club, coalesce(nullif(trim(p_name),''),'Door'), encode(digest(k,'sha256'),'hex'))
  returning * into d;
  return jsonb_build_object('ok', true, 'id', d.id, 'key', k);
end $$;

create or replace function public.club_revoke_door(p_door uuid)
returns void language plpgsql security definer set search_path = public as $$
declare d public.club_doors%rowtype;
begin
  select * into d from public.club_doors where id = p_door;
  if not found or not public.club_owned(d.club_id) then raise exception 'not allowed'; end if;
  update public.club_doors set revoked = true where id = p_door;
end $$;

-- حضور يدوي من اللوحة
create or replace function public.club_manual_checkin(p_student uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare st public.club_students%rowtype; cl public.clubs%rowtype; s jsonb;
begin
  select * into st from public.club_students where id = p_student;
  if not found or not public.club_owned(st.club_id) then raise exception 'not allowed'; end if;
  select * into cl from public.clubs where id = st.club_id;
  s := public._club_status(st.paid_until, public._club_fee(st), public._club_today(cl.timezone),
                           cl.expiring_days, cl.grace_days);
  insert into public.club_attendance (club_id, student_id, method, allowed, reason, door_name)
  values (st.club_id, st.id, 'manual', true, s->>'state', '');
  return jsonb_build_object('ok', true) || s;
end $$;

-- لوحة القيادة
create or replace function public.club_dashboard(p_club uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cl public.clubs%rowtype; t date; m0 date;
begin
  if not public.club_owned(p_club) then raise exception 'not allowed'; end if;
  select * into cl from public.clubs where id = p_club;
  t := public._club_today(cl.timezone);
  m0 := date_trunc('month', t)::date;
  return jsonb_build_object(
    'today', t,
    'students', (select count(*) from public.club_students where club_id = p_club and is_active),
    'active',   (select count(*) from public.club_students where club_id = p_club and is_active
                 and paid_until >= t + cl.expiring_days),
    'expiring', (select count(*) from public.club_students where club_id = p_club and is_active
                 and paid_until >= t and paid_until < t + cl.expiring_days),
    'expired',  (select count(*) from public.club_students where club_id = p_club and is_active
                 and (paid_until is null or paid_until < t)),
    'revenue_month', (select coalesce(sum(amount),0) from public.club_payments
                      where club_id = p_club
                        and (created_at at time zone cl.timezone)::date >= m0),
    'revenue_prev', (select coalesce(sum(amount),0) from public.club_payments
                      where club_id = p_club
                        and (created_at at time zone cl.timezone)::date >= (m0 - interval '1 month')::date
                        and (created_at at time zone cl.timezone)::date < m0),
    'owed_total', (select coalesce(sum((public._club_status(s.paid_until, public._club_fee(s), t,
                                         cl.expiring_days)->>'owed')::numeric),0)
                   from public.club_students s
                   where s.club_id = p_club and s.is_active and (s.paid_until is null or s.paid_until < t)),
    'checkins_today', (select count(distinct student_id) from public.club_attendance
                       where club_id = p_club and allowed
                         and (at at time zone cl.timezone)::date = t),
    'denied_today', (select count(*) from public.club_attendance
                     where club_id = p_club and not allowed
                       and (at at time zone cl.timezone)::date = t),
    'medals', (select count(*) from public.club_achievements where club_id = p_club
               and place in ('gold','silver','bronze')),
    'by_day', (select coalesce(jsonb_agg(jsonb_build_object('d', d::date, 'n', coalesce(n,0)) order by d), '[]'::jsonb)
               from generate_series(t - 13, t, interval '1 day') d
               left join (select (at at time zone cl.timezone)::date as day, count(distinct student_id) n
                          from public.club_attendance
                          where club_id = p_club and allowed and at > now() - interval '15 days'
                          group by 1) x on x.day = d::date)
  );
end $$;

-- ============================================================
--  8) صفحة التلميذ (بدون حساب Supabase)
-- ============================================================
create or replace function public.club_public(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cl public.clubs%rowtype; lic jsonb;
begin
  select * into cl from public.clubs where slug = lower(trim(coalesce(p_slug,'')));
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  lic := public.club_license(cl.id);
  return jsonb_build_object(
    'ok', cl.is_active and (lic->>'ok')::boolean,
    'reason', case when not cl.is_active then 'inactive' else lic->>'reason' end,
    'club', jsonb_build_object('name', cl.name, 'sport', cl.sport, 'logo_url', cl.logo_url,
             'whatsapp', cl.whatsapp, 'phone', cl.phone, 'address', cl.address,
             'primary_color', cl.primary_color, 'accent_color', cl.accent_color,
             'default_lang', cl.default_lang, 'slug', cl.slug));
end $$;

create or replace function public._club_session(p_token text)
returns uuid language sql stable security definer set search_path = public, extensions as $$
  select s.student_id from public.club_sessions s
  where s.token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex')
    and s.expires_at > now() limit 1;
$$;
revoke all on function public._club_session(text) from public, anon, authenticated;

create or replace function public.club_student_login(p_slug text, p_username text, p_password text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare cl public.clubs%rowtype; st public.club_students%rowtype;
        sc public.club_student_secrets%rowtype; tok text;
begin
  select * into cl from public.clubs where slug = lower(trim(coalesce(p_slug,'')));
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if not cl.is_active or not (public.club_license(cl.id)->>'ok')::boolean then
    return jsonb_build_object('ok', false, 'reason', 'club_inactive');
  end if;

  select * into st from public.club_students
   where club_id = cl.id and lower(username) = lower(trim(coalesce(p_username,'')));
  if not found then
    perform pg_sleep(0.4);
    return jsonb_build_object('ok', false, 'reason', 'bad_login');
  end if;
  select * into sc from public.club_student_secrets where student_id = st.id for update;
  if not found then return jsonb_build_object('ok', false, 'reason', 'bad_login'); end if;
  if sc.locked_until is not null and sc.locked_until > now() then
    return jsonb_build_object('ok', false, 'reason', 'locked',
      'minutes', ceil(extract(epoch from (sc.locked_until - now()))/60)::int);
  end if;
  if sc.password_hash <> crypt(coalesce(p_password,''), sc.password_hash) then
    update public.club_student_secrets
       set failed_count = failed_count + 1,
           locked_until = case when failed_count + 1 >= 6 then now() + interval '15 minutes' end
     where student_id = st.id;
    return jsonb_build_object('ok', false, 'reason', 'bad_login');
  end if;
  if not st.is_active then return jsonb_build_object('ok', false, 'reason', 'student_inactive'); end if;

  update public.club_student_secrets set failed_count = 0, locked_until = null where student_id = st.id;
  delete from public.club_sessions where student_id = st.id and expires_at < now();
  tok := encode(gen_random_bytes(24),'hex');
  insert into public.club_sessions (token_hash, student_id)
  values (encode(digest(tok,'sha256'),'hex'), st.id);
  return jsonb_build_object('ok', true, 'token', tok);
end $$;

create or replace function public.club_student_logout(p_token text)
returns void language sql security definer set search_path = public, extensions as $$
  delete from public.club_sessions
  where token_hash = encode(digest(coalesce(p_token,''),'sha256'),'hex');
$$;

create or replace function public.club_student_password(p_token text, p_old text, p_new text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare sid uuid; sc public.club_student_secrets%rowtype;
begin
  sid := public._club_session(p_token);
  if sid is null then return jsonb_build_object('ok', false, 'reason', 'session'); end if;
  select * into sc from public.club_student_secrets where student_id = sid;
  if sc.password_hash <> crypt(coalesce(p_old,''), sc.password_hash) then
    return jsonb_build_object('ok', false, 'reason', 'bad_old');
  end if;
  if length(coalesce(p_new,'')) < 4 then return jsonb_build_object('ok', false, 'reason', 'short'); end if;
  update public.club_student_secrets set password_hash = crypt(p_new, gen_salt('bf', 8)), updated_at = now()
   where student_id = sid;
  delete from public.club_sessions where student_id = sid
    and token_hash <> encode(digest(p_token,'sha256'),'hex');
  return jsonb_build_object('ok', true);
end $$;

-- ملف التلميذ الكامل
create or replace function public.club_student_me(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare sid uuid; st public.club_students%rowtype; cl public.clubs%rowtype; t date;
begin
  sid := public._club_session(p_token);
  if sid is null then return jsonb_build_object('ok', false, 'reason', 'session'); end if;
  select * into st from public.club_students where id = sid;
  select * into cl from public.clubs where id = st.club_id;
  if not st.is_active then return jsonb_build_object('ok', false, 'reason', 'student_inactive'); end if;
  t := public._club_today(cl.timezone);
  return jsonb_build_object(
    'ok', true,
    'today', t,
    'club', jsonb_build_object('name', cl.name, 'sport', cl.sport, 'logo_url', cl.logo_url,
             'whatsapp', cl.whatsapp, 'phone', cl.phone, 'currency_symbol', cl.currency_symbol,
             'primary_color', cl.primary_color, 'accent_color', cl.accent_color, 'card_note', cl.card_note),
    'student', jsonb_build_object('id', st.id, 'code', st.code, 'full_name', st.full_name,
             'photo_url', st.photo_url, 'birth_date', st.birth_date, 'gender', st.gender,
             'phone', st.phone, 'parent_name', st.parent_name, 'parent_phone', st.parent_phone,
             'joined_at', st.joined_at, 'paid_until', st.paid_until, 'username', st.username,
             'card_token', st.card_token, 'level_since', st.level_since,
             'fee', public._club_fee(st)),
    'body', jsonb_build_object('weight_kg', st.weight_kg, 'height_cm', st.height_cm,
             'body_status', st.body_status, 'injuries', to_jsonb(st.injuries), 'injury_notes', st.injury_notes),
    'body_log', coalesce((select jsonb_agg(jsonb_build_object('on', b.measured_on, 'weight_kg', b.weight_kg,
                           'height_cm', b.height_cm, 'body_status', b.body_status) order by b.measured_on desc)
                          from (select * from public.club_body_log where student_id = st.id
                                order by measured_on desc limit 24) b), '[]'::jsonb),
    'status', public._club_status(st.paid_until, public._club_fee(st), t, cl.expiring_days, cl.grace_days),
    'level', (select jsonb_build_object('name', l.name, 'color', l.color, 'sort', l.sort)
              from public.club_levels l where l.id = st.level_id),
    'levels_count', (select count(*) from public.club_levels where club_id = cl.id),
    'group', (select jsonb_build_object('name', g.name, 'schedule', g.schedule, 'coach', g.coach)
              from public.club_groups g where g.id = st.group_id),
    'achievements', coalesce((select jsonb_agg(to_jsonb(a) - 'club_id' - 'student_id'
                               order by a.event_date desc nulls last, a.created_at desc)
                              from public.club_achievements a where a.student_id = st.id), '[]'::jsonb),
    'level_history', coalesce((select jsonb_agg(jsonb_build_object('name', h.level_name,
                                'color', h.level_color, 'at', h.changed_at) order by h.changed_at desc)
                               from public.club_level_history h where h.student_id = st.id), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(jsonb_build_object('amount', p.amount, 'months', p.months,
                           'from', p.period_from, 'to', p.period_to, 'method', p.method, 'at', p.created_at)
                           order by p.created_at desc)
                          from (select * from public.club_payments where student_id = st.id
                                order by created_at desc limit 60) p), '[]'::jsonb),
    'attendance', jsonb_build_object(
        'month', (select count(distinct (at at time zone cl.timezone)::date) from public.club_attendance
                  where student_id = st.id and allowed
                    and (at at time zone cl.timezone)::date >= date_trunc('month', t)::date),
        'total', (select count(distinct (at at time zone cl.timezone)::date) from public.club_attendance
                  where student_id = st.id and allowed),
        'recent', coalesce((select jsonb_agg(x.at order by x.at desc) from
                   (select at from public.club_attendance where student_id = st.id and allowed
                    order by at desc limit 20) x), '[]'::jsonb))
  );
end $$;

-- ============================================================
--  9) شاشة الباب
-- ============================================================
create or replace function public._club_door(p_slug text, p_key text)
returns public.club_doors language plpgsql security definer set search_path = public, extensions as $$
declare d public.club_doors%rowtype;
begin
  select d2.* into d from public.club_doors d2 join public.clubs c on c.id = d2.club_id
   where c.slug = lower(trim(coalesce(p_slug,'')))
     and d2.key_hash = encode(digest(coalesce(p_key,''),'sha256'),'hex')
     and not d2.revoked;
  return d;
end $$;
revoke all on function public._club_door(text, text) from public, anon, authenticated;

create or replace function public.club_door_roster(p_slug text, p_key text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare d public.club_doors%rowtype; cl public.clubs%rowtype; lic jsonb;
begin
  d := public._club_door(p_slug, p_key);
  if d.id is null then return jsonb_build_object('ok', false, 'reason', 'bad_key'); end if;
  update public.club_doors set last_seen_at = now() where id = d.id;
  select * into cl from public.clubs where id = d.club_id;
  lic := public.club_license(cl.id);
  return jsonb_build_object(
    'ok', true,
    'licensed', cl.is_active and (lic->>'ok')::boolean,
    'door', jsonb_build_object('id', d.id, 'name', d.name),
    'club', jsonb_build_object('name', cl.name, 'logo_url', cl.logo_url, 'whatsapp', cl.whatsapp,
             'primary_color', cl.primary_color, 'accent_color', cl.accent_color,
             'default_lang', cl.default_lang, 'currency_symbol', cl.currency_symbol,
             'open_url', cl.door_open_url, 'open_method', cl.door_open_method,
             'open_body', cl.door_open_body, 'threshold', cl.door_threshold,
             'qr', cl.door_qr_enabled, 'face', cl.door_face_enabled),
    'students', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.full_name,
                            'face', s.face))
                          from public.club_students s
                          where s.club_id = cl.id and s.is_active
                            and jsonb_typeof(s.face) = 'array' and jsonb_array_length(s.face) > 0), '[]'::jsonb),
    'version', (select max(greatest(coalesce(face_updated_at, created_at), created_at))
                from public.club_students where club_id = cl.id)
  );
end $$;

-- التحقق عند الباب: p_student (من الوجه) أو p_card (من QR)
create or replace function public.club_door_check(p_slug text, p_key text, p_student uuid,
                                                  p_card text default null, p_method text default 'face')
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare d public.club_doors%rowtype; cl public.clubs%rowtype; st public.club_students%rowtype;
        s jsonb; ok boolean; lv jsonb; recent boolean;
begin
  d := public._club_door(p_slug, p_key);
  if d.id is null then return jsonb_build_object('ok', false, 'reason', 'bad_key'); end if;
  select * into cl from public.clubs where id = d.club_id;
  if not cl.is_active or not (public.club_license(cl.id)->>'ok')::boolean then
    return jsonb_build_object('ok', false, 'reason', 'club_inactive');
  end if;

  if p_card is not null and p_card <> '' then
    select * into st from public.club_students
     where club_id = cl.id and card_token = lower(trim(p_card));
  else
    select * into st from public.club_students where club_id = cl.id and id = p_student;
  end if;
  if not found then return jsonb_build_object('ok', false, 'reason', 'unknown'); end if;

  s := public._club_status(st.paid_until, public._club_fee(st), public._club_today(cl.timezone),
                           cl.expiring_days, cl.grace_days);
  ok := st.is_active and (s->>'door_ok')::boolean;

  select jsonb_build_object('name', l.name, 'color', l.color) into lv
  from public.club_levels l where l.id = st.level_id;

  -- ما منكرّر سجل الحضور إذا نفس التلميذ مرق خلال آخر 3 دقائق
  select exists (select 1 from public.club_attendance
                 where student_id = st.id and allowed = ok and at > now() - interval '3 minutes')
    into recent;
  if not recent then
    insert into public.club_attendance (club_id, student_id, method, allowed, reason, door_name)
    values (cl.id, st.id, case when p_method in ('face','qr') then p_method else 'face' end,
            ok, case when not st.is_active then 'inactive' else s->>'state' end, d.name);
  end if;
  update public.club_doors set last_seen_at = now() where id = d.id;

  return jsonb_build_object(
    'ok', true, 'allowed', ok,
    'reason', case when not st.is_active then 'inactive' else s->>'state' end,
    'student', jsonb_build_object('id', st.id, 'name', st.full_name, 'photo_url', st.photo_url,
                                  'code', st.code, 'paid_until', st.paid_until),
    'level', lv,
    'currency_symbol', cl.currency_symbol) || jsonb_build_object('status', s);
end $$;

-- ============================================================
--  10) مخزن الصور: club  (عام للقراءة بالرابط، الكتابة لصاحب النادي فقط)
--      المسار: club-<club_id>/...
-- ============================================================
do $$ begin
  insert into storage.buckets (id, name, public) values ('club','club', true)
  on conflict (id) do nothing;
exception when others then raise notice 'bucket skipped: %', sqlerrm;
end $$;

create or replace function public.club_path_owned(p_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select case when split_part(coalesce(p_name,''),'/',1) ~ '^club-[0-9a-f-]{36}$'
              then public.club_owned(substring(split_part(p_name,'/',1) from 6)::uuid)
              else false end;
$$;

do $$ begin
  execute 'drop policy if exists "club media insert" on storage.objects';
  execute 'create policy "club media insert" on storage.objects for insert to authenticated
           with check (bucket_id = ''club'' and public.club_path_owned(name))';
  execute 'drop policy if exists "club media select" on storage.objects';
  execute 'create policy "club media select" on storage.objects for select to authenticated
           using (bucket_id = ''club'' and public.club_path_owned(name))';
  execute 'drop policy if exists "club media update" on storage.objects';
  execute 'create policy "club media update" on storage.objects for update to authenticated
           using (bucket_id = ''club'' and public.club_path_owned(name))
           with check (bucket_id = ''club'' and public.club_path_owned(name))';
  execute 'drop policy if exists "club media delete" on storage.objects';
  execute 'create policy "club media delete" on storage.objects for delete to authenticated
           using (bucket_id = ''club'' and public.club_path_owned(name))';
exception when others then raise notice 'storage policies skipped: %', sqlerrm;
end $$;

-- ============================================================
--  11) صلاحيات تنفيذ الدوال
-- ============================================================
grant execute on function public.club_public(text)                         to anon, authenticated;
grant execute on function public.club_student_login(text, text, text)      to anon, authenticated;
grant execute on function public.club_student_logout(text)                 to anon, authenticated;
grant execute on function public.club_student_password(text, text, text)   to anon, authenticated;
grant execute on function public.club_student_me(text)                     to anon, authenticated;
grant execute on function public.club_door_roster(text, text)              to anon, authenticated;
grant execute on function public.club_door_check(text, text, uuid, text, text) to anon, authenticated;

revoke all on function public.admin_new_club(uuid, text, text, integer, numeric) from anon;
revoke all on function public.ensure_club(text)                     from anon;
revoke all on function public.start_club_trial(text, text)          from anon;
revoke all on function public.admin_club_product(numeric, numeric, integer, boolean) from anon;
revoke all on function public.club_add_payment(uuid, integer, numeric, text, text, text) from anon;
revoke all on function public.club_delete_payment(uuid)             from anon;
revoke all on function public.club_set_login(uuid, text, text)      from anon;
revoke all on function public.club_login_status(uuid)               from anon;
revoke all on function public.club_new_card_token(uuid)             from anon;
revoke all on function public.club_new_door(uuid, text)             from anon;
revoke all on function public.club_revoke_door(uuid)                from anon;
revoke all on function public.club_manual_checkin(uuid)             from anon;
revoke all on function public.club_dashboard(uuid)                  from anon;

-- تحقق سريع
select 'club product' as item, exists (select 1 from public.products where code = 'club') as ok
union all select 'clubs table', to_regclass('public.clubs') is not null
union all select 'students table', to_regclass('public.club_students') is not null
union all select 'club plan', exists (select 1 from public.plans where product_code = 'club')
union all select 'body fields', exists (select 1 from information_schema.columns
                                       where table_name = 'club_students' and column_name = 'injuries')
union all select 'portal link ok', pg_get_functiondef('public.my_client_id()'::regprocedure) like '%portal_users%'
union all select 'door function', to_regprocedure('public.club_door_check(text,text,uuid,text,text)') is not null;
