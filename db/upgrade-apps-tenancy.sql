-- ============================================================
--  أساس تعدد المستأجرين لبرامج المحاسبة
--  كل زبون بيشوف بياناته هو فقط، بمشروع Supabase واحد
--  شغّله قبل نقل أي جدول من برنامج الألمنيوم
--  آمن للتشغيل أكثر من مرة
-- ============================================================

-- ---------- 1) مين الزبون الحالي؟ ----------
--  بترجع client_id تبع المستخدم المسجّل — أساس كل سياسات الحماية
create or replace function public.my_client_id()
returns uuid language sql stable security definer set search_path = public as $$
  select c.id from public.clients c where c.user_id = auth.uid() limit 1;
$$;

-- ---------- 2) هل هذا الزبون إلي؟ ----------
create or replace function public.owns(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or (cid is not null and cid = public.my_client_id());
$$;

-- ---------- 3) هل اشتراك هذا البرنامج ساري؟ ----------
--  بتستعملها الواجهة لتقرر تفتح البرنامج أو تعرض شاشة التجديد
create or replace function public.app_access(p_product text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cid uuid; s public.subscriptions%rowtype;
begin
  cid := public.my_client_id();
  if cid is null then
    return jsonb_build_object('ok', false, 'reason', 'no_client');
  end if;

  select * into s from public.subscriptions
   where client_id = cid and product_code = p_product
   order by expires_at desc limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_subscription', 'client_id', cid);
  end if;

  return jsonb_build_object(
    'ok',        (s.status = 'active' and s.expires_at > now()),
    'reason',    case when s.status <> 'active' then 'suspended'
                      when s.expires_at <= now() then 'expired' else 'active' end,
    'client_id', cid,
    'plan',      s.plan,
    'trial',     (s.plan = 'trial'),
    'expires_at', s.expires_at,
    'days_left', greatest(0, ceil(extract(epoch from (s.expires_at - now()))/86400))::int,
    'subscription_id', s.id
  );
end $$;

-- ---------- 4) إعدادات كل زبون داخل البرنامج ----------
--  اسم المؤسسة، اللوغو، العملة، سعر الصرف… لكل برنامج على حدة
create table if not exists public.app_settings (
  client_id     uuid not null references public.clients(id) on delete cascade,
  product_code  text not null references public.products(code),
  biz_name      text default '',
  logo_url      text default '',
  phone         text default '',
  address       text default '',
  currency      text not null default 'USD',
  exchange_rate numeric(12,2) not null default 89500,
  extra         jsonb not null default '{}'::jsonb,
  updated_at    timestamptz not null default now(),
  primary key (client_id, product_code)
);

alter table public.app_settings enable row level security;

drop policy if exists own_app_settings on public.app_settings;
create policy own_app_settings on public.app_settings for all to authenticated
  using (public.owns(client_id)) with check (public.owns(client_id));

-- ============================================================
--  قالب: هيك بينتقل أي جدول من برنامج الألمنيوم
--  (مثال توضيحي — الجداول الفعلية بتنضاف بعد مراجعة سكيما البرنامج)
-- ============================================================
--
--  alter table public.<الجدول>
--    add column if not exists client_id uuid
--    references public.clients(id) on delete cascade;
--
--  create index if not exists <الجدول>_client_idx
--    on public.<الجدول> (client_id);
--
--  alter table public.<الجدول> enable row level security;
--
--  drop policy if exists own_<الجدول> on public.<الجدول>;
--  create policy own_<الجدول> on public.<الجدول> for all to authenticated
--    using (public.owns(client_id)) with check (public.owns(client_id));
--
--  -- وللبيانات الموجودة قبل النقل:
--  update public.<الجدول> set client_id = '<uuid الزبون>' where client_id is null;
--  alter table public.<الجدول> alter column client_id set not null;
--
-- ============================================================

-- تحقّق سريع بعد التشغيل
select 'my_client_id' as fn, public.my_client_id() is not null as ready
union all
select 'app_access(alum)', (public.app_access('alum') ->> 'ok') is not null;
