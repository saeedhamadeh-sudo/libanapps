-- المدير بيسجّل العداد بلا سعر شهر: الفاتورة بتنحسب مؤقتاً وبتتعدّل لحالها لما ينحدد سعر الشهر،
-- ورسالة قيمة الفاتورة بتنبعت تلقائياً بعد التسعير (متل عدادات الموظفين)
do $$
declare d text;
begin
  select pg_get_functiondef('public.motor_read(text,text,uuid,numeric,text,double precision,double precision,double precision,boolean,numeric,boolean)'::regprocedure) into d;
  if position('price_required' in d) > 0 then
    d := replace(d, 'if mp is null then perform public._motor_err(''price_required''); end if;
    p_price := mp;', 'if mp is not null then p_price := mp; end if;');
    execute d;
  end if;
end $$;
