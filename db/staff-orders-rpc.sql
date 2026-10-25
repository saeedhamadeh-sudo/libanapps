-- ============================================================
--  Staff Orders RPCs — for the /orders.html staff page
--  Accessible with anon key, scoped to restaurant by slug
--  Allows: list pending+recent orders, accept, reject, clear old
-- ============================================================

-- RPC: staff_get_orders(p_slug text)
-- Returns the last 60 orders for a restaurant (by slug)
-- including pending, accepted, rejected from last 24h
drop function if exists public.staff_get_orders(text);
create or replace function public.staff_get_orders(p_slug text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  rid uuid;
  rows jsonb;
begin
  select id into rid from public.restaurants where slug=p_slug;
  if rid is null then return '[]'::jsonb; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',            o.id,
    'order_no',      o.order_no,
    'customer_name', o.customer_name,
    'customer_phone',o.customer_phone,
    'order_type',    o.order_type,
    'total_usd',     o.total_usd,
    'status',        o.status,
    'created_at',    o.created_at
  ) order by o.created_at desc),'[]'::jsonb)
  into rows
  from public.orders o
  where o.restaurant_id=rid
    and o.created_at > now() - interval '24 hours'
    and o.status in ('pending','accepted','rejected');

  return rows;
end $$;

-- RPC: staff_accept_order(p_slug text, p_order_id bigint)
drop function if exists public.staff_accept_order(text, bigint);
create or replace function public.staff_accept_order(p_slug text, p_order_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  rid uuid;
  otype text;
begin
  select id into rid from public.restaurants where slug=p_slug;
  if rid is null then return '{"ok":false,"error":"not found"}'::jsonb; end if;

  select order_type into otype from public.orders
    where id=p_order_id and restaurant_id=rid and status='pending';
  if not found then return '{"ok":false,"error":"order not found or not pending"}'::jsonb; end if;

  if otype='delivery' then
    update public.orders set status='accepted', dispatch='waiting'
      where id=p_order_id and restaurant_id=rid;
  else
    update public.orders set status='accepted'
      where id=p_order_id and restaurant_id=rid;
  end if;

  return '{"ok":true}'::jsonb;
end $$;

-- RPC: staff_reject_order(p_slug text, p_order_id bigint, p_reason text)
drop function if exists public.staff_reject_order(text, bigint, text);
create or replace function public.staff_reject_order(p_slug text, p_order_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  rid uuid;
begin
  select id into rid from public.restaurants where slug=p_slug;
  if rid is null then return '{"ok":false,"error":"not found"}'::jsonb; end if;

  update public.orders
    set status='rejected', reject_reason=p_reason
    where id=p_order_id and restaurant_id=rid and status='pending';

  if not found then return '{"ok":false,"error":"order not found or not pending"}'::jsonb; end if;

  return '{"ok":true}'::jsonb;
end $$;

-- RPC: staff_clear_orders(p_slug text)
-- Permanently deletes accepted/rejected orders for a restaurant (keeps pending)
drop function if exists public.staff_clear_orders(text);
create or replace function public.staff_clear_orders(p_slug text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  rid uuid;
  deleted_count integer;
begin
  select id into rid from public.restaurants where slug=p_slug;
  if rid is null then return '{"ok":false,"error":"not found"}'::jsonb; end if;

  delete from public.orders
    where restaurant_id=rid
      and status in ('accepted','rejected','cancelled');
  get diagnostics deleted_count = row_count;

  return jsonb_build_object('ok',true,'deleted',deleted_count);
end $$;

-- Grant execute to anon role so the staff page (using anon key) can call them
grant execute on function public.staff_get_orders(text)           to anon;
grant execute on function public.staff_accept_order(text, bigint) to anon;
grant execute on function public.staff_reject_order(text, bigint, text) to anon;
grant execute on function public.staff_clear_orders(text)         to anon;
