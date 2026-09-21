-- ============================================================
--  ترقية: الزبون يشوف اشتراكاته حتى لو فعّلتها أنت يدوياً
--  شغّله لحاله — لا يحذف أي بيانات
-- ============================================================

-- ---------- 1) اشتراكاتي (من الاشتراكات مباشرة، مش من المشتريات) ----------
create or replace function public.my_licenses()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'expires_at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id',          s.id,
      'product',     s.product_code,
      'product_name',p.name_ar,
      'plan',        s.plan,
      'key',         s.key,
      'status',      s.status,
      'slug',        s.ref_slug,
      'expires_at',  s.expires_at,
      'days_left',   greatest(0, ceil(extract(epoch from (s.expires_at - now()))/86400))::int,
      'active',      (s.status = 'active' and s.expires_at > now()),
      'device_bound',(s.device_id is not null)
    ) as x
    from public.subscriptions s
    join public.products p on p.code = s.product_code
    where s.client_id in (select c.id from public.clients c where c.user_id = auth.uid())
  ) t;
$$;

-- ---------- 2) مطاعمي (لو الربط صار عبر restaurant_users فقط) ----------
create or replace function public.my_restaurants()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'slug', r.slug, 'name_ar', r.name_ar,
    'days_left', greatest(0, ceil(extract(epoch from (public.license_until(r.id) - now()))/86400))::int,
    'active', public.license_until(r.id) > now()
  )), '[]'::jsonb)
  from public.restaurants r
  join public.restaurant_users ru on ru.restaurant_id = r.id
  where ru.user_id = auth.uid();
$$;

-- ---------- 3) ربط زبون موجود بحساب دخول (من لوحتك) ----------
create or replace function public.link_client_user(p_client uuid, p_email text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  select id into uid from auth.users where lower(email) = lower(trim(p_email)) limit 1;
  if uid is null then
    return jsonb_build_object('ok', false, 'reason', 'ما في حساب بهذا الإيميل');
  end if;
  update public.clients set user_id = uid where id = p_client;
  return jsonb_build_object('ok', true, 'user_id', uid);
end $$;

-- ---------- 4) ربط تلقائي بالإيميل لمن لم يُربط بعد ----------
--  يفيد للزبائن القدامى: إذا إيميل الحساب يطابق إيميل مخزّن عندك
create or replace function public.autolink_my_client()
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid; myemail text;
begin
  if auth.uid() is null then return null; end if;
  select id into cid from public.clients where user_id = auth.uid();
  if cid is not null then return cid; end if;

  select lower(email) into myemail from auth.users where id = auth.uid();

  -- الزبون الذي يملك مطعماً هذا المستخدم عضو فيه
  select c.id into cid
    from public.clients c
    join public.restaurants r on r.client_id = c.id
    join public.restaurant_users ru on ru.restaurant_id = r.id
   where ru.user_id = auth.uid() and c.user_id is null
   limit 1;

  if cid is not null then
    update public.clients set user_id = auth.uid() where id = cid;
  end if;
  return cid;
end $$;
