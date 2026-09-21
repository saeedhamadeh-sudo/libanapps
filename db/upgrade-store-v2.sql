-- ============================================================
--  LibanApps Store — ترقية v2
--   • نوع المتجر (ملابس / إكسسوارات / إلكترونيات / …)
--   • مقاسات وألوان ومواصفات وسمات لكل منتج، جديد، وSale بتاريخ انتهاء
--   • تقييمات، صفحات المتجر، مشتركين، مناطق شحن، SEO
--   • بوابات دفع متعددة (Stripe / PayPal / Binance Pay / Areeba / MontyPay / Whish / عامة)
--   • ثيمات جديدة: nova · aurum · pulse · bloom · atelier · electro
--  شغّله بعد db/upgrade-store.sql — آمن للتشغيل أكثر من مرة.
-- ============================================================

-- ============================================================
--  1) المتجر
-- ============================================================
alter table public.stores add column if not exists store_type      text not null default 'general';
alter table public.stores add column if not exists logo_height     integer not null default 44;
alter table public.stores add column if not exists seo_title       text default '';
alter table public.stores add column if not exists seo_desc        text default '';
alter table public.stores add column if not exists og_image        text default '';
alter table public.stores add column if not exists usps            jsonb not null default '[]'::jsonb;        -- [{i,t}]
alter table public.stores add column if not exists shipping_zones  jsonb not null default '[]'::jsonb;        -- [{n,f}]
alter table public.stores add column if not exists size_guide      text default '';
alter table public.stores add column if not exists reviews_enabled boolean not null default true;
alter table public.stores add column if not exists reviews_auto    boolean not null default false;
alter table public.stores add column if not exists newsletter_on   boolean not null default true;

-- قيود الثيم ونوع المتجر (بنشيل القديمة وبنحط الجديدة)
do $$
declare c record;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.stores'::regclass and contype = 'c'
             and (pg_get_constraintdef(oid) ilike '%theme%' or pg_get_constraintdef(oid) ilike '%store_type%')
  loop execute format('alter table public.stores drop constraint %I', c.conname); end loop;
end $$;

update public.stores set theme = case theme
  when 'maison' then 'aurum' when 'fresh' then 'atelier' when 'volt' then 'pulse'
  when 'petal' then 'bloom' else theme end
where theme in ('maison','fresh','volt','petal');
alter table public.stores alter column theme set default 'nova';

alter table public.stores add constraint stores_theme_chk
  check (theme in ('nova','aurum','pulse','bloom','atelier','electro'));
alter table public.stores add constraint stores_type_chk
  check (store_type in ('fashion','accessories','electronics','beauty','home','grocery','general'));

-- ============================================================
--  2) المنتجات
-- ============================================================
alter table public.store_products add column if not exists brand        text default '';
alter table public.store_products add column if not exists sku          text default '';
alter table public.store_products add column if not exists is_new       boolean not null default false;
alter table public.store_products add column if not exists sale_ends_at timestamptz;
alter table public.store_products add column if not exists opt_label    text default '';
alter table public.store_products add column if not exists sizes        jsonb not null default '[]'::jsonb;   -- [{n,s,on}]
alter table public.store_products add column if not exists colors       jsonb not null default '[]'::jsonb;   -- [{n,h,on}]
alter table public.store_products add column if not exists specs        jsonb not null default '[]'::jsonb;   -- [{k,v}]
alter table public.store_products add column if not exists attrs        jsonb not null default '{}'::jsonb;

-- السعر الفعّال: إذا انتهى تاريخ الـSale بيرجع للسعر قبل الخصم
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

-- ============================================================
--  3) الطلبات: بوابات دفع + مقاس/لون
-- ============================================================
alter table public.store_orders add column if not exists payment_ref text default '';
alter table public.store_orders add column if not exists shipping_zone text default '';
alter table public.store_order_items add column if not exists size  text default '';
alter table public.store_order_items add column if not exists color text default '';

do $$
declare c record;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.store_orders'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%payment_method%'
  loop execute format('alter table public.store_orders drop constraint %I', c.conname); end loop;
end $$;
alter table public.store_orders add constraint store_orders_pm_chk check (length(payment_method) between 2 and 20);

-- ============================================================
--  4) جداول جديدة
-- ============================================================
create table if not exists public.store_reviews (
  id          uuid primary key default gen_random_uuid(),
  store_id    uuid not null references public.stores(id) on delete cascade,
  product_id  uuid not null references public.store_products(id) on delete cascade,
  name        text not null,
  rating      integer not null check (rating between 1 and 5),
  body        text default '',
  is_approved boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists store_reviews_idx on public.store_reviews (store_id, product_id, is_approved);

create table if not exists public.store_pages (
  id        uuid primary key default gen_random_uuid(),
  store_id  uuid not null references public.stores(id) on delete cascade,
  title     text not null,
  body      text default '',
  sort      integer not null default 0,
  is_active boolean not null default true
);
create index if not exists store_pages_idx on public.store_pages (store_id, sort);

create table if not exists public.store_subscribers (
  id         uuid primary key default gen_random_uuid(),
  store_id   uuid not null references public.stores(id) on delete cascade,
  email      text not null,
  created_at timestamptz not null default now(),
  unique (store_id, email)
);

-- بوابات الدفع: الإعدادات (فيها أسرار) — بدون أي سياسة قراءة/كتابة
create table if not exists public.store_gateways (
  store_id   uuid not null references public.stores(id) on delete cascade,
  provider   text not null,
  enabled    boolean not null default false,
  config     jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (store_id, provider)
);

alter table public.store_reviews     enable row level security;
alter table public.store_pages       enable row level security;
alter table public.store_subscribers enable row level security;
alter table public.store_gateways    enable row level security;

do $$
declare t text;
begin
  foreach t in array array['store_reviews','store_pages','store_subscribers']
  loop
    execute format('drop policy if exists own_%1$s on public.%1$s', t);
    execute format('create policy own_%1$s on public.%1$s for all to authenticated
                    using (public.store_owned(store_id)) with check (public.store_owned(store_id))', t);
  end loop;
end $$;

-- نقل بيانات Whish القديمة لجدول البوابات
insert into public.store_gateways (store_id, provider, enabled, config)
select c.store_id, 'whish', coalesce(s.whish_enabled, false),
       jsonb_build_object('channel', c.whish_channel, 'secret', c.whish_secret)
from public.store_payment_credentials c
join public.stores s on s.id = c.store_id
where coalesce(c.whish_channel,'') <> ''
on conflict (store_id, provider) do nothing;

-- ============================================================
--  5) البوابات: جاهزية + دعم العملة
-- ============================================================
create or replace function public._gw_ready(p_provider text, cfg jsonb)
returns boolean language sql immutable as $$
  select case p_provider
    when 'whish'   then coalesce(cfg->>'channel','')<>'' and coalesce(cfg->>'secret','')<>''
    when 'stripe'  then coalesce(cfg->>'secret_key','')<>''
    when 'paypal'  then coalesce(cfg->>'client_id','')<>'' and coalesce(cfg->>'secret','')<>''
    when 'binance' then coalesce(cfg->>'api_key','')<>'' and coalesce(cfg->>'secret_key','')<>''
    when 'areeba'  then coalesce(cfg->>'merchant_id','')<>'' and coalesce(cfg->>'api_password','')<>''
    when 'montypay' then coalesce(cfg->>'create_url','')<>'' and coalesce(cfg->>'body','')<>'' and coalesce(cfg->>'redirect_path','')<>''
    when 'custom'  then coalesce(cfg->>'create_url','')<>'' and coalesce(cfg->>'body','')<>'' and coalesce(cfg->>'redirect_path','')<>''
    when 'manual'  then coalesce(cfg->>'instructions','')<>''
    else false end;
$$;

create or replace function public._gw_supports(p_provider text, p_currency text)
returns boolean language sql immutable as $$
  select case p_provider
    when 'whish'  then p_currency in ('USD','LBP')
    when 'paypal' then p_currency in ('AUD','BRL','CAD','CNY','CZK','DKK','EUR','HKD','HUF','ILS','JPY','MYR','MXN','TWD','NZD','NOK','PHP','PLN','GBP','RUB','SGD','SEK','CHF','THB','USD')
    when 'binance' then p_currency in ('USD','EUR')
    else true end;
$$;

create or replace function public.set_store_gateway(
  p_store uuid, p_provider text, p_enabled boolean, p_config jsonb
) returns void language plpgsql security definer set search_path = public as $$
declare old jsonb; merged jsonb; k text; v jsonb;
begin
  if not public.store_owned(p_store) then raise exception 'not allowed'; end if;
  if p_provider not in ('whish','stripe','paypal','binance','areeba','montypay','custom','manual') then
    raise exception 'unknown provider'; end if;
  select config into old from public.store_gateways where store_id = p_store and provider = p_provider;
  merged := coalesce(old, '{}'::jsonb);
  for k, v in select * from jsonb_each(coalesce(p_config,'{}'::jsonb)) loop
    if jsonb_typeof(v) = 'string' and (v #>> '{}') = '' then continue; end if;   -- فاضي = ما منغيّر
    merged := merged || jsonb_build_object(k, v);
  end loop;
  insert into public.store_gateways (store_id, provider, enabled, config, updated_at)
  values (p_store, p_provider, coalesce(p_enabled,false), merged, now())
  on conflict (store_id, provider) do update
    set enabled = excluded.enabled, config = excluded.config, updated_at = now();
end $$;

-- الحالة للوحة: أي مفاتيح محفوظة (بدون قيمها) + تلميح آخر 4 أحرف للمعرّفات
create or replace function public.store_gateway_status(p_store uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r record; out jsonb := '{}'::jsonb; has jsonb; hint jsonb; k text; v jsonb;
begin
  if not public.store_owned(p_store) then raise exception 'not allowed'; end if;
  for r in select * from public.store_gateways where store_id = p_store loop
    has := '{}'::jsonb; hint := '{}'::jsonb;
    for k, v in select * from jsonb_each(r.config) loop
      has := has || jsonb_build_object(k, (v #>> '{}') <> '');
      if jsonb_typeof(v) = 'string' and length(v #>> '{}') > 0 then
        if k in ('channel','client_id','merchant_id','api_key') then
          hint := hint || jsonb_build_object(k, '••••' || right(v #>> '{}', 4));          -- معرّفات: آخر 4 أحرف فقط
        elsif k in ('mode','host','label','currency','api_version','create_url','body','redirect_path','ref_path',
                    'status_url','status_path','paid_values','content_type','method','instructions') then
          hint := hint || jsonb_build_object(k, v #>> '{}');                              -- إعدادات غير سرّية
        end if;                                                                           -- الباقي (أسرار/headers) ما بيرجع أبداً
      end if;
    end loop;
    out := out || jsonb_build_object(r.provider, jsonb_build_object(
      'enabled', r.enabled, 'ready', public._gw_ready(r.provider, r.config), 'has', has, 'hint', hint));
  end loop;
  return out;
end $$;

-- ============================================================
--  6) عرض المتجر للزوّار (v2)
-- ============================================================
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
    'popup', pop
  );
end $$;

create or replace function public.store_reviews(p_slug text, p_product uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('name', r.name, 'rating', r.rating, 'body', r.body,
                                               'at', r.created_at) order by r.created_at desc), '[]'::jsonb)
  from public.store_reviews r join public.stores s on s.id = r.store_id
  where s.slug = lower(trim(p_slug)) and r.product_id = p_product and r.is_approved;
$$;

create or replace function public.store_add_review(
  p_slug text, p_product uuid, p_name text, p_rating integer, p_body text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare st public.stores%rowtype; pid uuid;
begin
  select * into st from public.stores where slug = lower(trim(coalesce(p_slug,'')));
  if not found or not st.is_active or not st.reviews_enabled
     or not (public.store_license(st.id)->>'ok')::boolean then raise exception 'reviews unavailable'; end if;
  select id into pid from public.store_products where id = p_product and store_id = st.id and is_active;
  if pid is null then raise exception 'product unavailable'; end if;
  if length(trim(coalesce(p_name,''))) < 2 or p_rating not between 1 and 5 then raise exception 'invalid review'; end if;
  insert into public.store_reviews (store_id, product_id, name, rating, body, is_approved)
  values (st.id, pid, left(trim(p_name),60), p_rating, left(coalesce(p_body,''),800), st.reviews_auto);
  return jsonb_build_object('ok', true, 'approved', st.reviews_auto);
end $$;

create or replace function public.store_subscribe(p_slug text, p_email text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare st public.stores%rowtype; em text := lower(trim(coalesce(p_email,'')));
begin
  select * into st from public.stores where slug = lower(trim(coalesce(p_slug,'')));
  if not found or not st.is_active or not st.newsletter_on then raise exception 'unavailable'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(em) > 120 then raise exception 'invalid email'; end if;
  insert into public.store_subscribers (store_id, email) values (st.id, em) on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;

-- تتبّع طلب: رقم الطلب + آخر 7 أرقام من الهاتف
create or replace function public.store_track_order(p_slug text, p_order_no text, p_phone text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st public.stores%rowtype; o public.store_orders%rowtype; d text := right(regexp_replace(coalesce(p_phone,''),'\D','','g'), 7);
begin
  select * into st from public.stores where slug = lower(trim(coalesce(p_slug,'')));
  if not found then return jsonb_build_object('ok', false); end if;
  select * into o from public.store_orders
   where store_id = st.id and upper(order_no) = upper(trim(coalesce(p_order_no,'')))
     and length(d) = 7 and right(regexp_replace(customer_phone,'\D','','g'), 7) = d limit 1;
  if not found then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true, 'order_no', o.order_no, 'status', o.status, 'created_at', o.created_at,
    'total', o.total, 'method', o.delivery_method, 'payment', o.payment_method,
    'currency_symbol', st.currency_symbol, 'currency_decimals', st.currency_decimals,
    'items', coalesce((select jsonb_agg(jsonb_build_object('name', i.name, 'qty', i.qty, 'size', i.size, 'color', i.color))
                       from public.store_order_items i where i.order_id = o.id), '[]'::jsonb));
end $$;

-- ============================================================
--  7) الطلب (v2): مقاس/لون + منطقة شحن + بوابة دفع
-- ============================================================
create or replace function public._size_stock_add(p_pid uuid, p_size text, p_delta integer)
returns void language sql security definer set search_path = public as $$
  update public.store_products p set sizes = coalesce((
    select jsonb_agg(case when e->>'n' = p_size and jsonb_typeof(e->'s') = 'number'
                          then jsonb_set(e, '{s}', to_jsonb(greatest(0, (e->>'s')::int + p_delta)))
                          else e end order by ord)
    from jsonb_array_elements(p.sizes) with ordinality as x(e, ord)), '[]'::jsonb)
  where p.id = p_pid;
$$;
revoke all on function public._size_stock_add(uuid, text, integer) from public, anon, authenticated;

drop function if exists public.store_place_order(text,text,text,text,text,text,text,text,text,text,jsonb);

create or replace function public.store_place_order(
  p_slug text, p_name text, p_phone text, p_email text, p_method text,
  p_zone text, p_city text, p_address text, p_note text, p_payment text, p_coupon text, p_lines jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  st public.stores%rowtype; pr public.store_products%rowtype; gw public.store_gateways%rowtype;
  v_sub numeric := 0; v_disc numeric := 0; v_fee numeric := 0; v_tot numeric;
  v_no text; v_id bigint; v_tok text; v_cp jsonb; v_code text := '';
  ln record; v_qty integer; v_items jsonb := '[]'::jsonb; v_price numeric; sz jsonb; cl jsonb;
  z jsonb; v_zone text := ''; v_online boolean := false; v_note text := '';
begin
  select * into st from public.stores where slug = lower(trim(coalesce(p_slug,''))) for update;
  if not found or not st.is_active or not (public.store_license(st.id)->>'ok')::boolean then
    raise exception 'store unavailable'; end if;

  if length(trim(coalesce(p_name,''))) < 2 or length(regexp_replace(coalesce(p_phone,''),'\D','','g')) < 7 then
    raise exception 'invalid customer details'; end if;
  if p_method not in ('delivery','pickup') then raise exception 'bad method'; end if;
  if p_method = 'delivery' and not st.delivery_enabled then raise exception 'delivery disabled'; end if;
  if p_method = 'pickup'   and not st.pickup_enabled   then raise exception 'pickup disabled'; end if;
  if p_method = 'delivery' and length(trim(coalesce(p_address,''))) < 3 then raise exception 'address required'; end if;

  -- الدفع
  if p_payment = 'cod' then
    if not st.cod_enabled then raise exception 'cod disabled'; end if;
  else
    select * into gw from public.store_gateways where store_id = st.id and provider = p_payment and enabled;
    if not found or not public._gw_ready(gw.provider, gw.config) or not public._gw_supports(gw.provider, st.currency_code) then
      raise exception 'payment method disabled'; end if;
    v_online := p_payment <> 'manual';
  end if;

  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'empty cart'; end if;

  for ln in
    select x.id, coalesce(x.size,'') as size, coalesce(x.color,'') as color,
           sum(greatest(1, least(99, coalesce(x.qty,1))))::int as qty
    from jsonb_to_recordset(p_lines) as x(id uuid, qty int, size text, color text)
    group by x.id, coalesce(x.size,''), coalesce(x.color,'')
  loop
    v_qty := ln.qty;
    select * into pr from public.store_products where id = ln.id and store_id = st.id and is_active for update;
    if not found then raise exception 'product unavailable'; end if;

    if jsonb_array_length(pr.sizes) > 0 then
      select e into sz from jsonb_array_elements(pr.sizes) e where e->>'n' = ln.size limit 1;
      if sz is null or coalesce((sz->>'on')::boolean, true) = false then
        raise exception 'insufficient stock: %', coalesce(nullif(pr.name_ar,''), pr.name_en) || ' ' || ln.size; end if;
      if jsonb_typeof(sz->'s') = 'number' and (sz->>'s')::int < v_qty then
        raise exception 'insufficient stock: %', coalesce(nullif(pr.name_ar,''), pr.name_en) || ' ' || ln.size; end if;
    elsif pr.stock is not null and pr.stock < v_qty then
      raise exception 'insufficient stock: %', coalesce(nullif(pr.name_ar,''), pr.name_en);
    end if;

    if jsonb_array_length(pr.colors) > 0 then
      select e into cl from jsonb_array_elements(pr.colors) e where e->>'n' = ln.color limit 1;
      if cl is null or coalesce((cl->>'on')::boolean, true) = false then
        raise exception 'insufficient stock: %', coalesce(nullif(pr.name_ar,''), pr.name_en) || ' ' || ln.color; end if;
    end if;

    v_price := public._eff_price(pr.price, pr.compare_price, pr.sale_ends_at);
    v_sub := v_sub + v_price * v_qty;
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'id', pr.id, 'name', coalesce(nullif(pr.name_ar,''), pr.name_en), 'price', v_price,
      'qty', v_qty, 'size', ln.size, 'color', ln.color, 'hassz', jsonb_array_length(pr.sizes) > 0));
  end loop;

  if v_sub < st.min_order then raise exception 'min order'; end if;

  if coalesce(trim(p_coupon),'') <> '' then
    v_cp := public._store_coupon_calc(st.id, p_coupon, v_sub);
    if not (v_cp->>'ok')::boolean then raise exception 'coupon: %', v_cp->>'reason'; end if;
    v_disc := (v_cp->>'discount')::numeric; v_code := v_cp->>'code';
  end if;

  if p_method = 'delivery' then
    if jsonb_array_length(st.shipping_zones) > 0 then
      select e into z from jsonb_array_elements(st.shipping_zones) e where e->>'n' = p_zone limit 1;
      if z is null then raise exception 'zone required'; end if;
      v_fee := coalesce((z->>'f')::numeric, 0); v_zone := z->>'n';
    else
      v_fee := st.delivery_fee;
    end if;
    if st.free_delivery_over is not null and (v_sub - v_disc) >= st.free_delivery_over then v_fee := 0; end if;
  end if;

  v_sub := round(v_sub, st.currency_decimals);
  v_tot := round(v_sub - v_disc + v_fee, st.currency_decimals);

  update public.stores set order_seq = order_seq + 1 where id = st.id returning order_seq into v_id;
  v_no := 'S' || lpad(v_id::text, 4, '0');

  insert into public.store_orders (store_id, order_no, customer_name, customer_phone, customer_email,
      delivery_method, city, address_text, customer_note, subtotal, discount, coupon_code,
      delivery_fee, total, currency_code, payment_method, shipping_zone, status)
  values (st.id, v_no, trim(p_name), trim(p_phone), coalesce(trim(p_email),''),
      p_method, coalesce(nullif(trim(p_city),''), v_zone), coalesce(trim(p_address),''), coalesce(trim(p_note),''),
      v_sub, v_disc, v_code, v_fee, v_tot, st.currency_code, p_payment, v_zone,
      case when v_online then 'awaiting_payment' else 'pending' end)
  returning id, token into v_id, v_tok;

  insert into public.store_order_items (order_id, product_id, name, unit_price, qty, line_total, size, color)
  select v_id, (i->>'id')::uuid, i->>'name', (i->>'price')::numeric, (i->>'qty')::int,
         round((i->>'price')::numeric * (i->>'qty')::int, st.currency_decimals), i->>'size', i->>'color'
  from jsonb_array_elements(v_items) i;

  -- المخزون: بالمقاس إذا فيه مقاسات، وإلا بالمنتج
  for ln in select (i->>'id')::uuid as id, i->>'size' as size, (i->>'qty')::int as qty, (i->>'hassz')::boolean as hassz
            from jsonb_array_elements(v_items) i loop
    if ln.hassz then perform public._size_stock_add(ln.id, ln.size, -ln.qty);
    else update public.store_products set stock = stock - ln.qty where id = ln.id and stock is not null; end if;
  end loop;

  if v_code <> '' then
    update public.store_coupons set used_count = used_count + 1 where store_id = st.id and code = v_code;
  end if;

  if p_payment = 'manual' then v_note := coalesce(gw.config->>'instructions',''); end if;

  return jsonb_build_object(
    'order_id', v_id, 'order_no', v_no, 'token', v_tok, 'subtotal', v_sub, 'discount', v_disc,
    'delivery_fee', v_fee, 'total', v_tot, 'currency_code', st.currency_code,
    'currency_symbol', st.currency_symbol, 'currency_decimals', st.currency_decimals,
    'whatsapp', st.whatsapp, 'online', v_online, 'note', v_note);
end $$;

-- الطلب الملغي/الفاشل بيرجّع المخزون (بالمقاس أو بالمنتج) والكوبون
create or replace function public.store_orders_restock()
returns trigger language plpgsql security definer set search_path = public as $$
declare was_dead boolean; is_dead boolean; i record; sgn integer;
begin
  was_dead := old.status in ('failed','cancelled');
  is_dead  := new.status in ('failed','cancelled');
  if is_dead = was_dead then return new; end if;
  sgn := case when is_dead then 1 else -1 end;
  for i in select it.product_id, it.size, it.qty, (jsonb_array_length(p.sizes) > 0) as hassz
           from public.store_order_items it join public.store_products p on p.id = it.product_id
           where it.order_id = new.id loop
    if i.hassz then perform public._size_stock_add(i.product_id, i.size, sgn * i.qty);
    else update public.store_products set stock = greatest(0, stock + sgn * i.qty)
         where id = i.product_id and stock is not null; end if;
  end loop;
  if coalesce(new.coupon_code,'') <> '' then
    update public.store_coupons set used_count = greatest(0, used_count + case when is_dead then -1 else 1 end)
     where store_id = new.store_id and code = new.coupon_code;
  end if;
  return new;
end $$;

-- تحقق سريع
select 'store_type' as item, exists (select 1 from information_schema.columns where table_name='stores' and column_name='store_type') as ok
union all select 'gateways table', to_regclass('public.store_gateways') is not null
union all select 'reviews table',  to_regclass('public.store_reviews') is not null
union all select 'new place_order', exists (select 1 from pg_proc where proname='store_place_order' and pronargs = 12);
