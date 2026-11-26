-- «نقدي اليوم»: المدير الأساسي بيكتب رقم بإيدو (لليوم بس) — للعرض فقط، ما بيغيّر إيصالات ولا صناديق
create table if not exists public.motor_cash_today_fix (
  site_id uuid not null references public.motor_sites(id) on delete cascade,
  day date not null,
  amount numeric not null,
  by_name text not null default '',
  at timestamptz not null default now(),
  primary key (site_id, day)
);
alter table public.motor_cash_today_fix enable row level security;

create or replace function public.motor_cash_today_set(p_slug text, p_token text, p_amount numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare w jsonb; sid uuid; d date := public._motor_today();
begin
  w := public._motor_main(p_slug, p_token); sid := (w->>'site_id')::uuid;
  if p_amount is null then
    delete from public.motor_cash_today_fix where site_id = sid and day = d;
  else
    if p_amount < 0 or p_amount > 10000000 then perform public._motor_err('bad_amount'); end if;
    insert into public.motor_cash_today_fix (site_id, day, amount, by_name) values (sid, d, round(p_amount,2), w->>'name')
    on conflict (site_id, day) do update set amount = excluded.amount, by_name = excluded.by_name, at = now();
  end if;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.motor_cash_today_set(text,text,numeric) from public;
grant execute on function public.motor_cash_today_set(text,text,numeric) to anon, authenticated;

do $$
declare d text;
begin
  select pg_get_functiondef('public.motor_dashboard(text,text)'::regprocedure) into d;
  if position('motor_cash_today_fix' in d) = 0 then
    d := replace(d, E'    ''cash_today'', coalesce((select sum(amount) from public.motor_payments where site_id = sid and method = ''cash'' and not voided\n                     and (created_at at time zone ''Asia/Beirut'')::date = today and (not mine or staff_id = me)), 0),',
      E'    ''cash_today'', coalesce(case when not mine then (select f.amount from public.motor_cash_today_fix f where f.site_id = sid and f.day = today) end,\n                     (select sum(amount) from public.motor_payments where site_id = sid and method = ''cash'' and not voided\n                     and (created_at at time zone ''Asia/Beirut'')::date = today and (not mine or staff_id = me)), 0),\n    ''cash_today_fixed'', (not mine and exists (select 1 from public.motor_cash_today_fix f where f.site_id = sid and f.day = today)),\n    ''cash_today_real'', coalesce((select sum(amount) from public.motor_payments where site_id = sid and method = ''cash'' and not voided\n                     and (created_at at time zone ''Asia/Beirut'')::date = today and (not mine or staff_id = me)), 0),');
    if position('motor_cash_today_fix' in d) = 0 then raise exception 'dash patch'; end if;
    execute d;
  end if;
end $$;
