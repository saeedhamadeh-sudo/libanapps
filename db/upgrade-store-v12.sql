-- ============================================================
--  LibanApps Store — v12
--   • تأكيد (إعادة تعريف) أن السعر المشطوب (Compare-at) بيبين دايماً
--     إذا كان أعلى من السعر الحالي — بدون أي شرط على "ينتهي التخفيض".
--     "ينتهي التخفيض" (sale_ends_at) بيبقى اختياري: إذا حطيته وانتهى
--     تاريخه، السعر بيرجع للسعر الأساسي تلقائياً؛ إذا تركته فاضي
--     التخفيض بيضل ظاهر لحد ما تشيل Compare-at price يدوياً.
--  شغّله بعد upgrade-store-v11.sql — آمن للتشغيل أكثر من مرة.
-- ============================================================
create or replace function public._eff_price(pr numeric, cmp numeric, ends timestamptz)
returns numeric language sql stable as $$
  select case when ends is not null and ends < now() and cmp is not null and cmp > pr then cmp else pr end;
$$;

create or replace function public._eff_compare(pr numeric, cmp numeric, ends timestamptz)
returns numeric language sql stable as $$
  select case when cmp is null or cmp <= pr then null
              when ends is not null and ends < now() then null
              else cmp end;
$$;

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
        select jsonb_agg((to_jsonb(p) - 'store_id' - 'desc_ar' - 'desc_en') || jsonb_build_object(
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

select 'store_public' as item, exists (select 1 from pg_proc where proname='store_public') as ok
union all
select '_eff_price', exists (select 1 from pg_proc where proname='_eff_price')
union all
select '_eff_compare', exists (select 1 from pg_proc where proname='_eff_compare');
