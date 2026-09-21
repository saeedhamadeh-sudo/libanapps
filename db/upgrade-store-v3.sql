-- ============================================================
--  LibanApps Store — v3
--   • تصنيفات فرعية (parent_id) وأيقونة لكل تصنيف
--   • كل صورة سلايدر ممكن تنقل لتصنيف
--   • بنرات (مربعات) تحت السلايدر، كل واحد لتصنيف
--  شغّله بعد upgrade-store-v2.sql — آمن للتشغيل أكثر من مرة.
-- ============================================================
alter table public.store_categories add column if not exists parent_id uuid references public.store_categories(id) on delete set null;
alter table public.store_categories add column if not exists icon text default '';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'store_cat_parent_chk') then
    alter table public.store_categories add constraint store_cat_parent_chk check (parent_id is null or parent_id <> id);
  end if;
end $$;
create index if not exists store_cat_parent_idx on public.store_categories (store_id, parent_id);

alter table public.store_slides add column if not exists category_id uuid references public.store_categories(id) on delete set null;

create table if not exists public.store_banners (
  id          uuid primary key default gen_random_uuid(),
  store_id    uuid not null references public.stores(id) on delete cascade,
  image_url   text not null,
  title       text default '',
  category_id uuid references public.store_categories(id) on delete set null,
  link_url    text default '',
  sort        integer not null default 0,
  is_active   boolean not null default true
);
create index if not exists store_banners_idx on public.store_banners (store_id, sort);
alter table public.store_banners enable row level security;
drop policy if exists own_store_banners on public.store_banners;
create policy own_store_banners on public.store_banners for all to authenticated
  using (public.store_owned(store_id)) with check (public.store_owned(store_id));

create or replace function public.store_public(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st public.stores%rowtype; lic jsonb; gws jsonb; pop jsonb;
begin
  select * into st from public.stores where slug = lower(trim(coalesce(p_slug,'')));
  if not found then
    if exists (select 1 from public.subscriptions
               where product_code = 'store' and ref_slug = lower(trim(coalesce(p_slug,'')))) then
      return jsonb_build_object('ok', false, 'reason', 'not_ready');
    end if;
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;

  lic := public.store_license(st.id);
  if not st.is_active or not (lic->>'ok')::boolean then
    return jsonb_build_object('ok', false,
      'reason', case when not st.is_active then 'inactive' else coalesce(lic->>'reason','expired') end,
      'store', jsonb_build_object('name', st.name, 'logo_url', st.logo_url, 'logo_height', st.logo_height,
                                   'whatsapp', st.whatsapp, 'theme', st.theme));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('p', g.provider, 'label', coalesce(g.config->>'label',''),
                                               'note', case when g.provider = 'manual' then g.config->>'instructions' else '' end)
                            order by g.provider), '[]'::jsonb)
    into gws
  from public.store_gateways g
  where g.store_id = st.id and g.enabled
    and public._gw_ready(g.provider, g.config) and public._gw_supports(g.provider, st.currency_code);

  select to_jsonb(p) into pop from public.store_popups p
   where p.store_id = st.id and p.is_active
     and (p.starts_at is null or p.starts_at <= now())
     and (p.ends_at   is null or p.ends_at   >= now());

  return jsonb_build_object(
    'ok', true,
    'store', (to_jsonb(st) - 'client_id' - 'order_seq') || jsonb_build_object('gateways', gws),
    'categories', coalesce((select jsonb_agg(to_jsonb(c) order by c.sort, c.name_ar)
                            from public.store_categories c
                            where c.store_id = st.id and c.is_active), '[]'::jsonb),
    'products', coalesce((
        select jsonb_agg((to_jsonb(p) - 'store_id') || jsonb_build_object(
                 'price', public._eff_price(p.price, p.compare_price, p.sale_ends_at), 'compare_price', public._eff_compare(p.price, p.compare_price, p.sale_ends_at),
                 'rating_avg', r.avg, 'rating_count', coalesce(r.n, 0)) order by p.sort, p.created_at)
        from (select * from public.store_products
              where store_id = st.id and is_active order by sort, created_at limit 2000) p
        left join lateral (select round(avg(rating)::numeric,1) as avg, count(*)::int as n
                           from public.store_reviews rv
                           where rv.product_id = p.id and rv.is_approved) r on true), '[]'::jsonb),
    'slides', coalesce((select jsonb_agg(to_jsonb(s) order by s.sort)
                        from public.store_slides s where s.store_id = st.id and s.is_active), '[]'::jsonb),
    'pages', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'title', g.title, 'body', g.body) order by g.sort)
                       from public.store_pages g where g.store_id = st.id and g.is_active), '[]'::jsonb),
    'banners', coalesce((select jsonb_agg(to_jsonb(b) order by b.sort)
                         from public.store_banners b where b.store_id = st.id and b.is_active), '[]'::jsonb),
    'popup', pop
  );
end $$;

select 'categories.parent_id' as item, exists (select 1 from information_schema.columns where table_name='store_categories' and column_name='parent_id') as ok
union all select 'store_banners', to_regclass('public.store_banners') is not null
union all select 'slides.category_id', exists (select 1 from information_schema.columns where table_name='store_slides' and column_name='category_id');
