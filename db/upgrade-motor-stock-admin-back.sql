-- المخزون رجع للمدير كمان (فاديا) — بس السعر بيحدّدو المدير الأساسي وحدو. الموردون والمشتريات بيضلّوا للأساسي.
do $$
declare d text; f text;
begin
  for f in select p.oid::regprocedure::text from pg_proc p where p.pronamespace = 'public'::regnamespace
             and p.proname in ('motor_stock_save','motor_stock_delete','motor_stock_out','motor_stock_moves_list') loop
    d := pg_get_functiondef(f::regprocedure);
    d := replace(d, 'public._motor_main(p_slug, p_token)', 'public._motor_admin(p_slug, p_token)');
    if f like 'motor_stock_save%' and position('price_lock' in d) = 0 then
      d := replace(d, E'  sid := (w->>''site_id'')::uuid;\n',
        E'  sid := (w->>''site_id'')::uuid;\n  if not coalesce((w->>''is_main'')::boolean, false) then   -- price_lock: السعر للمدير الأساسي بس\n    d := (d - ''unit_price'') || jsonb_build_object(''unit_price'', coalesce((select unit_price from public.motor_stock where id = nullif(d->>''id'','''')::uuid and site_id = sid), 0));\n  end if;\n');
      if position('price_lock' in d) = 0 then raise exception 'save patch'; end if;
    end if;
    execute d;
  end loop;
end $$;
