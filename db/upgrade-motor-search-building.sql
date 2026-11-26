-- البحث بالزبائن حسب اسم البناية/العنوان: لائحة الزبائن بترجّع building و address
do $$
declare d text;
begin
  select pg_get_functiondef('public._motor_cust_rows(uuid,uuid,timestamptz)'::regprocedure) into d;
  if position('''building''' in d) = 0 then
    d := replace(d, '''location_name'', c.location_name,', '''location_name'', c.location_name, ''building'', c.building, ''address'', c.address,');
    if position('''building''' in d) = 0 then raise exception 'patch'; end if;
    execute d;
  end if;
end $$;
