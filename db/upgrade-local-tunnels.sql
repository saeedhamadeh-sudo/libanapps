-- ============================================================
--  النسخة المحلية (LibanApps Local) — شغّلو مرة وحدة، آمن للتكرار
--
--  1) local_tunnels: روابط الوصول من برّا (shop1.libanapps.com + دومين الزبون الخاص).
--     الـWorker (route */*) بيشوف هالجدول: إذا الرابط إلو، بيمرّق الطلب للنفق
--     على كمبيوتر الزبون بدل ما يعرض الموقع الأونلاين.
--  2) app_export_secrets: لما الزبون ينقل بياناتو من السحابة للكمبيوتر، بتنقل كمان
--     كلمات سر المستخدمين وحسابات الزباين والعمال (مشفّرة متل ما هي) + أسرار 2FA،
--     فما بيحتاج يعيد تعيين ولا كلمة سر. بس للمدير (admin) يلي فايت بنفس الجلسة.
-- ============================================================

create table if not exists public.local_tunnels (
  hostname       text primary key,
  client_id      uuid references public.clients(id) on delete cascade,
  tunnel_id      text,
  kind           text not null default 'sub',      -- sub = shop1.libanapps.com · custom = دومين الزبون
  cf_hostname_id text,
  created_at     timestamptz not null default now()
);
create index if not exists local_tunnels_client_idx on public.local_tunnels (client_id);
alter table public.local_tunnels enable row level security;   -- بلا سياسات: الـWorker بس (service key)
revoke all on public.local_tunnels from anon, authenticated;

-- النفق اليدوي يلي عملناه للتجربة
insert into public.local_tunnels (hostname, kind) values ('itech.libanapps.com', 'sub')
on conflict (hostname) do nothing;

create or replace function public.app_export_secrets(p_product text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.app_sessions;
begin
  if p_product not in ('alum','trade') then raise exception 'bad product'; end if;
  s := public.app_cur(p_product);
  if s.sid is null or s.kind <> 'staff' or coalesce(s.role,'') not in ('admin','superuser') then
    return jsonb_build_object('ok', false, 'reason', 'not_allowed');
  end if;
  return jsonb_build_object('ok', true, 'rows', coalesce((
    select jsonb_agg(jsonb_build_object('tbl', x.tbl, 'id', x.id, 'password_hash', x.password_hash, 'totp_secret', x.totp_secret))
      from public.app_account_secrets x
     where x.client_id = s.client_id and left(x.tbl, length(p_product) + 1) = p_product || '_'
  ), '[]'::jsonb));
end $$;
revoke all on function public.app_export_secrets(text) from public, anon;
grant execute on function public.app_export_secrets(text) to authenticated;
