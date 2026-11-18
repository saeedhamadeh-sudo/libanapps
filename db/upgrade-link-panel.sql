-- ============================================================
--  LibanApps — «وصلة»: دخول لوحة التحكم باسم مستخدم وكلمة مرور
--  الرابط: libanapps.com/l/<slug>/admin   (أو دومين الزبون/admin)
--  الافتراضي: المستخدم admin — كلمة المرور 0000 (يغيّرها الزبون من داخل وصلة)
--
--  كيف بيشتغل:
--   • link_panel: اسم المستخدم + كلمة المرور مشفّرة (bcrypt) لكل صفحة — ما حدا بيقرأها إلا مفتاح الخدمة
--   • الـWorker (/api/link/login) بيتحقق، وبيعطي جلسة لحساب داخلي خاص بهالصفحة بس
--     (link-<page_id>@panel.libanapps.com) — هالحساب ما بيشوف غير صفحته (link_owned)،
--     وما إلو أي وصول لحساب الزبون على LibanApps ولا لباقي برامجه.
--   • 10 محاولات غلط ← قفل 15 دقيقة.
--  آمن للتشغيل أكثر من مرة. شرط مسبق: upgrade-link.sql
-- ============================================================

create extension if not exists "pgcrypto";

create table if not exists public.link_panel (
  page_id      uuid primary key references public.link_pages(id) on delete cascade,
  username     text not null default 'admin',
  pass_hash    text not null,
  is_default   boolean not null default true,
  uid          uuid,                         -- الحساب الداخلي للوحة (auth.users)
  fails        integer not null default 0,
  locked_until timestamptz,
  updated_at   timestamptz not null default now()
);
alter table public.link_panel enable row level security;
revoke all on public.link_panel from anon, authenticated;
create index if not exists link_panel_uid_idx on public.link_panel (uid);

-- كل صفحة جديدة بتاخد admin / 0000 تلقائيًا
create or replace function public.link_pages_panel_init()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into public.link_panel (page_id, pass_hash) values (new.id, crypt('0000', gen_salt('bf')))
  on conflict (page_id) do nothing;
  return new;
end $$;
drop trigger if exists link_pages_panel_init on public.link_pages;
create trigger link_pages_panel_init after insert on public.link_pages
  for each row execute function public.link_pages_panel_init();

-- الصفحات الموجودة
insert into public.link_panel (page_id, pass_hash)
select p.id, crypt('0000', gen_salt('bf')) from public.link_pages p
on conflict (page_id) do nothing;

-- صاحب الصفحة = مدير المنصة، أو حساب لوحة الصفحة، أو صاحب الاشتراك
create or replace function public.link_owned(pid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin()
      or (auth.uid() is not null and exists (
            select 1 from public.link_panel lp where lp.page_id = pid and lp.uid = auth.uid()))
      or (not public.is_portal_user() and exists (
            select 1 from public.link_pages p
            where p.id = pid and p.client_id = public.my_client_id()));
$$;

-- حساب اللوحة بيقدر يعدّل صفحته (القفل على slug/client_id بيضل بالـtrigger)
drop policy if exists own_link_pages on public.link_pages;
create policy own_link_pages on public.link_pages for all to authenticated
  using (public.link_owned(id))
  with check (public.is_admin() or public.link_owned(id)
              or (not public.is_portal_user() and public.owns(client_id)));

-- ===== تسجيل الدخول (الـWorker فقط) =====
create or replace function public.link_panel_login(p_slug text, p_user text, p_pass text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare pg public.link_pages%rowtype; lp public.link_panel%rowtype;
begin
  select * into pg from public.link_pages where slug = lower(trim(coalesce(p_slug,'')));
  if not found then return jsonb_build_object('ok', false, 'reason', 'bad'); end if;
  select * into lp from public.link_panel where page_id = pg.id for update;
  if not found then
    insert into public.link_panel (page_id, pass_hash) values (pg.id, crypt('0000', gen_salt('bf')))
    returning * into lp;
  end if;
  if lp.locked_until is not null and lp.locked_until > now() then
    return jsonb_build_object('ok', false, 'reason', 'locked',
      'minutes', ceil(extract(epoch from (lp.locked_until - now())) / 60)::int);
  end if;
  if lower(trim(coalesce(p_user,''))) <> lower(lp.username)
     or lp.pass_hash <> crypt(coalesce(p_pass,''), lp.pass_hash) then
    update public.link_panel
       set fails = case when lp.fails + 1 >= 10 then 0 else lp.fails + 1 end,
           locked_until = case when lp.fails + 1 >= 10 then now() + interval '15 minutes' else null end
     where page_id = pg.id;
    return jsonb_build_object('ok', false, 'reason', 'bad', 'left', greatest(0, 9 - lp.fails));
  end if;
  update public.link_panel set fails = 0, locked_until = null where page_id = pg.id;
  return jsonb_build_object('ok', true, 'page_id', pg.id, 'uid', lp.uid, 'slug', pg.slug);
end $$;
revoke all on function public.link_panel_login(text, text, text) from public, anon, authenticated;
grant execute on function public.link_panel_login(text, text, text) to service_role;

create or replace function public.link_panel_set_uid(p_page uuid, p_uid uuid)
returns void language sql security definer set search_path = public as $$
  update public.link_panel set uid = p_uid where page_id = p_page;
$$;
revoke all on function public.link_panel_set_uid(uuid, uuid) from public, anon, authenticated;
grant execute on function public.link_panel_set_uid(uuid, uuid) to service_role;

-- ===== معلومات الدخول (لصفحة الحساب ولوحة وصلة) =====
create or replace function public.link_panel_info(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pg public.link_pages%rowtype; lp public.link_panel%rowtype;
begin
  select * into pg from public.link_pages where slug = lower(trim(coalesce(p_slug,'')));
  if not found or not public.link_owned(pg.id) then return null; end if;
  select * into lp from public.link_panel where page_id = pg.id;
  return jsonb_build_object('username', coalesce(lp.username, 'admin'),
                            'is_default', coalesce(lp.is_default, true),
                            'is_panel', (auth.uid() is not null and lp.uid = auth.uid()));
end $$;
revoke all on function public.link_panel_info(text) from anon;

-- ===== تغيير كلمة المرور =====
--  حساب اللوحة: لازم كلمة المرور الحالية. صاحب الاشتراك أو مدير المنصة: ما في داعي.
create or replace function public.link_panel_password(p_page uuid, p_current text, p_new text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare lp public.link_panel%rowtype; is_panel boolean;
begin
  if not public.link_owned(p_page) then raise exception 'not allowed'; end if;
  if char_length(coalesce(p_new,'')) < 4 then
    return jsonb_build_object('ok', false, 'reason', 'short');
  end if;
  select * into lp from public.link_panel where page_id = p_page for update;
  if not found then
    insert into public.link_panel (page_id, pass_hash) values (p_page, crypt('0000', gen_salt('bf')))
    returning * into lp;
  end if;
  is_panel := (auth.uid() is not null and lp.uid = auth.uid());
  if is_panel and lp.pass_hash <> crypt(coalesce(p_current,''), lp.pass_hash) then
    return jsonb_build_object('ok', false, 'reason', 'current');
  end if;
  update public.link_panel
     set pass_hash = crypt(p_new, gen_salt('bf')), is_default = (p_new = '0000'),
         fails = 0, locked_until = null, updated_at = now()
   where page_id = p_page;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.link_panel_password(uuid, text, text) from anon;

select 'link_panel' as item, to_regclass('public.link_panel') is not null as ok,
       (select count(*) from public.link_panel) as pages;
