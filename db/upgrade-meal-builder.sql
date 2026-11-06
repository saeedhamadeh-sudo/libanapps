-- ============================================================
--  LibanApps — «ركّب وجبتك» + منيوهات جاهزة (Route 66)
--  ------------------------------------------------------------
--  • categories.builder: قسم تركيب — الزبون بيختار خطوة بخطوة
--    (خيار واحد أو أكثر لكل خطوة، وكل خيار إلو سعر بينجمع)
--    المنتجات تحت القسم = خطوة "__item" (مثلاً اختار اللحمة)
--  • order_items.options: الخيارات اللي اختارها الزبون
--  • place_order: بيحسب سعر الخيارات بالسيرفر (ما منثق بسعر المتصفح)
--  • menu_templates + super_apply_menu_template: السوبر بيعطي منيو جاهز لأي مطعم
--  • تصليح: orders_status_check ما كان فيه awaiting_payment → طلبات Whish كانت تفشل
--  آمن للتشغيل أكثر من مرة
-- ============================================================

-- 0) تصليح حالات الطلب (Whish + auto_dispatch بيستعملوا هالقيم)
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check
  check (status in ('pending','awaiting_payment','accepted','rejected','paid','confirmed','failed','cancelled','refunded'));

-- 1) أعمدة جديدة
alter table public.categories  add column if not exists builder jsonb;
alter table public.order_items add column if not exists options jsonb;

-- 2) place_order — نفس التوقيع، مع دعم opts لكل سطر
--    p_lines: [{item_id, qty, opts?: {"base":["b1"], "veg":["v1","v3"], ...}}]
create or replace function public.place_order(
  p_slug text, p_type text, p_name text, p_phone text, p_table text,
  p_address text, p_lat double precision, p_lng double precision,
  p_note text, p_payment text, p_lines jsonb
) returns table (order_id bigint, order_no text, token text, total_usd numeric, total_lbp numeric)
language plpgsql security definer set search_path = public as $$
declare
  r public.restaurants%rowtype;
  v_sub numeric(10,2) := 0; v_del numeric(10,2) := 0;
  v_tot numeric(10,2); v_lbp numeric(14,0);
  v_no text; v_id bigint; v_tok text;
  ln jsonb; it public.items%rowtype; v_qty integer;
  v_builder jsonb; g jsonb; v_sel jsonb;
  v_unit numeric(10,2); v_opts jsonb; v_lab_ar text; v_lab_en text;
  v_cnt integer; v_add numeric(10,2); v_gar text; v_gen text; v_gjs jsonb; v_bad integer;
begin
  select * into r from public.restaurants where slug = p_slug;
  if not found or not public.menu_live(r.id) then raise exception 'restaurant unavailable'; end if;
  if p_type = 'dine_in'  and not r.dinein_enabled   then raise exception 'dine-in disabled'; end if;
  if p_type = 'delivery' and not r.delivery_enabled then raise exception 'delivery disabled'; end if;
  if length(trim(p_name)) < 2 or length(regexp_replace(p_phone,'\D','','g')) < 7 then
    raise exception 'invalid customer details'; end if;
  if p_type = 'delivery' and r.require_location and (p_lat is null or p_lng is null) then
    raise exception 'location required'; end if;
  if jsonb_array_length(p_lines) = 0 or jsonb_array_length(p_lines) > 60 then
    raise exception 'invalid cart'; end if;

  r.order_seq := r.order_seq + 1;
  update public.restaurants set order_seq = r.order_seq where id = r.id;
  v_no := upper(left(r.slug, 2)) || '-' || (1000 + r.order_seq);

  insert into public.orders (restaurant_id, order_no, order_type, customer_name, customer_phone,
                             table_no, address_text, lat, lng, customer_note,
                             subtotal_usd, delivery_usd, total_usd, exchange_rate, total_lbp,
                             payment_method, status)
  values (r.id, v_no, p_type, trim(p_name), trim(p_phone),
          coalesce(p_table,''), coalesce(p_address,''), p_lat, p_lng, coalesce(p_note,''),
          0, 0, 0, r.exchange_rate, 0, p_payment,
          case when p_payment = 'whish' then 'awaiting_payment' else 'pending' end)
  returning orders.id, orders.token into v_id, v_tok;

  for ln in select * from jsonb_array_elements(p_lines) loop
    v_qty := greatest(1, least(50, (ln->>'qty')::int));
    select * into it from public.items
      where id = (ln->>'item_id')::uuid and restaurant_id = r.id and is_available;
    if not found then continue; end if;

    v_unit := it.price_usd; v_opts := null; v_lab_ar := ''; v_lab_en := '';
    select c.builder into v_builder from public.categories c where c.id = it.category_id;

    if v_builder is not null and jsonb_typeof(v_builder->'groups') = 'array' then
      v_opts := '[]'::jsonb;
      for g in select * from jsonb_array_elements(v_builder->'groups') loop
        continue when g->>'key' = '__item';
        v_sel := ln->'opts'->(g->>'key');
        if v_sel is null or jsonb_typeof(v_sel) <> 'array' then v_sel := '[]'::jsonb; end if;

        -- خيار مش موجود بالقائمة؟
        select count(*) into v_bad from jsonb_array_elements_text(v_sel) s(id)
         where not exists (select 1 from jsonb_array_elements(coalesce(g->'choices','[]'::jsonb)) ch
                            where ch->>'id' = s.id and not coalesce((ch->>'off')::boolean,false));
        if v_bad > 0 then raise exception 'invalid option'; end if;

        select count(*), coalesce(sum((ch->>'price')::numeric),0),
               string_agg(ch->>'name_ar', '، '), string_agg(ch->>'name_en', ', '),
               coalesce(jsonb_agg(jsonb_build_object('id',ch->>'id','name_ar',ch->>'name_ar',
                          'name_en',ch->>'name_en','price',(ch->>'price')::numeric)),'[]'::jsonb)
          into v_cnt, v_add, v_gar, v_gen, v_gjs
          from jsonb_array_elements(coalesce(g->'choices','[]'::jsonb)) ch
         where ch->>'id' in (select distinct x from jsonb_array_elements_text(v_sel) t(x));

        if v_cnt < coalesce((g->>'min')::int,0) then raise exception 'missing option: %', g->>'name_en'; end if;
        if (g->>'max') is not null and v_cnt > (g->>'max')::int then raise exception 'too many options: %', g->>'name_en'; end if;

        if v_cnt > 0 then
          v_unit := v_unit + v_add;
          v_opts := v_opts || jsonb_build_array(jsonb_build_object('key',g->>'key',
                      'name_ar',g->>'name_ar','name_en',g->>'name_en','choices',v_gjs));
          v_lab_ar := v_lab_ar || case when v_lab_ar = '' then '' else ' · ' end || v_gar;
          v_lab_en := v_lab_en || case when v_lab_en = '' then '' else ' · ' end || v_gen;
        end if;
      end loop;
    end if;

    insert into public.order_items (order_id, item_id, name_ar, name_en, price_usd, qty, line_usd, options)
    values (v_id, it.id,
            it.name_ar || case when v_lab_ar <> '' then ' — ' || v_lab_ar else '' end,
            it.name_en || case when v_lab_en <> '' then ' — ' || v_lab_en else '' end,
            v_unit, v_qty, v_unit * v_qty, v_opts);
    v_sub := v_sub + v_unit * v_qty;
  end loop;

  if v_sub = 0 then raise exception 'empty cart'; end if;
  if p_type = 'delivery' then
    if v_sub < r.min_order_usd then raise exception 'below minimum order'; end if;
    v_del := r.delivery_fee_usd;
  end if;

  v_tot := v_sub + v_del;
  v_lbp := round(v_tot * r.exchange_rate / r.lbp_rounding) * r.lbp_rounding;
  update public.orders set subtotal_usd = v_sub, delivery_usd = v_del,
         total_usd = v_tot, total_lbp = v_lbp where id = v_id;

  return query select v_id, v_no, v_tok, v_tot, v_lbp;
end $$;

-- 3) منيوهات جاهزة
create table if not exists public.menu_templates (
  code       text primary key,
  name       text not null,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.menu_templates enable row level security;
drop policy if exists "menu_templates_admin" on public.menu_templates;
create policy "menu_templates_admin" on public.menu_templates
  for all using (public.is_admin()) with check (public.is_admin());

create or replace function public.super_menu_templates()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,
           'cats', jsonb_array_length(data->'categories')) order by name) from public.menu_templates), '[]'::jsonb);
end $$;
grant execute on function public.super_menu_templates() to authenticated;

-- p_replace = true: بيمسح أقسام ومنتجات المطعم الحالية قبل
create or replace function public.super_apply_menu_template(p_rid uuid, p_code text, p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t public.menu_templates%rowtype; c jsonb; i jsonb; v_sort integer; v_cid uuid;
        n_c integer := 0; n_i integer := 0; v_isort integer;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  select * into t from public.menu_templates where code = p_code;
  if not found then raise exception 'template not found'; end if;
  if not exists (select 1 from public.restaurants where id = p_rid) then raise exception 'restaurant not found'; end if;

  if p_replace then
    delete from public.items where restaurant_id = p_rid;
    delete from public.categories where restaurant_id = p_rid;
  end if;
  select coalesce(max(sort),0) into v_sort from public.categories where restaurant_id = p_rid;

  for c in select * from jsonb_array_elements(t.data->'categories') loop
    v_sort := v_sort + 1; n_c := n_c + 1;
    insert into public.categories (restaurant_id, name_ar, name_en, sort, is_active, builder)
    values (p_rid, c->>'name_ar', coalesce(c->>'name_en', c->>'name_ar'), v_sort, true, c->'builder')
    returning id into v_cid;
    v_isort := 0;
    for i in select * from jsonb_array_elements(coalesce(c->'items','[]'::jsonb)) loop
      v_isort := v_isort + 1; n_i := n_i + 1;
      insert into public.items (restaurant_id, category_id, name_ar, name_en, desc_ar, desc_en,
                                price_usd, is_available, is_featured, sort)
      values (p_rid, v_cid, i->>'name_ar', coalesce(i->>'name_en', i->>'name_ar'),
              coalesce(i->>'desc_ar',''), coalesce(i->>'desc_en',''),
              coalesce((i->>'price_usd')::numeric,0), true, coalesce((i->>'is_featured')::boolean,false), v_isort);
    end loop;
  end loop;
  return jsonb_build_object('ok', true, 'categories', n_c, 'items', n_i);
end $$;
grant execute on function public.super_apply_menu_template(uuid, text, boolean) to authenticated;

-- 4) قالب Route 66
insert into public.menu_templates (code, name, data) values ('route66', 'Route 66 — برغر ووجبات (مع ركّب وجبتك)', $tpl${"categories": [{"name_en": "Build It Your Way", "name_ar": "ركّب وجبتك", "builder": {"title_en": "Choose Your Base & Build It Your Way", "title_ar": "اختار الخبز وركّب وجبتك على ذوقك", "groups": [{"key": "base", "name_en": "Choose Your Base", "name_ar": "اختار الخبز", "min": 1, "max": 1, "choices": [{"id": "b1", "name_en": "Burger Bun", "name_ar": "خبز برغر", "price": 0}, {"id": "b2", "name_en": "Tortilla Wrap", "name_ar": "خبز تورتيلا", "price": 0}, {"id": "b3", "name_en": "Sub Sandwich", "name_ar": "خبز صب", "price": 0}]}, {"key": "__item", "name_en": "Choose Your Meat", "name_ar": "اختار اللحمة", "min": 1, "max": 1}, {"key": "veg", "name_en": "Choose Your Veggies", "name_ar": "اختار الخضار", "min": 0, "max": 9, "choices": [{"id": "v1", "name_en": "Fresh Rocca Leaves", "name_ar": "روكا طازة", "price": 0.4}, {"id": "v2", "name_en": "Fresh Iceberg Lettuce", "name_ar": "خس آيسبرغ طازة", "price": 0.4}, {"id": "v3", "name_en": "Fresh / Grilled Tomatoes", "name_ar": "بندورة طازة / مشوية", "price": 0.2}, {"id": "v4", "name_en": "Fresh / Grilled Onions", "name_ar": "بصل طازة / مشوي", "price": 0.3}, {"id": "v5", "name_en": "Fresh / Grilled Peppers", "name_ar": "فليفلة طازة / مشوية", "price": 0.4}, {"id": "v6", "name_en": "Fresh / Grilled Chili Peppers", "name_ar": "فليفلة حرّة طازة / مشوية", "price": 0.4}, {"id": "v7", "name_en": "Grilled Mushrooms", "name_ar": "فطر مشوي", "price": 0.8}, {"id": "v8", "name_en": "Dill Pickles", "name_ar": "مخلل خيار", "price": 0.4}, {"id": "v9", "name_en": "Jalapeños", "name_ar": "هالابينو", "price": 0.4}]}, {"key": "cheese", "name_en": "Choose Your Cheese", "name_ar": "اختار الجبنة", "min": 0, "max": 6, "choices": [{"id": "c1", "name_en": "6 Cheeses", "name_ar": "٦ أنواع جبنة", "price": 1.5}, {"id": "c2", "name_en": "Emmental Slice", "name_ar": "شريحة إيمنتال", "price": 0.9}, {"id": "c3", "name_en": "Cheddar Slice", "name_ar": "شريحة شيدر", "price": 0.9}, {"id": "c4", "name_en": "Cheddar Sauce", "name_ar": "صوص شيدر", "price": 0.9}, {"id": "c5", "name_en": "Cheddar Patty", "name_ar": "قرص شيدر", "price": 1.9}, {"id": "c6", "name_en": "Mozzarella Patty", "name_ar": "قرص موزاريلا", "price": 1.9}]}, {"key": "sauce", "name_en": "Choose Your Sauce", "name_ar": "اختار الصوص", "min": 0, "max": 7, "choices": [{"id": "s1", "name_en": "R66 Sauce", "name_ar": "صوص R66", "price": 0.9}, {"id": "s2", "name_en": "Herbal Mayo", "name_ar": "مايونيز بالأعشاب", "price": 0.9}, {"id": "s3", "name_en": "Garlic Mayo", "name_ar": "مايونيز بالثوم", "price": 0.9}, {"id": "s4", "name_en": "Honey Mustard", "name_ar": "هني ماستارد", "price": 0.9}, {"id": "s5", "name_en": "Mayo Barbecue", "name_ar": "مايو باربكيو", "price": 0.9}, {"id": "s6", "name_en": "Cocktail", "name_ar": "كوكتيل", "price": 0.9}, {"id": "s7", "name_en": "Chili Mayo", "name_ar": "مايو حار", "price": 0.9}]}, {"key": "top", "name_en": "More Toppings", "name_ar": "إضافات", "min": 0, "max": 5, "choices": [{"id": "t1", "name_en": "Chips Sticks", "name_ar": "أصابع شيبس", "price": 0.9}, {"id": "t2", "name_en": "Fries", "name_ar": "بطاطا", "price": 0.9}, {"id": "t3", "name_en": "Onion Rings", "name_ar": "حلقات بصل", "price": 1}, {"id": "t4", "name_en": "Turkey Bacon", "name_ar": "بيكن حبش", "price": 1.6}, {"id": "t5", "name_en": "Coleslaw", "name_ar": "كول سلو", "price": 0.9}]}]}, "items": [{"name_en": "Grilled Angus Beef 170gr", "name_ar": "لحم أنغوس مشوي ١٧٠غ", "price_usd": 4.9, "desc_en": "", "desc_ar": ""}, {"name_en": "Smashed Angus Beef 150gr", "name_ar": "لحم أنغوس سماش ١٥٠غ", "price_usd": 4.3, "desc_en": "", "desc_ar": ""}, {"name_en": "Grilled Chicken Breast", "name_ar": "صدر دجاج مشوي", "price_usd": 3.8, "desc_en": "", "desc_ar": ""}, {"name_en": "Fried Crispy Chicken", "name_ar": "دجاج كرسبي مقلي", "price_usd": 3.8, "desc_en": "", "desc_ar": ""}]}, {"name_en": "Appetizers", "name_ar": "مقبلات", "items": [{"name_en": "Fries Cup", "name_ar": "كاسة بطاطا", "price_usd": 3, "desc_en": "", "desc_ar": ""}, {"name_en": "Fries Box", "name_ar": "علبة بطاطا", "price_usd": 5, "desc_en": "", "desc_ar": ""}, {"name_en": "Curly Fries Cup", "name_ar": "كاسة بطاطا كيرلي", "price_usd": 4, "desc_en": "", "desc_ar": ""}, {"name_en": "Jalapeno Cheesy Bites (6pcs)", "name_ar": "هالابينو بالجبنة (٦ قطع)", "price_usd": 4, "desc_en": "", "desc_ar": ""}, {"name_en": "Mozzarella Sticks (5pcs)", "name_ar": "أصابع موزاريلا (٥ قطع)", "price_usd": 5, "desc_en": "", "desc_ar": ""}, {"name_en": "Onion Rings (5pcs)", "name_ar": "حلقات بصل (٥ قطع)", "price_usd": 3, "desc_en": "", "desc_ar": ""}, {"name_en": "Chicken Nuggets (6pcs)", "name_ar": "ناغتس دجاج (٦ قطع)", "price_usd": 4, "desc_en": "", "desc_ar": ""}, {"name_en": "Wings Box (10pcs)", "name_ar": "علبة جوانح (١٠ قطع)", "price_usd": 7, "desc_en": "", "desc_ar": ""}, {"name_en": "Crispy Chicken Cup (3pcs)", "name_ar": "كاسة دجاج كرسبي (٣ قطع)", "price_usd": 4, "desc_en": "", "desc_ar": ""}]}, {"name_en": "Meals", "name_ar": "وجبات", "items": [{"name_en": "Crispy Chicken Meal", "name_ar": "وجبة دجاج كرسبي", "price_usd": 10, "desc_en": "5 Crispy Chicken Pieces Regular or Spicy Served with Fries Cup, Garlic Mayo, Pickles, Coleslaw & a Bun", "desc_ar": "٥ قطع دجاج كرسبي عادي أو حار مع كاسة بطاطا، مايونيز بالثوم، مخلل، كول سلو وخبزة"}, {"name_en": "Crispy Family Meal", "name_ar": "وجبة كرسبي عائلية", "price_usd": 38, "desc_en": "21 Crispy Chicken Pieces Regular or Spicy Served with Fries Box, 3 Coleslaw, 2 Garlic Mayo, 2 Cheddar Sauce, 4 Buns, & 1.25L Pepsi", "desc_ar": "٢١ قطعة دجاج كرسبي عادي أو حار مع علبة بطاطا، ٣ كول سلو، ٢ مايونيز بالثوم، ٢ صوص شيدر، ٤ خبزات وبيبسي ١.٢٥ ليتر"}, {"name_en": "Wings Giant Meal", "name_ar": "وجبة الجوانح الكبيرة", "price_usd": 19, "desc_en": "30 Pieces of Crunchy Wings Served with Fries, Garlic Mayo, Honey Mustard, Barbecue, Buffalo Sauce, & 1.25L Pepsi", "desc_ar": "٣٠ قطعة جوانح مقرمشة مع بطاطا، مايونيز بالثوم، هني ماستارد، باربكيو، صوص بافالو وبيبسي ١.٢٥ ليتر"}, {"name_en": "Trio Boneless Meal", "name_ar": "وجبة تريو بونلس", "price_usd": 8, "desc_en": "3 Special Mini Crispy Chicken Wraps Served with a Soft Drink", "desc_ar": "٣ رابات كرسبي صغيرة مميزة مع مشروب غازي"}, {"name_en": "Kids Meal", "name_ar": "وجبة أطفال", "price_usd": 6, "desc_en": "2 Crispy Chicken & 3 Nuggets Pieces, Bundled with Fries, Surprise Gift, & a Juice", "desc_ar": "٢ قطعة كرسبي و٣ قطع ناغتس مع بطاطا، هدية مفاجأة وعصير"}]}, {"name_en": "Loaded Fries", "name_ar": "بطاطا محمّلة", "items": [{"name_en": "Topped Fries", "name_ar": "بطاطا توبد", "price_usd": 6, "desc_en": "Fries Topped with Melted Cheddar & R66 Sauce & Your Choice of Jalapeños or Dill Pickles", "desc_ar": "بطاطا مع شيدر ذايب وصوص R66 وعلى اختيارك هالابينو أو مخلل"}, {"name_en": "Loaded Black Angus", "name_ar": "لوديد بلاك أنغوس", "price_usd": 9, "desc_en": "Fries Drizzled with Mayo Barbecue, R66 Sauce, Topped with Black Angus Beef, Grilled Onions, Melted Cheddar & Your Choice of Jalapeños or Dill Pickles", "desc_ar": "بطاطا مع مايو باربكيو وصوص R66، لحم بلاك أنغوس، بصل مشوي، شيدر ذايب وعلى اختيارك هالابينو أو مخلل"}, {"name_en": "Loaded Crispy Chicken", "name_ar": "لوديد دجاج كرسبي", "price_usd": 8, "desc_en": "Fries Topped with Herbal Mayo, Crispy Chicken, Turkey Bacon, Melted Cheddar & Barbecue Sauce Crowned with Your Choice of Jalapeños or Dill Pickles", "desc_ar": "بطاطا مع مايونيز بالأعشاب، دجاج كرسبي، بيكن حبش، شيدر ذايب وصوص باربكيو وعلى اختيارك هالابينو أو مخلل"}, {"name_en": "Loaded Grilled Chicken", "name_ar": "لوديد دجاج مشوي", "price_usd": 8, "desc_en": "Fries Drizzled with Honey Mustard & Garlic Mayo Sauces, Topped with Grilled Chicken Infused with 6 Cheeses & Grilled Pepper, Sprinkled with Chips Sticks", "desc_ar": "بطاطا مع هني ماستارد ومايونيز بالثوم، دجاج مشوي بـ٦ أنواع جبنة وفليفلة مشوية، ورشّة أصابع شيبس"}]}, {"name_en": "Salads", "name_ar": "سلطات", "items": [{"name_en": "Chicken Caesar", "name_ar": "سيزر بالدجاج", "price_usd": 8, "desc_en": "Fresh Lettuce, Grilled Chicken, Crunchy Croutons, Parmesan, & Creamy Caesar Dressing", "desc_ar": "خس طازة، دجاج مشوي، خبز محمّص، بارميزان وصلصة سيزر كريمية"}, {"name_en": "Caesar", "name_ar": "سيزر", "price_usd": 6, "desc_en": "Fresh Lettuce, Golden Croutons, Parmesan, & Creamy Caesar Dressing", "desc_ar": "خس طازة، خبز محمّص، بارميزان وصلصة سيزر كريمية"}, {"name_en": "Coleslaw", "name_ar": "كول سلو", "price_usd": 2, "desc_en": "Fresh Blend of Cabbage & Carrots Mixed With Our Smooth Dressing", "desc_ar": "ملفوف وجزر طازة مع صلصتنا الناعمة"}]}, {"name_en": "Side Cups", "name_ar": "كاسات جانبية", "items": [{"name_en": "Dill Pickles", "name_ar": "مخلل خيار", "price_usd": 0.8, "desc_en": "", "desc_ar": ""}, {"name_en": "Jalapeños", "name_ar": "هالابينو", "price_usd": 0.8, "desc_en": "", "desc_ar": ""}, {"name_en": "Cheddar Sauce", "name_ar": "صوص شيدر", "price_usd": 1, "desc_en": "", "desc_ar": ""}, {"name_en": "R66 Sauce", "name_ar": "صوص R66", "price_usd": 1, "desc_en": "", "desc_ar": ""}, {"name_en": "Herbal Mayo Sauce", "name_ar": "مايونيز بالأعشاب", "price_usd": 1, "desc_en": "", "desc_ar": ""}, {"name_en": "Garlic Mayo Sauce", "name_ar": "مايونيز بالثوم", "price_usd": 1, "desc_en": "", "desc_ar": ""}, {"name_en": "Honey Mustard Sauce", "name_ar": "صوص هني ماستارد", "price_usd": 1, "desc_en": "", "desc_ar": ""}, {"name_en": "Mayo Barbecue Sauce", "name_ar": "صوص مايو باربكيو", "price_usd": 1, "desc_en": "", "desc_ar": ""}, {"name_en": "Cocktail Sauce", "name_ar": "صوص كوكتيل", "price_usd": 1, "desc_en": "", "desc_ar": ""}, {"name_en": "Chili Sauce", "name_ar": "صوص حار", "price_usd": 1, "desc_en": "", "desc_ar": ""}]}, {"name_en": "Add Combo", "name_ar": "أضف كومبو", "items": [{"name_en": "Fries Cup & Soft Drink", "name_ar": "كاسة بطاطا ومشروب غازي", "price_usd": 3.5, "desc_en": "", "desc_ar": ""}]}, {"name_en": "Dessert", "name_ar": "حلويات", "items": [{"name_en": "Smiley", "name_ar": "سمايلي", "price_usd": 2.8, "desc_en": "Brownie Cubes Bathed with Chocolate & Strawberry Drizzle, Crowned with Fluffy Marshmallows", "desc_ar": "مكعبات براوني بالشوكولا والفريز مع مارشميلو"}]}, {"name_en": "Drinks", "name_ar": "مشروبات", "items": [{"name_en": "Mix 66", "name_ar": "ميكس 66", "price_usd": 2.5, "desc_en": "", "desc_ar": ""}, {"name_en": "Soft Drink", "name_ar": "مشروب غازي", "price_usd": 1.3, "desc_en": "", "desc_ar": ""}, {"name_en": "Ice Tea", "name_ar": "آيس تي", "price_usd": 1.3, "desc_en": "", "desc_ar": ""}, {"name_en": "Sparkling Water", "name_ar": "مياه غازية", "price_usd": 1.5, "desc_en": "", "desc_ar": ""}, {"name_en": "Juice", "name_ar": "عصير", "price_usd": 0.6, "desc_en": "", "desc_ar": ""}, {"name_en": "Water", "name_ar": "مياه", "price_usd": 0.5, "desc_en": "", "desc_ar": ""}]}]}$tpl$::jsonb)
on conflict (code) do update set name = excluded.name, data = excluded.data, updated_at = now();
