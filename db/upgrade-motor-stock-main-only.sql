-- المخزون والموردون للمدير الأساسي بس. المدير (غير الأساسي) بيفوتر من المخزون بس، وبالأسعار يلي حاططها المدير الأساسي
create or replace function public._motor_sale_lock(p_sid uuid, p_items jsonb, p_sale uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare x jsonb; s public.motor_stock%rowtype; pr numeric; out jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_items) <> 'array' then return p_items; end if;
  for x in select * from jsonb_array_elements(p_items) loop
    if coalesce(x->>'stock_id','') = '' then perform public._motor_err('stock_only'); end if;
    select * into s from public.motor_stock where id = (x->>'stock_id')::uuid and site_id = p_sid;
    if not found then perform public._motor_err('bad_data'); end if;
    pr := null;
    if p_sale is not null then
      select (it->>'price')::numeric into pr from public.motor_invoices i, jsonb_array_elements(i.items) it
       where i.id = p_sale and i.site_id = p_sid and it->>'stock_id' = s.id::text limit 1;
    end if;
    out := out || jsonb_build_array(x || jsonb_build_object('name', s.name, 'price', coalesce(pr, s.unit_price, 0)));
  end loop;
  return out;
end $$;
revoke all on function public._motor_sale_lock(uuid,jsonb,uuid) from public, anon, authenticated;

do $$
declare d text; f text;
begin
  -- البيع والمرتجع: غير الأساسي بيتقفل على أصناف المخزون وأسعارها
  select pg_get_functiondef('public.motor_sale_add(text,text,uuid,jsonb,text)'::regprocedure) into d;
  if position('_motor_sale_lock' in d) = 0 then
    d := replace(d, E'  sid := (w->>''site_id'')::uuid;\n  select * into c',
      E'  sid := (w->>''site_id'')::uuid;\n  if not coalesce((w->>''is_main'')::boolean, false) then p_items := public._motor_sale_lock(sid, p_items); end if;\n  select * into c');
    if position('_motor_sale_lock' in d) = 0 then raise exception 'sale_add patch'; end if;
    execute d;
  end if;
  select pg_get_functiondef('public.motor_sale_return(text,text,uuid,jsonb,text,uuid)'::regprocedure) into d;
  if position('_motor_sale_lock' in d) = 0 then
    d := replace(d, E'  sid := (w->>''site_id'')::uuid;\n  select * into c',
      E'  sid := (w->>''site_id'')::uuid;\n  if not coalesce((w->>''is_main'')::boolean, false) then p_items := public._motor_sale_lock(sid, p_items, p_sale); end if;\n  select * into c');
    if position('_motor_sale_lock' in d) = 0 then raise exception 'sale_return patch'; end if;
    execute d;
  end if;
  -- إدارة المخزون والمشتريات والموردين: المدير الأساسي بس
  for f in select p.oid::regprocedure::text from pg_proc p where p.pronamespace = 'public'::regnamespace
             and p.proname in ('motor_stock_save','motor_stock_delete','motor_stock_out','motor_stock_moves_list',
                               'motor_purchase_add','motor_purchase_edit','motor_purchase_get','motor_purchase_void',
                               'motor_supplier_save','motor_supplier_delete','motor_supplier_pay','motor_supplier_statement','motor_suppliers') loop
    d := pg_get_functiondef(f::regprocedure);
    if position('_motor_admin(p_slug, p_token)' in d) > 0 then
      d := replace(d, 'public._motor_admin(p_slug, p_token)', 'public._motor_main(p_slug, p_token)');
      execute d;
    end if;
  end loop;
end $$;
