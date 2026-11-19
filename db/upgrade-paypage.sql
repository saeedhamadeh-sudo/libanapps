-- صفحة الدفع الخاصة بـLibanApps (/pay): رابط تجربة دفع لمرّة وحدة
alter table public.platform_settings add column if not exists pay_test_hash text;
alter table public.platform_settings add column if not exists pay_test_until timestamptz;
alter table public.platform_settings add column if not exists pay_test_amount numeric default 1;
