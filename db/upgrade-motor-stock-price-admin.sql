-- المدير (فاديا) كمان بيحدد سعر صنف المخزون — شيل قفل السعر من motor_stock_save
do $$
declare d text;
begin
  select pg_get_functiondef('public.motor_stock_save(text,text,jsonb)'::regprocedure) into d;
  if position('price_lock' in d) > 0 then
    d := regexp_replace(d, E'  if not coalesce\\(\\(w->>''is_main''\\)::boolean, false\\) then   -- price_lock[^\\n]*\\n[^\\n]*\\n  end if;\\n', '');
    if position('price_lock' in d) > 0 then raise exception 'unpatch failed'; end if;
    execute d;
  end if;
end $$;
