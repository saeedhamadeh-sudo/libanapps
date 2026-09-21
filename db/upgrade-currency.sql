-- ============================================================
--  ترقية: العملة الأساسية لكل مطعم
--  شغّله لحاله، أو شغّل schema.sql كامل — نفس النتيجة
--  لا يحذف أي بيانات
-- ============================================================

alter table public.restaurants add column if not exists base_currency text not null default 'USD';
do $$ begin
  alter table public.restaurants add constraint base_currency_chk
    check (base_currency in ('USD','LBP'));
exception when duplicate_object then null; end $$;

create or replace function public.get_order(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders%rowtype; r public.restaurants%rowtype;
begin
  select * into o from public.orders where token = p_token;
  if not found then raise exception 'not found'; end if;
  select * into r from public.restaurants where id = o.restaurant_id;
  return jsonb_build_object(
    'order', to_jsonb(o) - 'restaurant_id',
    'restaurant', jsonb_build_object('name_ar',r.name_ar,'name_en',r.name_en,'logo_url',r.logo_url,
                                     'phone',r.phone,'slug',r.slug,'theme',r.theme,
                                     'default_lang',r.default_lang,
                                     'base_currency',r.base_currency,
                                     'exchange_rate',r.exchange_rate),
    'items', coalesce((select jsonb_agg(to_jsonb(oi) - 'order_id' - 'id')
                       from public.order_items oi where oi.order_id = o.id), '[]'::jsonb)
  );
end $$;
