-- حد واتساب اليومي لكل موقع (wa_limit) — رسائل قيمة الفاتورة بتوقف عند wa_limit − wa_reserve
-- وبيضل wa_reserve (25) لإيصالات الدفع. لما يرتفع الحد لـ2000: update motor_sites set wa_limit = 2000 where slug = '...';
alter table public.motor_sites add column if not exists wa_limit integer not null default 250;
alter table public.motor_sites add column if not exists wa_reserve integer not null default 25;

do $$
declare d text;
begin
  select pg_get_functiondef('public.motor_wa_quota(uuid,text,integer)'::regprocedure) into d;
  if position('wa_limit' in d) = 0 then
    d := replace(d, E'perform pg_advisory_xact_lock(hashtext(''motor_wa_'' || p_site::text));',
      E'perform pg_advisory_xact_lock(hashtext(''motor_wa_'' || p_site::text));\n  if coalesce(p_limit, 250) = 250 then p_limit := coalesce((select wa_limit from public.motor_sites where id = p_site), 250); end if;');
    if position('wa_limit' in d) = 0 then raise exception 'q patch'; end if;
    execute d;
  end if;
  select pg_get_functiondef('public.motor_inv_wa_claim(integer)'::regprocedure) into d;
  if position('wa_reserve' in d) = 0 then
    d := replace(d, 'select s.id, s.name, s.currency, s.wc_api_key from public.motor_sites s', 'select s.id, s.name, s.currency, s.wc_api_key, s.wa_limit, s.wa_reserve from public.motor_sites s');
    d := replace(d, 'q := public.motor_wa_quota(st.id, num, 250);', 'q := public.motor_wa_quota(st.id, num, greatest(st.wa_limit - st.wa_reserve, 1));');
    if position('wa_reserve' in d) = 0 or position('greatest(st.wa_limit' in d) = 0 then raise exception 'i patch'; end if;
    execute d;
  end if;
end $$;
