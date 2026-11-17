-- ============================================================
--  LibanApps — برنامج «وصلة» (Wasla) — صفحة روابط لكل زبون   code = link
--  مثل Linktree: صفحة واحدة فيها صورة، نبذة، أيقونات التواصل،
--  وأزرار روابط (واتساب، اتصال، موقع، يوتيوب، أي رابط...)
--
--  الرابط العام للزبون:   libanapps.com/l/<slug>
--  لوحة التحكم:            libanapps.com/portal-link/<slug>/admin
--
--  بيضيف:
--   • منتج جديد link (بادئة المفتاح LINK) + باقة سنوية + تجربة 7 أيام
--   • جداول: link_pages (الصفحة)، link_items (الأزرار)، link_daily (الإحصاءات اليومية)
--   • دوال: التجربة، الإصدار اليدوي من /super، الصفحة العامة، الإحصاءات، التتبّع
--   • مخزن صور جديد: link   (المسار: link-<page_id>/...)
--
--  آمن للتشغيل أكثر من مرة — ما بيحذف ولا بيغيّر بيانات موجودة.
--  شرط مسبق: schema.sql + upgrade-website.sql + upgrade-apps-tenancy.sql
--            + security-fixes-1.sql (فيها is_portal_user)
-- ============================================================

create extension if not exists "pgcrypto";

-- ============================================================
--  1) المنتج والباقة
-- ============================================================
insert into public.products (code, name_ar, name_en, prefix) values
  ('link', 'وصلة — صفحة روابط', 'LibanApps Wasla', 'LINK')
on conflict (code) do nothing;

alter table public.products add column if not exists trial_days integer;
update public.products set trial_days = 7 where code = 'link' and trial_days is null;

alter table public.plans add column if not exists renew_price_usd numeric(10,2);

-- الباقة: 25$ سنويًا (السعر والتجديد ومدة التجربة بتتغيّر من /super)
insert into public.plans (product_code, name_ar, name_en, days, price_usd, renew_price_usd, badge_ar, features_ar, features_en, sort)
select 'link', 'وصلة — سنة', 'Wasla — 1 year', 365, 25, 25, 'جديد',
  array['صفحة روابط باسمك: libanapps.com/l/اسمك',
        'روابط غير محدودة: واتساب، اتصال، موقع، يوتيوب، أي رابط',
        'أيقونات حسابات التواصل الاجتماعي',
        'قوالب وألوان وخطوط قابلة للتعديل',
        'إحصاءات الزيارات والنقرات والدول',
        'رمز QR جاهز للطباعة',
        'زر «حفظ جهة الاتصال» على الهاتف'],
  array['Your own links page: libanapps.com/l/yourname',
        'Unlimited links: WhatsApp, call, location, YouTube, any URL',
        'Social media icons',
        'Editable themes, colors and fonts',
        'Visits, clicks and countries analytics',
        'Print-ready QR code',
        '“Save contact” button on phones'], 7
where not exists (select 1 from public.plans where product_code = 'link');

-- إعدادات «وصلة» من لوحة /super
create or replace function public.admin_link_product(
  p_price numeric, p_renew numeric, p_trial integer, p_active boolean default true
) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update public.products set trial_days = greatest(0, least(60, coalesce(p_trial, 7))) where code = 'link';
  update public.plans set price_usd = greatest(0, coalesce(p_price, price_usd)),
                          renew_price_usd = greatest(0, coalesce(p_renew, renew_price_usd)),
                          is_active = coalesce(p_active, is_active)
   where product_code = 'link';
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  2) الجداول
-- ============================================================
create table if not exists public.link_pages (
  id              uuid primary key default gen_random_uuid(),
  client_id       uuid not null references public.clients(id) on delete cascade,
  slug            text unique not null,
  title           text not null default '',
  bio             text not null default '',
  avatar_url      text not null default '',
  avatar_shape    text not null default 'circle',
  theme           text not null default 'classic',
  bg_type         text not null default 'solid',
  bg_color        text not null default '#f4f4f5',
  bg_color2       text not null default '#e4e4e7',
  bg_image_url    text not null default '',
  text_color      text not null default '#18181b',
  btn_style       text not null default 'fill',
  btn_shape       text not null default 'rounded',
  btn_color       text not null default '#18181b',
  btn_text_color  text not null default '#ffffff',
  font            text not null default 'Tajawal',
  socials         jsonb not null default '[]'::jsonb,   -- [{"k":"instagram","u":"https://..."}]
  socials_pos     text not null default 'top',
  default_lang    text not null default 'ar',
  seo_title       text not null default '',
  seo_desc        text not null default '',
  og_image        text not null default '',
  show_share      boolean not null default true,
  show_vcard      boolean not null default false,       -- زر «حفظ جهة الاتصال»
  contact_name    text not null default '',
  contact_phone   text not null default '',
  contact_email   text not null default '',
  contact_org     text not null default '',
  hide_brand      boolean not null default false,       -- إخفاء «صُنع بواسطة LibanApps» — من /super فقط
  is_active       boolean not null default true,
  views           bigint not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists link_pages_client_idx on public.link_pages (client_id);

do $$ begin
  alter table public.link_pages add constraint link_pages_slug_format check (slug ~ '^[a-z0-9][a-z0-9-]{1,30}$');
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.link_pages add constraint link_pages_enums check (
        avatar_shape in ('circle','rounded','square','none')
    and bg_type      in ('solid','gradient','image')
    and btn_style    in ('fill','outline','soft','shadow','glass')
    and btn_shape    in ('square','rounded','pill')
    and socials_pos  in ('top','bottom')
    and default_lang in ('ar','en','fr')
    and jsonb_typeof(socials) = 'array'
    and char_length(title) <= 80 and char_length(bio) <= 300);
exception when duplicate_object then null; end $$;

create table if not exists public.link_items (
  id          uuid primary key default gen_random_uuid(),
  page_id     uuid not null references public.link_pages(id) on delete cascade,
  kind        text not null default 'link',
  title       text not null default '',
  url         text not null default '',
  note        text not null default '',        -- وصف صغير / نص رسالة واتساب / نص الفقرة
  thumb_url   text not null default '',
  icon        text not null default '',        -- مفتاح أيقونة جاهزة أو إيموجي
  highlight   text not null default '',        -- '' | pulse | shake | glow
  starts_at   timestamptz,                     -- جدولة: يظهر من تاريخ
  ends_at     timestamptz,                     -- جدولة: يختفي بعد تاريخ
  is_active   boolean not null default true,
  sort        integer not null default 0,
  clicks      bigint not null default 0,
  created_at  timestamptz not null default now()
);
create index if not exists link_items_page_idx on public.link_items (page_id, sort);

do $$ begin
  alter table public.link_items add constraint link_items_enums check (
        kind in ('link','header','whatsapp','phone','email','location','youtube','text')
    and highlight in ('','pulse','shake','glow')
    and char_length(title) <= 120 and char_length(note) <= 600 and char_length(url) <= 2000
    -- لا روابط سكربت أبداً
    and url !~* '^\s*(javascript|data|vbscript|file):');
exception when duplicate_object then null; end $$;

-- إحصاءات مجمّعة باليوم (بدل سطر لكل زيارة — حجم صغير ثابت)
--   metric: view | click (ref = item_id) | country (ref = DE) | device (ref = m/d/t) | src (ref = instagram.com)
create table if not exists public.link_daily (
  page_id  uuid not null references public.link_pages(id) on delete cascade,
  day      date not null,
  metric   text not null,
  ref      text not null default '',
  n        integer not null default 0,
  primary key (page_id, day, metric, ref)
);

-- ============================================================
--  3) قفل الحقول + حدود
-- ============================================================
create or replace function public.link_pages_lock_fields()
returns trigger language plpgsql as $$
begin
  if current_setting('link.track', true) = '1' then
    return new;                                   -- عدّاد الزيارات فقط
  end if;
  if not public.is_admin() then
    if new.slug <> old.slug then raise exception 'slug is locked'; end if;
    if new.client_id <> old.client_id then raise exception 'owner is locked'; end if;
    new.hide_brand := old.hide_brand;
    new.views := old.views;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists link_pages_lock on public.link_pages;
create trigger link_pages_lock before update on public.link_pages
  for each row execute function public.link_pages_lock_fields();

create or replace function public.link_items_guard()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    if (select count(*) from public.link_items where page_id = new.page_id) >= 150 then
      raise exception 'items limit reached (150)';
    end if;
    new.clicks := 0;
  elsif current_setting('link.track', true) is distinct from '1' then
    if new.page_id <> old.page_id then raise exception 'page is locked'; end if;
    if not public.is_admin() then new.clicks := old.clicks; end if;
  end if;
  return new;
end $$;
drop trigger if exists link_items_guard on public.link_items;
create trigger link_items_guard before insert or update on public.link_items
  for each row execute function public.link_items_guard();

-- ============================================================
--  4) الصلاحيات (RLS)
-- ============================================================
create or replace function public.link_owned(pid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or (not public.is_portal_user() and exists (
    select 1 from public.link_pages p
    where p.id = pid and p.client_id = public.my_client_id()));
$$;

alter table public.link_pages enable row level security;
alter table public.link_items enable row level security;
alter table public.link_daily enable row level security;

drop policy if exists own_link_pages on public.link_pages;
create policy own_link_pages on public.link_pages for all to authenticated
  using (public.link_owned(id))
  with check (public.is_admin() or (not public.is_portal_user() and public.owns(client_id)));

drop policy if exists own_link_items on public.link_items;
create policy own_link_items on public.link_items for all to authenticated
  using (public.link_owned(page_id)) with check (public.link_owned(page_id));

drop policy if exists own_link_daily on public.link_daily;
create policy own_link_daily on public.link_daily for select to authenticated
  using (public.link_owned(page_id));

-- ============================================================
--  5) الترخيص والإنشاء
-- ============================================================
create or replace function public.link_license(pid uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pg public.link_pages%rowtype; s public.subscriptions%rowtype;
begin
  select * into pg from public.link_pages where id = pid;
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  select * into s from public.subscriptions
   where client_id = pg.client_id and product_code = 'link' and ref_slug = pg.slug
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

-- كلمات محجوزة ما بتنفع كرابط صفحة
create or replace function public.link_slug_available(p_slug text)
returns boolean language sql stable security definer set search_path = public as $$
  select lower(trim(coalesce(p_slug,''))) ~ '^[a-z0-9][a-z0-9-]{1,30}$'
     and lower(trim(p_slug)) not in ('admin','api','login','signup','account','super','libanapps','support','help','www','img','assets')
     and not exists (select 1 from public.link_pages where slug = lower(trim(p_slug)))
     and not exists (select 1 from public.subscriptions
                     where product_code = 'link' and ref_slug = lower(trim(p_slug)));
$$;

create or replace function public._make_link_page(p_client uuid, p_slug text, p_name text)
returns public.link_pages language plpgsql security definer set search_path = public as $$
declare c public.clients%rowtype; pg public.link_pages; ph text;
begin
  select * into c from public.clients where id = p_client;
  ph := regexp_replace(coalesce(c.phone,''),'\D','','g');
  insert into public.link_pages (client_id, slug, title, contact_name, contact_phone)
  values (p_client, p_slug, left(coalesce(nullif(trim(p_name),''), p_slug), 80),
          left(coalesce(nullif(trim(p_name),''), p_slug), 80), coalesce(c.phone,''))
  returning * into pg;
  -- زر واتساب جاهز من رقم الزبون (بيقدر يعدّله أو يحذفه)
  if length(ph) >= 7 then
    insert into public.link_items (page_id, kind, title, url, sort)
    values (pg.id, 'whatsapp', 'راسلنا على واتساب', ph, 1);
  end if;
  return pg;
end $$;
revoke all on function public._make_link_page(uuid, text, text) from public, anon, authenticated;

create or replace function public.admin_new_link(
  p_client uuid, p_slug text, p_biz text, p_days integer, p_price numeric default 0
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_slug text; pg public.link_pages; s public.subscriptions;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  v_slug := lower(trim(coalesce(p_slug,'')));
  if v_slug !~ '^[a-z0-9][a-z0-9-]{1,30}$' then raise exception 'invalid slug'; end if;
  if not public.link_slug_available(v_slug) then raise exception 'slug taken'; end if;
  pg := public._make_link_page(p_client, v_slug, p_biz);
  insert into public.subscriptions (client_id, product_code, key, plan, expires_at,
                                    price_usd, ref_slug, notes)
  values (p_client, 'link', public.gen_license_key('link'),
          case when p_days <= 7 then 'trial' when p_days <= 31 then 'monthly' else 'yearly' end,
          now() + make_interval(days => greatest(1, p_days)),
          coalesce(p_price,0), v_slug, 'إصدار يدوي')
  returning * into s;
  return jsonb_build_object('ok', true, 'key', s.key, 'expires_at', s.expires_at, 'slug', v_slug);
end $$;

-- تجربة مجانية (7 أيام افتراضيًا — تتغيّر من /super)
create or replace function public.start_link_trial(p_slug text, p_biz text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare cid uuid; v_slug text; d integer; s public.subscriptions; pg public.link_pages;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select id into cid from public.clients where user_id = auth.uid();
  if cid is null then raise exception 'complete your profile first'; end if;
  if exists (select 1 from public.subscriptions where client_id = cid and product_code = 'link') then
    return jsonb_build_object('ok', false, 'reason', 'لديك اشتراك أو تجربة سابقة لهذا البرنامج');
  end if;
  v_slug := lower(trim(coalesce(p_slug,'')));
  if v_slug !~ '^[a-z0-9][a-z0-9-]{1,30}$' then
    return jsonb_build_object('ok', false, 'reason', 'يجب أن يكون الرابط بأحرف إنكليزية وأرقام وشَرطة، بطول بين 2 و31 حرفًا');
  end if;
  if not public.link_slug_available(v_slug) then
    return jsonb_build_object('ok', false, 'reason', 'هذا الرابط محجوز — اختر رابطًا آخر');
  end if;
  select coalesce(trial_days, 7) into d from public.products where code = 'link';
  if coalesce(d,0) <= 0 then
    return jsonb_build_object('ok', false, 'reason', 'التجربة المجانية غير متاحة حاليًا لهذا البرنامج');
  end if;
  pg := public._make_link_page(cid, v_slug, p_biz);
  insert into public.subscriptions (client_id, product_code, key, plan, expires_at, price_usd, ref_slug, notes)
  values (cid, 'link', public.gen_license_key('link'), 'trial',
          now() + make_interval(days => d), 0, v_slug, 'تجربة مجانية')
  returning * into s;
  return jsonb_build_object('ok', true, 'key', s.key, 'expires_at', s.expires_at,
                            'days', d, 'slug', v_slug, 'subscription_id', s.id);
end $$;

-- اشتراك link بدون صفحة (مثلاً بعد الشراء بـWhish) — منبني الصفحة أول ما تنفتح اللوحة
create or replace function public.ensure_link_page(p_slug text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_slug text; pg public.link_pages; cid uuid; s public.subscriptions; biz text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  v_slug := lower(trim(coalesce(p_slug,'')));
  select * into pg from public.link_pages where slug = v_slug;
  if found then
    if not public.link_owned(pg.id) then raise exception 'not allowed'; end if;
    return to_jsonb(pg);
  end if;
  cid := public.my_client_id();
  if cid is null then raise exception 'no client'; end if;
  select * into s from public.subscriptions
   where client_id = cid and product_code = 'link' and ref_slug = v_slug limit 1;
  if not found then raise exception 'no subscription for this page'; end if;
  select biz_name into biz from public.purchases
   where client_id = cid and product_code = 'link' and slug = v_slug order by id desc limit 1;
  select * into pg from public._make_link_page(cid, v_slug, coalesce(biz,''));
  return to_jsonb(pg);
end $$;

-- ============================================================
--  6) الصفحة العامة (بدون تسجيل دخول)
-- ============================================================
create or replace function public.link_public(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pg public.link_pages%rowtype; lic jsonb;
begin
  select * into pg from public.link_pages where slug = lower(trim(coalesce(p_slug,'')));
  if not found then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  lic := public.link_license(pg.id);
  if not pg.is_active or not coalesce((lic->>'ok')::boolean, false) then
    return jsonb_build_object('ok', false,
      'reason', case when not pg.is_active then 'inactive' else lic->>'reason' end,
      'page', jsonb_build_object('title', pg.title, 'slug', pg.slug, 'default_lang', pg.default_lang));
  end if;
  return jsonb_build_object('ok', true,
    'page', jsonb_build_object(
      'id', pg.id, 'slug', pg.slug, 'title', pg.title, 'bio', pg.bio,
      'avatar_url', pg.avatar_url, 'avatar_shape', pg.avatar_shape, 'theme', pg.theme,
      'bg_type', pg.bg_type, 'bg_color', pg.bg_color, 'bg_color2', pg.bg_color2, 'bg_image_url', pg.bg_image_url,
      'text_color', pg.text_color, 'btn_style', pg.btn_style, 'btn_shape', pg.btn_shape,
      'btn_color', pg.btn_color, 'btn_text_color', pg.btn_text_color, 'font', pg.font,
      'socials', pg.socials, 'socials_pos', pg.socials_pos, 'default_lang', pg.default_lang,
      'seo_title', pg.seo_title, 'seo_desc', pg.seo_desc, 'og_image', pg.og_image,
      'show_share', pg.show_share, 'show_vcard', pg.show_vcard,
      'contact_name', pg.contact_name, 'contact_phone', pg.contact_phone,
      'contact_email', pg.contact_email, 'contact_org', pg.contact_org,
      'hide_brand', pg.hide_brand, 'updated_at', pg.updated_at),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', i.id, 'kind', i.kind, 'title', i.title, 'url', i.url, 'note', i.note,
               'thumb_url', i.thumb_url, 'icon', i.icon, 'highlight', i.highlight)
             order by i.sort, i.created_at)
        from public.link_items i
       where i.page_id = pg.id and i.is_active
         and (i.starts_at is null or i.starts_at <= now())
         and (i.ends_at   is null or i.ends_at   >  now())), '[]'::jsonb));
end $$;

-- ============================================================
--  7) التتبّع (الـWorker فقط — بمفتاح الخدمة)
-- ============================================================
create or replace function public._link_bump(p_page uuid, p_day date, p_metric text, p_ref text)
returns void language sql security definer set search_path = public as $$
  insert into public.link_daily (page_id, day, metric, ref, n) values (p_page, p_day, p_metric, coalesce(p_ref,''), 1)
  on conflict (page_id, day, metric, ref) do update set n = public.link_daily.n + 1;
$$;
revoke all on function public._link_bump(uuid, date, text, text) from public, anon, authenticated;

create or replace function public.link_track(
  p_slug text, p_item uuid default null, p_country text default '', p_device text default '', p_src text default ''
) returns jsonb language plpgsql security definer set search_path = public as $$
declare pg public.link_pages%rowtype; d date; src text; cc text;
begin
  select * into pg from public.link_pages where slug = lower(trim(coalesce(p_slug,'')));
  if not found then return jsonb_build_object('ok', false); end if;
  d := (now() at time zone 'Asia/Beirut')::date;
  perform set_config('link.track', '1', true);
  if p_item is null then
    update public.link_pages set views = views + 1 where id = pg.id;
    perform public._link_bump(pg.id, d, 'view', '');
    cc := upper(coalesce(p_country,''));
    if cc ~ '^[A-Z]{2}$' then perform public._link_bump(pg.id, d, 'country', cc); end if;
    if p_device in ('m','d','t') then perform public._link_bump(pg.id, d, 'device', p_device); end if;
    src := split_part(regexp_replace(lower(coalesce(p_src,'')), '^[a-z]+://', ''), '/', 1);
    src := left(regexp_replace(src, '[^a-z0-9.-]', '', 'g'), 60);
    src := regexp_replace(src, '^(www\.|m\.|l\.|lm\.)', '');
    if src <> '' then perform public._link_bump(pg.id, d, 'src', src); end if;
  else
    update public.link_items set clicks = clicks + 1 where id = p_item and page_id = pg.id;
    if not found then return jsonb_build_object('ok', false); end if;
    perform public._link_bump(pg.id, d, 'click', p_item::text);
  end if;
  perform set_config('link.track', '0', true);
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.link_track(text, uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.link_track(text, uuid, text, text, text) to service_role;

-- ============================================================
--  8) تقرير الإحصاءات لصاحب الصفحة
-- ============================================================
create or replace function public.link_report(p_page uuid, p_days integer default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare dd integer; since date; today date;
begin
  if not public.link_owned(p_page) then raise exception 'not allowed'; end if;
  dd := greatest(1, least(365, coalesce(p_days, 30)));
  today := (now() at time zone 'Asia/Beirut')::date;
  since := today - (dd - 1);
  return jsonb_build_object(
    'days', dd,
    'views',  (select coalesce(sum(n),0) from public.link_daily where page_id = p_page and day >= since and metric = 'view'),
    'clicks', (select coalesce(sum(n),0) from public.link_daily where page_id = p_page and day >= since and metric = 'click'),
    'total_views', (select views from public.link_pages where id = p_page),
    'daily', (select coalesce(jsonb_agg(jsonb_build_object('day', g.d, 'views', coalesce(v.n,0), 'clicks', coalesce(c.n,0)) order by g.d), '[]'::jsonb)
                from (select generate_series(since, today, interval '1 day')::date as d) g
                left join (select day, sum(n) n from public.link_daily where page_id = p_page and metric = 'view'  and day >= since group by day) v on v.day = g.d
                left join (select day, sum(n) n from public.link_daily where page_id = p_page and metric = 'click' and day >= since group by day) c on c.day = g.d),
    'items',     (select coalesce(jsonb_agg(jsonb_build_object('id', ref, 'n', s) order by s desc), '[]'::jsonb)
                    from (select ref, sum(n) s from public.link_daily where page_id = p_page and day >= since and metric = 'click' group by ref) x),
    'countries', (select coalesce(jsonb_agg(jsonb_build_object('k', ref, 'n', s) order by s desc), '[]'::jsonb)
                    from (select ref, sum(n) s from public.link_daily where page_id = p_page and day >= since and metric = 'country' group by ref order by 2 desc limit 10) x),
    'devices',   (select coalesce(jsonb_agg(jsonb_build_object('k', ref, 'n', s) order by s desc), '[]'::jsonb)
                    from (select ref, sum(n) s from public.link_daily where page_id = p_page and day >= since and metric = 'device' group by ref) x),
    'sources',   (select coalesce(jsonb_agg(jsonb_build_object('k', ref, 'n', s) order by s desc), '[]'::jsonb)
                    from (select ref, sum(n) s from public.link_daily where page_id = p_page and day >= since and metric = 'src' group by ref order by 2 desc limit 10) x));
end $$;

-- ترتيب الأزرار دفعة واحدة (بعد السحب والإفلات)
create or replace function public.link_reorder(p_page uuid, p_ids uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare i integer;
begin
  if not public.link_owned(p_page) then raise exception 'not allowed'; end if;
  for i in 1 .. coalesce(array_length(p_ids,1),0) loop
    update public.link_items set sort = i where id = p_ids[i] and page_id = p_page;
  end loop;
  return jsonb_build_object('ok', true);
end $$;

-- إخفاء الشعار من /super
create or replace function public.admin_link_brand(p_page uuid, p_hide boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update public.link_pages set hide_brand = coalesce(p_hide,false) where id = p_page;
  return jsonb_build_object('ok', true);
end $$;

-- ============================================================
--  9) مخزن الصور: link  (عام للقراءة بالرابط، الكتابة لصاحب الصفحة فقط)
--      المسار: link-<page_id>/...
-- ============================================================
do $$ begin
  insert into storage.buckets (id, name, public) values ('link','link', true)
  on conflict (id) do nothing;
exception when others then raise notice 'bucket skipped: %', sqlerrm;
end $$;

create or replace function public.link_path_owned(p_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select case when split_part(coalesce(p_name,''),'/',1) ~ '^link-[0-9a-f-]{36}$'
              then public.link_owned(substring(split_part(p_name,'/',1) from 6)::uuid)
              else false end;
$$;

do $$ begin
  execute 'drop policy if exists "link media insert" on storage.objects';
  execute 'create policy "link media insert" on storage.objects for insert to authenticated
           with check (bucket_id = ''link'' and public.link_path_owned(name))';
  execute 'drop policy if exists "link media select" on storage.objects';
  execute 'create policy "link media select" on storage.objects for select to authenticated
           using (bucket_id = ''link'' and public.link_path_owned(name))';
  execute 'drop policy if exists "link media update" on storage.objects';
  execute 'create policy "link media update" on storage.objects for update to authenticated
           using (bucket_id = ''link'' and public.link_path_owned(name))
           with check (bucket_id = ''link'' and public.link_path_owned(name))';
  execute 'drop policy if exists "link media delete" on storage.objects';
  execute 'create policy "link media delete" on storage.objects for delete to authenticated
           using (bucket_id = ''link'' and public.link_path_owned(name))';
exception when others then raise notice 'storage policies skipped: %', sqlerrm;
end $$;

-- ============================================================
--  10) صلاحيات تنفيذ الدوال
-- ============================================================
grant execute on function public.link_public(text)            to anon, authenticated;
grant execute on function public.link_slug_available(text)    to anon, authenticated;

revoke all on function public.admin_new_link(uuid, text, text, integer, numeric) from anon;
revoke all on function public.admin_link_product(numeric, numeric, integer, boolean) from anon;
revoke all on function public.admin_link_brand(uuid, boolean)  from anon;
revoke all on function public.start_link_trial(text, text)     from anon;
revoke all on function public.ensure_link_page(text)           from anon;
revoke all on function public.link_report(uuid, integer)       from anon;
revoke all on function public.link_reorder(uuid, uuid[])       from anon;
revoke all on function public.link_license(uuid)               from anon;

-- تحقق سريع
select 'link product' as item, exists (select 1 from public.products where code = 'link') as ok
union all select 'link plan',    exists (select 1 from public.plans where product_code = 'link')
union all select 'pages table',  to_regclass('public.link_pages') is not null
union all select 'items table',  to_regclass('public.link_items') is not null
union all select 'stats table',  to_regclass('public.link_daily') is not null
union all select 'public fn',    to_regprocedure('public.link_public(text)') is not null
union all select 'track fn',     to_regprocedure('public.link_track(text,uuid,text,text,text)') is not null;
