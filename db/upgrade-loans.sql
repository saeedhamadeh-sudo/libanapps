-- القروض (برنامج التجارة + برنامج الصناعيين): كل سطر = قرض (kind='loan') أو دفعة عليه (kind='repay', loan_id)
do $$
declare p text;
begin
  foreach p in array array['trade','alum'] loop
    execute format($f$
      create table if not exists public.%I (
        id text primary key,
        client_id uuid not null references public.clients(id) on delete cascade,
        kind text not null default 'loan',
        loan_id text,
        lender text,
        amount numeric default 0,
        date date,
        number text,
        note text,
        extra jsonb,
        created_at bigint default 0,
        deleted boolean default false,
        deleted_at bigint
      )$f$, p||'_loans');
    execute format('create index if not exists %I on public.%I (client_id)', p||'_loans_cid', p||'_loans');
    execute format('alter table public.%I enable row level security', p||'_loans');
    execute format('drop policy if exists %I on public.%I', p||'_loans_rw', p||'_loans');
    execute format('create policy %I on public.%I for all using (owns(client_id)) with check (owns(client_id))', p||'_loans_rw', p||'_loans');
    execute format('drop policy if exists gate_sel on public.%I', p||'_loans');
    execute format('drop policy if exists gate_ins on public.%I', p||'_loans');
    execute format('drop policy if exists gate_upd on public.%I', p||'_loans');
    execute format('drop policy if exists gate_del on public.%I', p||'_loans');
    execute format('create policy gate_sel on public.%I as restrictive for select to authenticated using (public.app_can_read(%L, client_id, jsonb_build_object(''id'', id)))', p||'_loans', p||'_loans');
    execute format('create policy gate_ins on public.%I as restrictive for insert to authenticated with check (public.app_can_write(%L, client_id))', p||'_loans', p||'_loans');
    execute format('create policy gate_upd on public.%I as restrictive for update to authenticated using (public.app_can_write(%L, client_id)) with check (public.app_can_write(%L, client_id))', p||'_loans', p||'_loans', p||'_loans');
    execute format('create policy gate_del on public.%I as restrictive for delete to authenticated using (public.app_can_write(%L, client_id))', p||'_loans', p||'_loans');
  end loop;
end $$;

-- صلاحية «الميزانية» بتشمل القروض
create or replace function public.app_perm_tables(p_product text, p_perm text)
returns text[] language sql immutable as $$
  select case p_product
    when 'alum' then case p_perm
      when 'customers'  then array['customers','invoices','receipts']
      when 'suppliers'  then array['suppliers','purchase_invoices','payment_vouchers']
      when 'workers'    then array['workers','work_entries','worker_payments']
      when 'deductions' then array['deductions']
      when 'quotes'     then array['quotes']
      when 'warehouse'  then array['warehouse_items','stock_ins','stock_outs']
      when 'orders'     then array['cutting_orders']
      when 'budget'     then array['budget_categories','budget_entries','loans']
      else array[]::text[] end
    when 'trade' then case p_perm
      when 'pos'        then array['customers','invoices','receipts','stock_outs','stock_ins','cash_movements','cashier_shifts']
      when 'customers'  then array['customers','invoices','receipts','stock_outs']
      when 'suppliers'  then array['suppliers','purchase_invoices','payment_vouchers']
      when 'warehouse'  then array['warehouse_items','stock_ins','stock_outs']
      when 'budget'     then array['budget_categories','budget_entries','loans']
      when 'workers'    then array['workers','work_entries','worker_payments']
      else array[]::text[] end
    else array[]::text[] end;
$$;
