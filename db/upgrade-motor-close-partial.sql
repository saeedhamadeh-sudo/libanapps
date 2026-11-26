-- استلام من الجابي بمبلغ يحددو المدير: الباقي بيضل بصندوق الجابي (فراطة يرد فيها للعالم)
do $$
declare d text;
begin
  select pg_get_functiondef('public.motor_staff_close(text,text,uuid)'::regprocedure) into d;
  d := replace(d, 'p_staff uuid DEFAULT NULL::uuid)', 'p_staff uuid DEFAULT NULL::uuid, p_amount numeric DEFAULT NULL::numeric)');
  d := replace(d, 'cid uuid := gen_random_uuid();', 'cid uuid := gen_random_uuid(); boxv numeric;');
  d := replace(d, E'  rep := jsonb_build_object(\n',
    E'  boxv := hand;\n  if p_amount is not null then\n    if p_amount <= 0 or round(p_amount,2) > round(hand,2) then perform public._motor_err(''bad_amount'', hand::text); end if;\n    hand := round(p_amount, 2);\n  end if;\n  rep := jsonb_build_object(\n');
  d := replace(d, E'''handed'', hand,', E'''handed'', hand, ''box'', boxv, ''kept'', boxv - hand,');
  if position('p_amount' in d) = 0 or position('''kept''' in d) = 0 or position('boxv := hand' in d) = 0 then raise exception 'patch failed'; end if;
  drop function public.motor_staff_close(text,text,uuid);
  execute d;
  revoke all on function public.motor_staff_close(text,text,uuid,numeric) from public;
  grant execute on function public.motor_staff_close(text,text,uuid,numeric) to anon, authenticated, service_role;
end $$;
