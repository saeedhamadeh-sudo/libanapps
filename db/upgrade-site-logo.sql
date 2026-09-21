-- ============================================================
--  ترقية: شعار الموقع
--  بترفعه من لوحتك وبيظهر مكان اسم LibanApps بكل الصفحات
-- ============================================================

alter table public.platform_settings add column if not exists logo_url text default '';

create or replace function public.public_settings()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'brand_name', s.brand_name, 'logo_url', s.logo_url,
    'whatsapp', s.whatsapp, 'phone', s.phone,
    'email', s.email, 'address', s.address,
    'facebook', s.facebook, 'instagram', s.instagram,
    'whish_enabled', s.whish_enabled, 'trial_days', s.trial_days
  ) from public.platform_settings s where s.id = 1;
$$;
