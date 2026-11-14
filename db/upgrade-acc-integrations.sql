-- برامج المحاسبة (تجارة / صناعيين): Google Drive + WhatChimp — مفاتيح محفوظة عالسيرفر بس
create table if not exists public.acc_integrations (
  client_id uuid not null,
  product text not null,
  key_hash text not null,
  wc_api_key text,
  wc_label text,
  gd_refresh text,
  gd_email text,
  gd_folder text,
  gd_last_at timestamptz,
  gd_last_err text,
  updated_at timestamptz not null default now(),
  primary key (client_id, product)
);
alter table public.acc_integrations enable row level security;
revoke all on public.acc_integrations from anon, authenticated;
alter table public.trade_app_settings add column if not exists int_key text;
alter table public.alum_app_settings add column if not exists int_key text;
