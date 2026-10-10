-- ============================================================
--  الوضع الآمن لبرنامجي المحاسبة (alum / trade)
--
--  قبل: كل من يملك رابط المؤسسة يستطيع قراءة وتعديل كل بياناتها (وكلمات
--  سر المستخدمين) من المتصفح، لأن تسجيل دخول اليوزر الداخلي كان في المتصفح فقط.
--
--  بعد (للمؤسسات التي يُفعَّل لها «الوضع الآمن» من لوحة /super):
--   · تسجيل الدخول الداخلي يتم في قاعدة البيانات (app_login) — كلمات السر مشفّرة
--     و2FA يُتحقَّق منه هنا، مع حدّ لمحاولات الدخول الخاطئة.
--   · لا تُقرأ بيانات المؤسسة قبل تسجيل الدخول.
--   · الزبون يرى حسابه فقط، والعامل يومياته ودفعاته فقط.
--   · المستخدم المخصّص يكتب فقط في أقسام صلاحياته.
--   · كلمات السر وأسرار 2FA لا تُقرأ من المتصفح أبداً.
--
--  المؤسسات غير المفعّل لها الوضع الآمن تبقى كما هي تماماً.
--  شغّله مرة واحدة على مشروع LibanApps — آمن للتكرار.
-- ============================================================
create extension if not exists pgcrypto;   -- في Supabase موجودة في مخطط extensions

-- ---------- 1) مفتاح الوضع الآمن لكل مؤسسة ----------
alter table public.clients add column if not exists secure_apps boolean not null default false;

create or replace function public.app_secure(cid uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select secure_apps from public.clients where id = cid), false);
$$;

-- ---------- 2) جلسات الدخول الداخلي (مربوطة بجلسة Supabase في هذا المتصفح) ----------
create table if not exists public.app_sessions (
  sid         uuid not null,              -- session_id من رمز Supabase
  product     text not null,              -- alum / trade
  uid         uuid not null,
  client_id   uuid not null references public.clients(id) on delete cascade,
  kind        text not null,              -- staff / customer / worker
  account_id  text not null,
  role        text,
  perms       text[] not null default '{}',
  customer_id text,
  worker_id   text,
  created_at  timestamptz not null default now(),
  primary key (sid, product)
);
alter table public.app_sessions enable row level security;   -- بلا سياسات: عبر الدوال فقط

create table if not exists public.app_login_attempts (
  client_id uuid not null,
  product   text not null,
  username  text not null,
  at        timestamptz not null default now()
);
create index if not exists app_login_attempts_idx on public.app_login_attempts (client_id, product, username, at);
alter table public.app_login_attempts enable row level security;

create or replace function public.app_sid()
returns uuid language sql stable as $$
  select nullif(auth.jwt()->>'session_id','')::uuid;
$$;

create or replace function public.app_cur(p_product text)
returns public.app_sessions language sql stable security definer set search_path = public, extensions as $$
  select * from public.app_sessions
   where sid = public.app_sid() and product = p_product and uid = auth.uid()
   limit 1;
$$;

-- ---------- 3) قواعد الصلاحيات ----------
--  ما يكتبه المستخدم المخصّص حسب صلاحياته (أسماء الجداول بدون البادئة)
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
      when 'budget'     then array['budget_categories','budget_entries']
      else array[]::text[] end
    when 'trade' then case p_perm
      when 'pos'        then array['customers','invoices','receipts','stock_outs','stock_ins','cash_movements','cashier_shifts']
      when 'customers'  then array['customers','invoices','receipts','stock_outs']
      when 'suppliers'  then array['suppliers','purchase_invoices','payment_vouchers']
      when 'warehouse'  then array['warehouse_items','stock_ins','stock_outs']
      when 'budget'     then array['budget_categories','budget_entries']
      when 'workers'    then array['workers','work_entries','worker_payments']
      else array[]::text[] end
    else array[]::text[] end;
$$;

--  هل يُسمح بقراءة هذا السطر؟  p_tbl مثل 'alum_invoices'، p_row فيه id / customer_id / worker_id
create or replace function public.app_can_read(p_tbl text, p_cid uuid, p_row jsonb)
returns boolean language plpgsql stable security definer set search_path = public, extensions as $$
declare prod text := split_part(p_tbl, '_', 1);
        t    text := substr(p_tbl, length(split_part(p_tbl, '_', 1)) + 2);
        s    public.app_sessions;
begin
  if public.is_admin() then return true; end if;
  if not public.app_secure(p_cid) then return true; end if;
  if t = 'app_settings' then return true; end if;            -- الاسم والشعار لشاشة الدخول
  s := public.app_cur(prod);
  if s.sid is null or s.client_id <> p_cid then return false; end if;
  if s.kind = 'staff' then
    if t in ('app_users','customer_accounts','worker_accounts') then
      return s.role in ('admin','superuser') or (t = 'app_users' and p_row->>'id' = s.account_id);
    end if;
    return true;
  elsif s.kind = 'customer' then
    return (t = 'customers' and p_row->>'id' = s.customer_id)
        or (t in ('invoices','receipts') and p_row->>'customer_id' = s.customer_id);
  elsif s.kind = 'worker' then
    return (t = 'workers' and p_row->>'id' = s.worker_id)
        or (t in ('work_entries','worker_payments') and p_row->>'worker_id' = s.worker_id);
  end if;
  return false;
end $$;

create or replace function public.app_can_write(p_tbl text, p_cid uuid)
returns boolean language plpgsql stable security definer set search_path = public, extensions as $$
declare prod text := split_part(p_tbl, '_', 1);
        t    text := substr(p_tbl, length(split_part(p_tbl, '_', 1)) + 2);
        s    public.app_sessions; p text;
begin
  if public.is_admin() then return true; end if;
  if not public.app_secure(p_cid) then return true; end if;
  s := public.app_cur(prod);
  if s.sid is null or s.client_id <> p_cid or s.kind <> 'staff' then return false; end if;
  if s.role in ('admin','superuser') then return true; end if;
  if t in ('app_users','customer_accounts','worker_accounts','day_closures') then return false; end if;
  if t in ('app_settings','budget_categories') then return true; end if;   -- خيارات القوائم وحقول الميزانية
  foreach p in array s.perms loop
    if t = any(public.app_perm_tables(prod, p)) then return true; end if;
  end loop;
  return false;
end $$;

-- ---------- 4) سياسات تقييدية على كل جداول البرنامجين ----------
--  (تُضاف فوق سياسة owns(client_id) الموجودة — لا تستبدلها)
do $$
declare r record; rowexpr text; cols text;
begin
  for r in select c.relname as tbl from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r'
              and (c.relname like 'alum\_%' or c.relname like 'trade\_%')
              and exists (select 1 from information_schema.columns
                           where table_schema='public' and table_name=c.relname and column_name='client_id')
  loop
    select string_agg(format('%L, %I', column_name, column_name), ', ') into cols
      from information_schema.columns
     where table_schema='public' and table_name=r.tbl and column_name in ('id','customer_id','worker_id');
    rowexpr := format('jsonb_build_object(%s)', coalesce(cols, ''));
    execute format('drop policy if exists gate_sel on public.%I', r.tbl);
    execute format('drop policy if exists gate_ins on public.%I', r.tbl);
    execute format('drop policy if exists gate_upd on public.%I', r.tbl);
    execute format('drop policy if exists gate_del on public.%I', r.tbl);
    execute format('create policy gate_sel on public.%I as restrictive for select to authenticated using (public.app_can_read(%L, client_id, %s))', r.tbl, r.tbl, rowexpr);
    execute format('create policy gate_ins on public.%I as restrictive for insert to authenticated with check (public.app_can_write(%L, client_id))', r.tbl, r.tbl);
    execute format('create policy gate_upd on public.%I as restrictive for update to authenticated using (public.app_can_write(%L, client_id)) with check (public.app_can_write(%L, client_id))', r.tbl, r.tbl, r.tbl);
    execute format('create policy gate_del on public.%I as restrictive for delete to authenticated using (public.app_can_write(%L, client_id))', r.tbl, r.tbl);
  end loop;
end $$;

-- ---------- 5) كلمات السر مشفّرة، وأسرار 2FA في جدول لا يصل إليه المتصفح ----------
--  البرنامج يكتب كلمة السر في عمود password كالعادة؛ المشغّل ينقل بصمتها (bcrypt)
--  وسر 2FA إلى app_account_secrets. في الوضع الآمن لا يبقى في الجدول الأصلي شيء يُقرأ.
create table if not exists public.app_account_secrets (
  tbl           text not null,
  client_id     uuid not null,
  id            text not null,
  password_hash text,
  totp_secret   text,
  updated_at    timestamptz not null default now(),
  primary key (tbl, client_id, id)
);
alter table public.app_account_secrets enable row level security;   -- بلا سياسات
revoke all on public.app_account_secrets from anon, authenticated;

create or replace function public.app_protect_secrets()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare j jsonb := to_jsonb(new); pw text := j->>'password'; ts text := j->>'totp_secret';
        sec boolean := public.app_secure(new.client_id);
begin
  if pw is not null and pw <> '' then
    insert into public.app_account_secrets (tbl, client_id, id, password_hash)
    values (TG_TABLE_NAME, new.client_id, new.id, crypt(pw, gen_salt('bf', 8)))
    on conflict (tbl, client_id, id) do update set password_hash = excluded.password_hash, updated_at = now();
  end if;
  if ts is not null and ts <> '' then
    insert into public.app_account_secrets (tbl, client_id, id, totp_secret)
    values (TG_TABLE_NAME, new.client_id, new.id, ts)
    on conflict (tbl, client_id, id) do update set totp_secret = excluded.totp_secret, updated_at = now();
  end if;
  if sec then
    -- لا شيء قابل للقراءة: كلمة السر فارغة، وسر 2FA محذوف من الجدول الأصلي
    j := jsonb_build_object('password', '');
    if TG_TABLE_NAME like '%app_users' then j := j || jsonb_build_object('totp_secret', null); end if;
    new := jsonb_populate_record(new, j);
  elsif TG_OP = 'UPDATE' and (pw is null or pw = '') then
    -- الوضع العادي: البرنامج الجديد لا يعيد كلمة السر عند الحفظ — نُبقي القديمة للأجهزة القديمة
    new := jsonb_populate_record(new, jsonb_build_object('password', to_jsonb(old)->>'password'));
  end if;
  return new;
end $$;

create or replace function public.app_drop_secrets()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from public.app_account_secrets where tbl = TG_TABLE_NAME and client_id = old.client_id and id = old.id;
  return old;
end $$;

do $$
declare r record;
begin
  for r in select c.relname as tbl from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname='public' and c.relkind='r'
              and c.relname in ('alum_app_users','alum_customer_accounts','alum_worker_accounts',
                                'trade_app_users','trade_customer_accounts','trade_worker_accounts')
  loop
    execute format('drop trigger if exists trg_protect_secrets on public.%I', r.tbl);
    execute format('create trigger trg_protect_secrets before insert or update on public.%I for each row execute function public.app_protect_secrets()', r.tbl);
    execute format('drop trigger if exists trg_drop_secrets on public.%I', r.tbl);
    execute format('create trigger trg_drop_secrets after delete on public.%I for each row execute function public.app_drop_secrets()', r.tbl);
    -- نقل كلمات السر وأسرار 2FA الموجودة (المشغّل يعمل على هذا التحديث)
    execute format('update public.%I x set password = password where not exists (select 1 from public.app_account_secrets s where s.tbl = %L and s.client_id = x.client_id and s.id = x.id and s.password_hash is not null)', r.tbl, r.tbl);
  end loop;
end $$;

-- ---------- 6) TOTP (RFC 6238) في قاعدة البيانات ----------
create or replace function public.app_base32_decode(s text)
returns bytea language plpgsql immutable as $$
declare alphabet text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; bits text := ''; c text; i int; idx int; out bytea := ''::bytea;
begin
  s := upper(regexp_replace(coalesce(s,''), '[^A-Za-z2-7]', '', 'g'));
  for i in 1..length(s) loop
    c := substr(s, i, 1); idx := strpos(alphabet, c) - 1;
    if idx >= 0 then bits := bits || lpad(idx::bit(5)::text, 5, '0'); end if;
  end loop;
  i := 1;
  while i + 7 <= length(bits) loop
    out := out || set_byte('\x00'::bytea, 0, substr(bits, i, 8)::bit(8)::int);
    i := i + 8;
  end loop;
  return out;
end $$;

create or replace function public.app_totp_ok(p_secret text, p_code text)
returns boolean language plpgsql stable set search_path = public, extensions as $$
declare key bytea := public.app_base32_decode(p_secret); w int; ctr bigint; msg bytea; h bytea; off int; bin bigint;
begin
  if p_code is null or p_code !~ '^\d{6}$' or length(key) = 0 then return false; end if;
  for w in -1..1 loop
    ctr := floor(extract(epoch from now()) / 30)::bigint + w;
    msg := decode(lpad(to_hex(ctr), 16, '0'), 'hex');
    h := hmac(msg, key, 'sha1');
    off := get_byte(h, 19) & 15;
    bin := ((get_byte(h, off) & 127)::bigint << 24) | (get_byte(h, off+1)::bigint << 16)
         | (get_byte(h, off+2)::bigint << 8) | get_byte(h, off+3)::bigint;
    if lpad((bin % 1000000)::text, 6, '0') = p_code then return true; end if;
  end loop;
  return false;
end $$;

-- ---------- 7) تسجيل الدخول والخروج ----------
create or replace function public.app_pw_ok(p_tbl text, p_row jsonb, p_password text)
returns boolean language plpgsql stable security definer set search_path = public, extensions as $$
declare h text;
begin
  select password_hash into h from public.app_account_secrets
   where tbl = p_tbl and client_id = (p_row->>'client_id')::uuid and id = p_row->>'id';
  if h is not null then return crypt(coalesce(p_password,''), h) = h; end if;
  return coalesce(p_row->>'password','') <> '' and p_row->>'password' = p_password;   -- حساب قديم لم يُشفَّر بعد
end $$;

create or replace function public.app_login(p_product text, p_username text, p_password text, p_totp text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_cid uuid := public.my_client_id(); v_sid uuid := public.app_sid();
        r jsonb; ok boolean; fails int; u text := lower(trim(coalesce(p_username,''))); t text; secret text;
begin
  if p_product not in ('alum','trade') then raise exception 'bad product'; end if;
  if auth.uid() is null or v_sid is null then return jsonb_build_object('ok', false, 'reason', 'no_session'); end if;
  if v_cid is null then return jsonb_build_object('ok', false, 'reason', 'no_client'); end if;

  delete from public.app_login_attempts where at < now() - interval '1 day';
  select count(*) into fails from public.app_login_attempts a
   where a.client_id = v_cid and a.product = p_product and a.username = u and a.at > now() - interval '15 minutes';
  if fails >= 8 then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;

  -- 1) مستخدمو البرنامج
  t := p_product || '_app_users';
  execute format('select to_jsonb(x) from public.%I x where x.client_id = $1 and lower(x.username) = $2 limit 1', t) into r using v_cid, u;
  if r is not null then
    ok := public.app_pw_ok(t, r, p_password);
    if ok and coalesce((r->>'totp_enabled')::boolean, false) then
      if coalesce(p_totp,'') = '' then return jsonb_build_object('ok', false, 'need_totp', true); end if;
      select s.totp_secret into secret from public.app_account_secrets s where s.tbl = t and s.client_id = v_cid and s.id = r->>'id';
      ok := public.app_totp_ok(coalesce(secret, r->>'totp_secret'), p_totp);
    end if;
    if ok then
      insert into public.app_sessions as a (sid, product, uid, client_id, kind, account_id, role, perms)
      values (v_sid, p_product, auth.uid(), v_cid, 'staff', r->>'id', r->>'role',
              coalesce(array(select jsonb_array_elements_text(case when jsonb_typeof(r->'permissions')='array' then r->'permissions' else '[]'::jsonb end)), '{}'))
      on conflict (sid, product) do update set uid = excluded.uid, client_id = excluded.client_id, kind = excluded.kind,
        account_id = excluded.account_id, role = excluded.role, perms = excluded.perms,
        customer_id = null, worker_id = null, created_at = now();
      return jsonb_build_object('ok', true, 'kind', 'staff', 'account', (r - 'password' - 'totp_secret' - 'client_id'));
    end if;
  end if;

  -- 2) حسابات الزبائن
  if r is null then
    t := p_product || '_customer_accounts';
    execute format('select to_jsonb(x) from public.%I x where x.client_id = $1 and lower(x.username) = $2 limit 1', t) into r using v_cid, u;
    if r is not null and public.app_pw_ok(t, r, p_password) then
      insert into public.app_sessions as a (sid, product, uid, client_id, kind, account_id, customer_id)
      values (v_sid, p_product, auth.uid(), v_cid, 'customer', r->>'id', r->>'customer_id')
      on conflict (sid, product) do update set uid = excluded.uid, client_id = excluded.client_id, kind = 'customer',
        account_id = excluded.account_id, role = null, perms = '{}', customer_id = excluded.customer_id, worker_id = null, created_at = now();
      return jsonb_build_object('ok', true, 'kind', 'customer', 'account', (r - 'password' - 'client_id'));
    end if;
  end if;

  -- 3) حسابات العمال (الألمنيوم، والتجاري عند تفعيل تبويب العمال)
  t := p_product || '_worker_accounts';
  if r is null and to_regclass('public.' || t) is not null then
    execute format('select to_jsonb(x) from public.%I x where x.client_id = $1 and lower(x.username) = $2 limit 1', t) into r using v_cid, u;
    if r is not null and public.app_pw_ok(t, r, p_password) then
      insert into public.app_sessions as a (sid, product, uid, client_id, kind, account_id, worker_id)
      values (v_sid, p_product, auth.uid(), v_cid, 'worker', r->>'id', r->>'worker_id')
      on conflict (sid, product) do update set uid = excluded.uid, client_id = excluded.client_id, kind = 'worker',
        account_id = excluded.account_id, role = null, perms = '{}', customer_id = null, worker_id = excluded.worker_id, created_at = now();
      return jsonb_build_object('ok', true, 'kind', 'worker', 'account', (r - 'password' - 'client_id'));
    end if;
  end if;

  insert into public.app_login_attempts (client_id, product, username) values (v_cid, p_product, u);
  return jsonb_build_object('ok', false, 'reason', 'invalid');
end $$;

create or replace function public.app_logout(p_product text)
returns void language sql security definer set search_path = public, extensions as $$
  delete from public.app_sessions where sid = public.app_sid() and product = p_product;
$$;

-- هل المؤسسة الحالية بالوضع الآمن؟ (يقرأها البرنامج عند الفتح)
create or replace function public.app_mode()
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('secure', public.app_secure(public.my_client_id()));
$$;

-- تفعيل/إيقاف الوضع الآمن من لوحة /super
create or replace function public.set_secure_apps(p_client uuid, p_on boolean)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare t text;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update public.clients set secure_apps = p_on where id = p_client;
  if p_on then
    -- كلمات السر أصبحت مشفّرة — نفرّغ النسخة المقروءة
    foreach t in array array['alum_app_users','alum_customer_accounts','alum_worker_accounts',
                             'trade_app_users','trade_customer_accounts','trade_worker_accounts'] loop
      if to_regclass('public.' || t) is not null then
        -- المشغّل يحفظ البصمة والسر في app_account_secrets ثم يفرّغ الأعمدة المقروءة
        execute format('update public.%I set password = password where client_id = $1', t) using p_client;
      end if;
    end loop;
  else
    delete from public.app_sessions where client_id = p_client;
  end if;
  return jsonb_build_object('ok', true, 'secure', p_on);
end $$;

-- الدوال الداخلية لا تُستدعى مباشرة من المتصفح
revoke execute on function public.app_cur(text) from public, anon;
revoke execute on function public.app_pw_ok(text, jsonb, text) from public, anon, authenticated;
revoke execute on function public.set_secure_apps(uuid, boolean) from public, anon;
revoke execute on function public.app_login(text, text, text, text) from public, anon;
revoke execute on function public.app_logout(text) from public, anon;
grant execute on function public.app_login(text, text, text, text) to authenticated;
grant execute on function public.app_logout(text) to authenticated;
grant execute on function public.set_secure_apps(uuid, boolean) to authenticated;
grant execute on function public.app_mode() to authenticated;

-- تحقّق: كل جداول البرنامجين عليها سياسات gate_*
select tablename, count(*) filter (where policyname like 'gate\_%') as gate_policies
from pg_policies where schemaname='public' and (tablename like 'alum\_%' or tablename like 'trade\_%')
group by tablename order by tablename;
