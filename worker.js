import { WhishClient, parseCallbackUrl } from 'whish-pay';

// ============================================================
//  LibanApps — Cloudflare Worker
//  بيخدم ملفات الموقع + مسارات الـAPI بملف واحد
//  بدون أي مكتبة خارجية
// ============================================================

const MAX_BYTES = 3 * 1024 * 1024;

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }
  });
}

function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

// ---------- حفظ الفاتورة ----------
async function storeInvoice(request, env) {
  const URL_ = env.SUPABASE_URL;
  const KEY = env.SUPABASE_SERVICE_KEY;
  if (!URL_ || !KEY) return json(500, { error: 'server not configured' });

  let body;
  try { body = await request.json(); }
  catch { return json(400, { error: 'bad json' }); }

  const { token, pdf_base64 } = body || {};
  if (!token || !pdf_base64) return json(400, { error: 'missing fields' });

  let bytes;
  try { bytes = b64ToBytes(pdf_base64); }
  catch { return json(400, { error: 'bad base64' }); }
  if (!bytes.length || bytes.length > MAX_BYTES) return json(400, { error: 'bad file size' });
  if (String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3]) !== '%PDF') {
    return json(400, { error: 'not a pdf' });
  }

  const h = { apikey: KEY, Authorization: `Bearer ${KEY}` };

  const q = `${URL_}/rest/v1/orders?token=eq.${encodeURIComponent(token)}` +
            `&select=id,order_no,invoice_pdf_url&limit=1`;
  const r1 = await fetch(q, { headers: h });
  if (!r1.ok) return json(500, { error: 'lookup failed' });
  const rows = await r1.json();
  const order = rows && rows[0];
  if (!order) return json(404, { error: 'order not found' });
  if (order.invoice_pdf_url) return json(200, { url: order.invoice_pdf_url, cached: true });

  const path = `${order.id}-${order.order_no}.pdf`;
  const up = await fetch(`${URL_}/storage/v1/object/invoices/${encodeURIComponent(path)}`, {
    method: 'POST',
    headers: { ...h, 'Content-Type': 'application/pdf' },
    body: bytes
  });
  if (!up.ok) {
    const t = await up.text();
    if (!t.includes('already exists') && !t.includes('Duplicate')) {
      return json(500, { error: 'upload failed' });
    }
  }

  const url = `${URL_}/storage/v1/object/public/invoices/${encodeURIComponent(path)}`;
  await fetch(`${URL_}/rest/v1/orders?id=eq.${order.id}`, {
    method: 'PATCH',
    headers: { ...h, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
    body: JSON.stringify({ invoice_pdf_url: url })
  });

  return json(200, { url });
}


// ---------- مساعد Supabase ----------
function sbHeaders(env) {
  const k = env.SUPABASE_SERVICE_KEY;
  return { apikey: k, Authorization: `Bearer ${k}` };
}
async function sbGet(env, path) {
  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/${path}`, { headers: sbHeaders(env) });
  if (!r.ok) throw new Error('db read failed');
  return r.json();
}
async function sbPatch(env, path, body) {
  return fetch(`${env.SUPABASE_URL}/rest/v1/${path}`, {
    method: 'PATCH',
    headers: { ...sbHeaders(env), 'Content-Type': 'application/json', Prefer: 'return=minimal' },
    body: JSON.stringify(body)
  });
}

// ---------- عميل Whish لمطعم معيّن ----------
async function whishFor(env, restaurantId) {
  const rows = await sbGet(env,
    `payment_credentials?restaurant_id=eq.${restaurantId}&select=*&limit=1`);
  const c = rows[0];
  if (!c || !c.whish_enabled || !c.whish_channel || !c.whish_secret) return null;
  return {
    cred: c,
    client: new WhishClient({
      channel: c.whish_channel,
      secret: c.whish_secret,
      websiteUrl: c.website_url || env.WEBSITE_URL,
      // نمرّرها صراحةً: على Cloudflare ما في NODE_ENV
      environment: (env.WHISH_ENV === 'sandbox') ? 'sandbox' : 'production'
    })
  };
}

// ---------- إنشاء دفعة ----------
async function whishCreate(request, env) {
  let body;
  try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const { order_id, slug } = body || {};
  if (!order_id || !slug) return json(400, { error: 'missing fields' });

  const orders = await sbGet(env,
    `orders?id=eq.${Number(order_id)}&select=id,order_no,restaurant_id,total_usd,total_lbp,status,token&limit=1`);
  const order = orders[0];
  if (!order) return json(404, { error: 'order not found' });
  if (order.status === 'paid') return json(400, { error: 'already paid' });

  const rests = await sbGet(env,
    `restaurants?id=eq.${order.restaurant_id}&select=id,slug,name_en&limit=1`);
  const rest = rests[0];
  if (!rest || rest.slug !== slug) return json(400, { error: 'restaurant mismatch' });

  const w = await whishFor(env, order.restaurant_id);
  if (!w) return json(400, { error: 'الدفع عبر Whish غير مفعّل لهذا المطعم' });

  const currency = w.cred.whish_currency === 'LBP' ? 'LBP' : 'USD';
  const amount = currency === 'LBP' ? Number(order.total_lbp) : Number(order.total_usd);
  if (!(amount > 0)) return json(400, { error: 'invalid amount' });

  const site = env.WEBSITE_URL;
  try {
    const result = await w.client.createPayment({
      amount,
      currency,
      invoice: `${rest.name_en} — ${order.order_no}`,
      externalId: Number(order.id),
      successCallbackUrl: `${site}/api/whish/callback-success`,
      failureCallbackUrl: `${site}/api/whish/callback-failure`,
      successRedirectUrl: `${site}/i/${encodeURIComponent(order.token)}`,
      failureRedirectUrl: `${site}/${rest.slug}?payment=failed`
    });

    if (!result.success) {
      return json(400, { error: (result.dialog && result.dialog.message) || 'payment rejected' });
    }

    await sbPatch(env, `orders?id=eq.${order.id}`,
      { status: 'awaiting_payment', whish_currency: currency });

    return json(200, { collectUrl: result.collectUrl });
  } catch (e) {
    console.error('whish create failed', e);
    var d = (e && e.dialog && e.dialog.message) || '';
    var parts = [];
    if (e && e.code) parts.push(e.code);
    if (e && e.httpStatus) parts.push('HTTP ' + e.httpStatus);
    if (d) parts.push(d);
    else if (e && e.message) parts.push(e.message);
    return json(502, {
      error: 'بوابة الدفع رفضت العملية: ' + (parts.join(' · ') || 'سبب غير معروف'),
      env: (env.WHISH_ENV === 'sandbox') ? 'sandbox' : 'production',
      site: w.cred.website_url || env.WEBSITE_URL,
      currency: currency,
      amount: amount
    });
  }
}

// ---------- تأكيد الدفع ----------
async function whishSuccess(request, env) {
  const parsed = parseCallbackUrl(request.url) || {};
  const { externalId, currency } = parsed;
  if (!externalId || !currency) return json(400, { error: 'malformed callback' });

  const orders = await sbGet(env,
    `orders?id=eq.${Number(externalId)}&select=id,restaurant_id,total_usd,total_lbp,status&limit=1`);
  const order = orders[0];
  if (!order) return json(404, { error: 'unknown order' });
  if (order.status === 'paid') return json(200, { ok: true, already: true });

  const w = await whishFor(env, order.restaurant_id);
  if (!w) return json(400, { error: 'no credentials' });

  let status;
  try {
    status = await w.client.getPaymentStatus(currency, Number(externalId));
  } catch (e) {
    console.error('status check failed', e && (e.code || e.message));
    return json(502, { error: 'status check failed' });
  }

  if (status.collectStatus !== 'success') {
    return json(400, { error: 'not confirmed', status: status.collectStatus });
  }

  // getPaymentStatus من Whish ما بيرجّع حقل amount (شفناها فعلياً برد حقيقي: فيه
  // بس collectStatus و payerPhoneNumber) — فمنتحقق من المبلغ فقط إذا كان موجوداً
  if (status.amount !== undefined && status.amount !== null) {
    const expected = currency === 'LBP' ? Number(order.total_lbp) : Number(order.total_usd);
    if (!w.client.validateAmount(Number(status.amount), expected, currency)) {
      console.error('amount mismatch', order.id, status.amount, expected);
      return json(400, { error: 'amount mismatch' });
    }
  }

  // idempotent: لا نلمس طلباً مدفوعاً مسبقاً
  await sbPatch(env, `orders?id=eq.${order.id}&status=neq.paid`, {
    status: 'paid',
    paid_at: new Date().toISOString(),
    whish_txn_id: status.transactionId || null,
    whish_currency: currency
  });

  return json(200, { ok: true });
}

// ---------- فشل الدفع ----------
async function whishFailure(request, env) {
  const { externalId, errorCode } = parseCallbackUrl(request.url) || {};
  if (!externalId) return json(400, { error: 'malformed callback' });
  await sbPatch(env, `orders?id=eq.${Number(externalId)}&status=eq.awaiting_payment`,
    { status: 'failed' });
  console.log('payment failed', externalId, errorCode);
  return json(200, { ok: true });
}





// ---------- وسيط الصور: بتنخدم من كاش Cloudflare بدل Supabase ----------
//  /img/items/xxx.jpg  →  Supabase Storage
//  أول طلب بيجيبها من Supabase، وبعدها بتنخدم من الكاش مجاناً
async function imageProxy(request, env, ctx, url) {
  const path = url.pathname.replace(/^\/img\//, '');
  if (!path || path.indexOf('..') >= 0) return new Response('bad path', { status: 400 });

  const cache = caches.default;
  const key = new Request(url.toString(), { method: 'GET' });
  const hit = await cache.match(key);
  if (hit) return hit;

  const target = `${env.SUPABASE_URL}/storage/v1/object/public/${path}`;
  const res = await fetch(target, { cf: { cacheEverything: true, cacheTtl: 604800 } });
  if (!res.ok) return new Response('not found', { status: 404 });

  const out = new Response(res.body, res);
  out.headers.set('Cache-Control', 'public, max-age=604800, immutable');  // أسبوع
  out.headers.set('X-LibanApps-Cache', 'MISS');
  out.headers.delete('set-cookie');
  if (ctx && ctx.waitUntil) ctx.waitUntil(cache.put(key, out.clone()));
  return out;
}


// ---------- توليد رمز تفعيل موقّع (لبرامج المحاسبة أوفلاين: ALUM / TRADE) ----------
//  نفس خوارزمية أداة client-setup — بس المفتاح الخاص هون بيجي من Secret،
//  مش مكتوب بالكود (هاد الملف على GitHub).
function b64urlBytes(bytes) {
  let bin = '';
  const arr = new Uint8Array(bytes);
  for (let i = 0; i < arr.length; i++) bin += String.fromCharCode(arr[i]);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
const PRODUCT_SIGNING_ENV = { alum: 'ALUM_PRIVATE_KEY_JWK', trade: 'TRADE_PRIVATE_KEY_JWK' };
async function generateActivationSerial(env, productCode, label, expMs) {
  const envVar = PRODUCT_SIGNING_ENV[productCode];
  if (!envVar || !env[envVar]) return null;   // المنتج ما إلو توقيع (متل menu) أو السر مش مضاف
  let privJwk;
  try { privJwk = JSON.parse(env[envVar]); }
  catch { console.error('bad signing key JSON for', productCode); return null; }
  const key = await crypto.subtle.importKey(
    'jwk', privJwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const payload = { label: label || '', exp: expMs };
  const payloadB64 = b64urlBytes(new TextEncoder().encode(JSON.stringify(payload)));
  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(payloadB64));
  return 'HMDH1.' + payloadB64 + '.' + b64urlBytes(sig);
}

// ---------- تحقّق مباشر من الدفع وتفعيل فوري ----------
//  ما بيعتمد على نداء Whish للسيرفر — منسأل Whish مباشرة
//  بيناديها الزبون لما يرجع من صفحة الدفع، وبتناديها لوحتك كمان
async function buyVerify(request, env) {
  const me = await currentUser(request, env);
  if (!me) return json(401, { error: 'سجّل دخولك أولاً' });

  let body;
  try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const pid = Number(body.purchase_id);
  if (!pid) return json(400, { error: 'missing purchase_id' });

  const rows = await sbGet(env,
    `purchases?id=eq.${pid}&select=id,user_id,amount_usd,status,product_code,biz_name&limit=1`);
  const p = rows[0];
  if (!p) return json(404, { error: 'purchase not found' });

  // صاحب العملية أو مشرف المنصة
  if (p.user_id !== me.id) {
    const adm = await sbGet(env, `platform_admins?user_id=eq.${me.id}&select=user_id&limit=1`);
    if (!adm.length) return json(403, { error: 'not allowed' });
  }

  if (p.status === 'paid') return json(200, { ok: true, already: true });

  const w = await platformWhish(env);
  if (!w) return json(400, { error: 'الدفع الإلكتروني غير مفعّل' });

  let st;
  try { st = await w.client.getPaymentStatus('USD', Number(p.id)); }
  catch (e) {
    console.error('verify status failed', e);
    return json(502, { error: 'ما قدرنا نتحقق من الدفعة عند Whish' });
  }

  if (st.collectStatus !== 'success') {
    return json(200, { ok: false, status: st.collectStatus || 'pending',
                       message: 'ما تأكد الدفع بعد' });
  }
  // ملاحظة: رد getPaymentStatus من Whish ما بيرجّع حقل amount أصلاً
  // (رجّع فقط collectStatus و payerPhoneNumber) — فالمبلغ انحدد فعلياً
  // وقت إنشاء الدفعة (createPayment) وربطناه بـ externalId، فلا داعي
  // ولا طريقة نتحقق منه مرة ثانية هون.
  if (st.amount !== undefined && st.amount !== null) {
    const got = Number(st.amount);
    const want = Number(p.amount_usd);
    const okAmount = w.client.validateAmount(got, want, 'USD')
                     || (isFinite(got) && got >= want - 0.01)
                     || (isFinite(got) && got >= want * 0.99 - 0.005);
    if (!okAmount) {
      return json(400, {
        error: 'المبلغ غير مطابق',
        whish_amount: got, expected: want, currency: st.currency || 'USD',
        status: st.collectStatus
      });
    }
  }

  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/provision_purchase`, {
    method: 'POST',
    headers: { ...sbHeaders(env), 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_id: Number(p.id), p_txn: st.transactionId || null })
  });
  if (!r.ok) {
    const t = await r.text();
    console.error('provision failed', t);
    return json(500, { error: 'تعذّر التفعيل: ' + t.slice(0, 120) });
  }
  const out = await r.json();

  // لبرامج المحاسبة الأوفلاين (ALUM/TRADE) — نولّد رمز التفعيل الموقّع ونحفظه
  // بالاشتراك حتى يظهر للزبون بصفحة "اشتراكاتي"
  if ((p.product_code === 'alum' || p.product_code === 'trade') && out.expires_at) {
    try {
      const subRows = await sbGet(env, `purchases?id=eq.${p.id}&select=subscription_id&limit=1`);
      const subId = subRows[0] && subRows[0].subscription_id;
      if (subId) {
        const label = p.biz_name || '';
        const expMs = new Date(out.expires_at).getTime();
        const serial = await generateActivationSerial(env, p.product_code, label, expMs);
        if (serial) {
          await sbPatch(env, `subscriptions?id=eq.${subId}`, { key: serial });
          out.key = serial;
        } else {
          console.error('activation serial not generated — missing signing secret for', p.product_code);
        }
      }
    } catch (e) {
      console.error('activation serial generation failed', e);
      // ما منفشّل كل عملية التفعيل بسبب هيدا — الاشتراك تفعّل، بس المفتاح ممكن يضل القديم
    }
  }

  return json(200, { ok: true, activated: true, result: out });
}

// ---------- شراء باقة من الموقع ----------
async function platformWhish(env) {
  const rows = await sbGet(env, 'platform_settings?id=eq.1&select=*&limit=1');
  const s = rows[0];
  if (!s || !s.whish_enabled || !s.whish_channel || !s.whish_secret) return null;
  return {
    row: s,
    client: new WhishClient({
      channel: s.whish_channel,
      secret: s.whish_secret,
      websiteUrl: s.website_url || env.WEBSITE_URL,
      environment: (env.WHISH_ENV === 'sandbox') ? 'sandbox' : 'production'
    })
  };
}

// من هو صاحب الطلب؟
async function currentUser(request, env) {
  const auth = request.headers.get('Authorization') || '';
  const token = auth.replace(/^Bearer\s+/i, '');
  if (!token) return null;
  const r = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${token}` }
  });
  if (!r.ok) return null;
  return r.json();
}

// ============================================================
//  التحقق بخطوتين (2FA) — الرمز نفسه (TOTP) مُدار من Supabase Auth مباشرة من المتصفح
//  (sb.auth.mfa.*). هون بس الرموز الاحتياطية (backup codes) + تعطيل المشرف الطارئ.
// ============================================================
const BC_ALPHA = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // بدون أحرف/أرقام ملتبسة (0/O، 1/I/L)
function genBackupCode() {
  var out = '';
  var r = crypto.getRandomValues(new Uint8Array(8));
  for (var i = 0; i < 8; i++) { if (i === 4) out += '-'; out += BC_ALPHA[r[i] % BC_ALPHA.length]; }
  return out;
}
async function sha256Hex(s) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('');
}
// نص الخطأ الحقيقي من Supabase — حتى ما يضيع سبب الفشل (مثلاً: الجدول مش موجود)
async function sbErrText(r) {
  let t = ''; try { t = await r.text(); } catch (e) {}
  let m = t; try { const j = JSON.parse(t); m = j.message || j.hint || j.code || t; } catch (e) {}
  if (/mfa_backup_codes/.test(m) && /(not find|does not exist|PGRST205|42P01)/i.test(t)) m = 'mfa_backup_codes table missing — run db/upgrade-mfa-backup-codes.sql';
  return `HTTP ${r.status}${m ? ': ' + String(m).slice(0, 160) : ''}`;
}
async function mfaBackupGenerate(request, env) {
  const me = await currentUser(request, env);
  if (!me) return json(401, { error: 'سجّل دخولك أولاً' });
  const codes = Array.from({ length: 8 }, genBackupCode);
  const hashes = await Promise.all(codes.map(sha256Hex));
  // نمسح القديمة (مستعملة أو لأ) ونحط دفعة جديدة — تفعيل جديد بيلغي الرموز السابقة
  const del = await fetch(`${env.SUPABASE_URL}/rest/v1/mfa_backup_codes?user_id=eq.${me.id}`, {
    method: 'DELETE', headers: sbHeaders(env)
  });
  if (!del.ok) return json(500, { error: 'تعذّر تجديد الرموز الاحتياطية — ' + await sbErrText(del) });
  const rows = hashes.map(h => ({ user_id: me.id, code_hash: h }));
  const ins = await fetch(`${env.SUPABASE_URL}/rest/v1/mfa_backup_codes`, {
    method: 'POST', headers: { ...sbHeaders(env), 'Content-Type': 'application/json', Prefer: 'return=minimal' }, body: JSON.stringify(rows)
  });
  if (!ins.ok) return json(500, { error: 'تعذّر حفظ الرموز الاحتياطية — ' + await sbErrText(ins) });
  return json(200, { ok: true, codes }); // بترجع نص واضح مرة وحدة بس — ما بتنخزن أبداً
}
async function mfaBackupStatus(request, env) {
  const me = await currentUser(request, env);
  if (!me) return json(401, { error: 'سجّل دخولك أولاً' });
  const rows = await sbGet(env, `mfa_backup_codes?user_id=eq.${me.id}&used_at=is.null&select=id`);
  return json(200, { ok: true, unused: rows.length });
}
async function mfaBackupVerify(request, env) {
  const me = await currentUser(request, env);
  if (!me) return json(401, { error: 'سجّل دخولك أولاً' });
  let body; try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const code = String(body.code || '').trim().toUpperCase();
  if (!code) return json(400, { error: 'اكتب الرمز' });
  const hash = await sha256Hex(code);
  const rows = await sbGet(env, `mfa_backup_codes?user_id=eq.${me.id}&code_hash=eq.${hash}&used_at=is.null&select=id&limit=1`);
  if (!rows.length) return json(200, { ok: false, error: 'الرمز غير صحيح أو مستعمل من قبل' });
  await sbPatch(env, `mfa_backup_codes?id=eq.${rows[0].id}`, { used_at: new Date().toISOString() });
  const left = await sbGet(env, `mfa_backup_codes?user_id=eq.${me.id}&used_at=is.null&select=id`);
  return json(200, { ok: true, remaining: left.length });
}
async function mfaBackupClear(request, env) {
  const me = await currentUser(request, env);
  if (!me) return json(401, { error: 'سجّل دخولك أولاً' });
  await fetch(`${env.SUPABASE_URL}/rest/v1/mfa_backup_codes?user_id=eq.${me.id}`, { method: 'DELETE', headers: sbHeaders(env) });
  return json(200, { ok: true });
}
async function requirePlatformAdmin(request, env) {
  const auth = request.headers.get('Authorization') || '';
  const token = auth.replace(/^Bearer\s+/i, '');
  if (!token) return { err: json(401, { error: 'not signed in' }) };
  const me = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, { headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${token}` } });
  if (!me.ok) return { err: json(401, { error: 'invalid session' }) };
  const meData = await me.json();
  const admins = await sbGet(env, `platform_admins?user_id=eq.${meData.id}&select=user_id&limit=1`);
  if (!admins.length) return { err: json(403, { error: 'not allowed' }) };
  return { me: meData };
}
async function adminMfaStatus(request, env) {
  const g = await requirePlatformAdmin(request, env); if (g.err) return g.err;
  const url = new URL(request.url), userId = url.searchParams.get('user_id');
  if (!userId) return json(400, { error: 'missing user_id' });
  const r = await fetch(`${env.SUPABASE_URL}/auth/v1/admin/users/${userId}/factors`, {
    headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}` }
  });
  const factors = r.ok ? await r.json() : [];
  const codes = await sbGet(env, `mfa_backup_codes?user_id=eq.${userId}&used_at=is.null&select=id`);
  return json(200, { ok: true, factors: (factors || []).map(f => ({ id: f.id, status: f.status, created_at: f.created_at })), backup_unused: codes.length });
}
async function adminMfaDisable(request, env) {
  const g = await requirePlatformAdmin(request, env); if (g.err) return g.err;
  let body; try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const userId = body.user_id;
  if (!userId) return json(400, { error: 'missing user_id' });
  const r = await fetch(`${env.SUPABASE_URL}/auth/v1/admin/users/${userId}/factors`, {
    headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}` }
  });
  const factors = r.ok ? await r.json() : [];
  let removed = 0;
  for (const f of (factors || [])) {
    const d = await fetch(`${env.SUPABASE_URL}/auth/v1/admin/users/${userId}/factors/${f.id}`, {
      method: 'DELETE', headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}` }
    });
    if (d.ok) removed++;
  }
  await fetch(`${env.SUPABASE_URL}/rest/v1/mfa_backup_codes?user_id=eq.${userId}`, { method: 'DELETE', headers: sbHeaders(env) });
  return json(200, { ok: true, removed });
}

async function buyCreate(request, env) {
  const me = await currentUser(request, env);
  if (!me) return json(401, { error: 'سجّل دخولك أولاً' });

  let body;
  try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const pid = Number(body.purchase_id);
  if (!pid) return json(400, { error: 'missing purchase_id' });

  let rows = await sbGet(env,
    `purchases?id=eq.${pid}&select=*&limit=1`);
  let p = rows[0];
  if (!p) return json(404, { error: 'purchase not found' });
  if (p.user_id !== me.id) return json(403, { error: 'not allowed' });
  if (p.status === 'paid') return json(400, { error: 'مدفوعة مسبقاً' });

  // رابط Whish صالح لمرة وحدة — إعادة المحاولة بدها عملية جديدة
  if (p.status === 'awaiting_payment') {
    const clone = await fetch(`${env.SUPABASE_URL}/rest/v1/purchases`, {
      method: 'POST',
      headers: { ...sbHeaders(env), 'Content-Type': 'application/json', Prefer: 'return=representation' },
      body: JSON.stringify({
        user_id: p.user_id, client_id: p.client_id, plan_id: p.plan_id,
        product_code: p.product_code, amount_usd: p.amount_usd, days: p.days,
        slug: p.slug, biz_name: p.biz_name, renew_of: p.renew_of
      })
    });
    if (clone.ok) {
      const made = await clone.json();
      if (made && made[0]) {
        await sbPatch(env, `purchases?id=eq.${p.id}`, { status: 'cancelled' });
        p = made[0];
      }
    }
  }

  const w = await platformWhish(env);
  if (!w) return json(400, { error: 'الدفع الإلكتروني غير مفعّل حالياً — تواصل معنا' });

  const site = env.WEBSITE_URL;
  try {
    const res = await w.client.createPayment({
      amount: Number(p.amount_usd),
      currency: 'USD',
      invoice: `LibanApps — ${p.product_code} #${p.id}`,
      externalId: Number(p.id),
      successCallbackUrl: `${site}/api/buy/callback-success`,
      failureCallbackUrl: `${site}/api/buy/callback-failure`,
      successRedirectUrl:  `${site}/account?paid=${p.id}`,
      failureRedirectUrl:  `${site}/account?failed=${p.id}`
    });
    if (!res.success) {
      // منسجّل الرد كامل حتى نشوفه بلوغز Cloudflare (wrangler tail)
      console.error('whish create rejected', JSON.stringify(res));
      return json(400, {
        error: (res.dialog && res.dialog.message) || 'رفضت بوابة الدفع العملية',
        code: res.code || null,
        sent_amount: Number(p.amount_usd),
        sent_currency: 'USD'
      });
    }
    await sbPatch(env, `purchases?id=eq.${p.id}`, { status: 'awaiting_payment' });
    return json(200, { collectUrl: res.collectUrl });
  } catch (e) {
    console.error('buy create failed', JSON.stringify(e, Object.getOwnPropertyNames(e)));
    const d = (e && e.dialog && e.dialog.message) || (e && (e.code || e.message)) || '';
    return json(502, {
      error: 'بوابة الدفع: ' + d,
      code: e && e.code,
      httpStatus: e && e.httpStatus,
      sent_amount: Number(p.amount_usd),
      sent_currency: 'USD'
    });
  }
}

async function buySuccess(request, env) {
  const { externalId, currency } = parseCallbackUrl(request.url) || {};
  if (!externalId) return json(400, { error: 'malformed callback' });

  const rows = await sbGet(env,
    `purchases?id=eq.${Number(externalId)}&select=id,amount_usd,status&limit=1`);
  const p = rows[0];
  if (!p) return json(404, { error: 'unknown purchase' });
  if (p.status === 'paid') return json(200, { ok: true, already: true });

  const w = await platformWhish(env);
  if (!w) return json(400, { error: 'no platform credentials' });

  let st;
  try { st = await w.client.getPaymentStatus(currency || 'USD', Number(externalId)); }
  catch (e) { console.error('buy status failed', e); return json(502, { error: 'status check failed' }); }

  if (st.collectStatus !== 'success') return json(400, { error: 'not confirmed' });
  const gotCb = Number(st.amount), wantCb = Number(p.amount_usd);
  const okCb = w.client.validateAmount(gotCb, wantCb, currency || 'USD')
               || (isFinite(gotCb) && gotCb >= wantCb - 0.01)
               || (isFinite(gotCb) && gotCb >= wantCb * 0.85);
  if (!okCb) {
    console.error('buy amount mismatch', p.id, st.amount, p.amount_usd);
    return json(400, { error: 'amount mismatch', got: gotCb, expected: wantCb });
  }

  // التفعيل: ترخيص + مطعم إذا كانت باقة منيو
  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/provision_purchase`, {
    method: 'POST',
    headers: { ...sbHeaders(env), 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_id: Number(externalId), p_txn: st.transactionId || null })
  });
  if (!r.ok) {
    console.error('provision failed', await r.text());
    return json(500, { error: 'provision failed' });
  }
  return json(200, { ok: true });
}

async function buyFailure(request, env) {
  const { externalId } = parseCallbackUrl(request.url) || {};
  if (!externalId) return json(400, { error: 'malformed callback' });
  await sbPatch(env, `purchases?id=eq.${Number(externalId)}&status=eq.awaiting_payment`,
    { status: 'failed' });
  return json(200, { ok: true });
}

// ---------- إنشاء حساب لصاحب مطعم ----------
//  يتحقق أولاً أن الطالب مشرف منصة، ثم ينشئ المستخدم ويربطه بمطعمه.
// ---------- تحقق خفيف: مين صاحب رابط /portal/<slug> (بدون توليد رمز دخول) ----------
async function portalClient(request, env) {
  const url = new URL(request.url);
  const slug = (url.searchParams.get('slug') || '').trim().toLowerCase();
  const product = (url.searchParams.get('product') || 'alum').trim().toLowerCase();
  if (!slug) return json(400, { error: 'missing slug' });

  const rows = await sbGet(env,
    `app_settings?product_code=eq.${product}&slug=eq.${encodeURIComponent(slug)}&select=client_id&limit=1`);
  if (!rows.length) return json(200, { ok: false, reason: 'no_client' });

  return json(200, { ok: true, client_id: rows[0].client_id });
}

// ---------- دخول تلقائي مأمون لرابط /portal/<slug> — بدون شاشة دخول المنصة ----------
async function portalToken(request, env) {
  const url = new URL(request.url);
  const slug = (url.searchParams.get('slug') || '').trim().toLowerCase();
  const product = (url.searchParams.get('product') || 'alum').trim().toLowerCase();
  if (!slug) return json(400, { error: 'missing slug' });

  const settingsRows = await sbGet(env,
    `app_settings?product_code=eq.${product}&slug=eq.${encodeURIComponent(slug)}&select=client_id&limit=1`);
  if (!settingsRows.length) return json(200, { ok: false, reason: 'no_client' });
  const clientId = settingsRows[0].client_id;

  const subs = await sbGet(env,
    `subscriptions?client_id=eq.${clientId}&product_code=eq.${product}&select=status,expires_at&order=expires_at.desc&limit=1`);
  if (!subs.length) return json(200, { ok: false, reason: 'no_subscription' });
  const sub = subs[0];
  if (sub.status === 'suspended') return json(200, { ok: false, reason: 'suspended' });
  if (new Date(sub.expires_at).getTime() < Date.now()) return json(200, { ok: false, reason: 'expired' });

  const clientRows = await sbGet(env, `clients?id=eq.${clientId}&select=user_id&limit=1`);
  if (!clientRows.length || !clientRows[0].user_id) return json(200, { ok: false, reason: 'no_client' });
  const userId = clientRows[0].user_id;

  const userRes = await fetch(`${env.SUPABASE_URL}/auth/v1/admin/users/${userId}`, {
    headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}` }
  });
  if (!userRes.ok) return json(500, { error: 'user lookup failed' });
  const userData = await userRes.json();
  const email = userData.email;
  if (!email) return json(500, { error: 'الحساب المرتبط بلا إيميل' });

  const linkRes = await fetch(`${env.SUPABASE_URL}/auth/v1/admin/generate_link`, {
    method: 'POST',
    headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', email })
  });
  if (!linkRes.ok) {
    const t = await linkRes.text();
    return json(500, { error: 'تعذّر توليد رمز الدخول: ' + t.slice(0, 150) });
  }
  const linkData = await linkRes.json();
  const hashedToken = linkData.hashed_token || (linkData.properties && linkData.properties.hashed_token);
  if (!hashedToken) return json(500, { error: 'ما طلع رمز دخول من Supabase' });

  return json(200, { ok: true, hashed_token: hashedToken });
}

async function createOwner(request, env) {
  const auth = request.headers.get('Authorization') || '';
  const token = auth.replace(/^Bearer\s+/i, '');
  if (!token) return json(401, { error: 'not signed in' });

  // 1) من هو صاحب الطلب؟
  const me = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${token}` }
  });
  if (!me.ok) return json(401, { error: 'invalid session' });
  const meData = await me.json();

  // 2) هل هو مشرف منصة؟
  const admins = await sbGet(env, `platform_admins?user_id=eq.${meData.id}&select=user_id&limit=1`);
  if (!admins.length) return json(403, { error: 'not allowed' });

  let body;
  try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const email = String(body.email || '').trim().toLowerCase();
  const password = String(body.password || '');
  const restaurantId = body.restaurant_id;

  if (!email || !password || !restaurantId) return json(400, { error: 'missing fields' });
  if (password.length < 6) return json(400, { error: 'كلمة المرور قصيرة (6 أحرف على الأقل)' });

  const rest = await sbGet(env, `restaurants?id=eq.${restaurantId}&select=id,name_ar,slug&limit=1`);
  if (!rest.length) return json(404, { error: 'restaurant not found' });

  // 3) إنشاء المستخدم — مؤكّد مباشرة حتى يدخل بدون رسالة تفعيل
  let userId = null;
  const created = await fetch(`${env.SUPABASE_URL}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      apikey: env.SUPABASE_SERVICE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ email, password, email_confirm: true })
  });

  if (created.ok) {
    userId = (await created.json()).id;
  } else {
    const txt = await created.text();
    // موجود مسبقاً؟ نجيبه ونربطه بدل ما نفشل
    if (/already|exists|registered/i.test(txt)) {
      const found = await fetch(
        `${env.SUPABASE_URL}/auth/v1/admin/users?filter=${encodeURIComponent(email)}`,
        { headers: {
            apikey: env.SUPABASE_SERVICE_KEY,
            Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}` } });
      if (found.ok) {
        const list = await found.json();
        const u = (list.users || []).find(x => (x.email || '').toLowerCase() === email);
        if (u) userId = u.id;
      }
      if (!userId) return json(400, { error: 'الإيميل مستعمل ولم نتمكن من جلبه' });
    } else {
      console.error('create user failed', txt);
      return json(400, { error: 'تعذّر إنشاء الحساب: ' + txt.slice(0, 140) });
    }
  }

  // 4) ربط الزبون بحساب الدخول (ليشوف اشتراكه بصفحة حسابه)
  try {
    const rr = await sbGet(env, `restaurants?id=eq.${restaurantId}&select=client_id&limit=1`);
    const cid = rr[0] && rr[0].client_id;
    if (cid) await sbPatch(env, `clients?id=eq.${cid}&user_id=is.null`, { user_id: userId });
  } catch (e) { console.error('client link skipped', e && e.message); }

  // 5) الربط بالمطعم
  const link = await fetch(`${env.SUPABASE_URL}/rest/v1/restaurant_users`, {
    method: 'POST',
    headers: {
      ...sbHeaders(env),
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates,return=minimal'
    },
    body: JSON.stringify({ user_id: userId, restaurant_id: restaurantId, role: 'owner' })
  });
  if (!link.ok) {
    const t = await link.text();
    return json(400, { error: 'تعذّر الربط بالمطعم: ' + t.slice(0, 140) });
  }

  return json(200, {
    ok: true, email, user_id: userId,
    restaurant: rest[0].name_ar, slug: rest[0].slug,
    existed: !created.ok
  });
}

// ---------- حذف زبون بالكامل — بياناته + حساب دخوله (auth) ----------
async function adminDeleteClient(request, env) {
  const auth = request.headers.get('Authorization') || '';
  const token = auth.replace(/^Bearer\s+/i, '');
  if (!token) return json(401, { error: 'not signed in' });

  const me = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${token}` }
  });
  if (!me.ok) return json(401, { error: 'invalid session' });
  const meData = await me.json();

  const admins = await sbGet(env, `platform_admins?user_id=eq.${meData.id}&select=user_id&limit=1`);
  if (!admins.length) return json(403, { error: 'not allowed' });

  let body;
  try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const clientId = body.client_id;
  if (!clientId) return json(400, { error: 'missing client_id' });

  const rows = await sbGet(env, `clients?id=eq.${clientId}&select=id,name,user_id&limit=1`);
  if (!rows.length) return json(404, { error: 'client not found' });
  const client = rows[0];

  // 1) امسح سجل الزبون — وهاد بيسحب معه (CASCADE) كل الاشتراكات والمطاعم وبيانات البرامج
  const del = await fetch(`${env.SUPABASE_URL}/rest/v1/clients?id=eq.${clientId}`, {
    method: 'DELETE',
    headers: { ...sbHeaders(env), Prefer: 'return=representation' }
  });
  if (!del.ok) {
    const t = await del.text();
    return json(500, { error: 'تعذّر حذف سجل الزبون: ' + t.slice(0, 150) });
  }
  const deleted = await del.json();
  if (!deleted.length) return json(500, { error: 'ما انحذف ولا صف' });

  // 2) امسح حساب الدخول (auth) — بدون هذا، الزبون المحذوف بيضل يقدر يسجّل دخول
  let authDeleted = false, authError = null;
  if (client.user_id) {
    const delAuth = await fetch(`${env.SUPABASE_URL}/auth/v1/admin/users/${client.user_id}`, {
      method: 'DELETE',
      headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}` }
    });
    if (delAuth.ok) authDeleted = true;
    else authError = (await delAuth.text()).slice(0, 150);
  }

  return json(200, { ok: true, name: client.name, auth_deleted: authDeleted, auth_error: authError });
}

// ---------- إصدار ترخيص يدوي من لوحة المشرف — مع توليد رمز موقّع للألمنيوم/التجارة ----------
async function adminNewLicense(request, env) {
  const auth = request.headers.get('Authorization') || '';
  const token = auth.replace(/^Bearer\s+/i, '');
  if (!token) return json(401, { error: 'not signed in' });

  const me = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${token}` }
  });
  if (!me.ok) return json(401, { error: 'invalid session' });
  const meData = await me.json();

  const admins = await sbGet(env, `platform_admins?user_id=eq.${meData.id}&select=user_id&limit=1`);
  if (!admins.length) return json(403, { error: 'not allowed' });

  let body;
  try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const clientId = body.client_id, productCode = body.product_code;
  const days = Number(body.days), price = Number(body.price) || 0;
  const notes = String(body.notes || '');
  if (!clientId || !productCode || !days) return json(400, { error: 'missing fields' });

  const plan = days <= 7 ? 'trial' : (days <= 31 ? 'monthly' : 'yearly');

  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/new_subscription`, {
    method: 'POST',
    headers: { ...sbHeaders(env), 'Content-Type': 'application/json' },
    body: JSON.stringify({
      p_client: clientId, p_product: productCode, p_plan: plan,
      p_days: days, p_price: price, p_slug: '', p_notes: notes
    })
  });
  if (!r.ok) {
    const t = await r.text();
    return json(500, { error: 'تعذّر إنشاء الاشتراك: ' + t.slice(0, 150) });
  }
  const sub = await r.json();

  let finalKey = sub.key;
  let finalSlug = '';

  if (productCode === 'alum' || productCode === 'trade') {
    const bizName = String(body.biz_name || '').trim();
    const vSlug = String(body.slug || '').trim().toLowerCase().replace(/[^a-z0-9-]/g, '');
    const expMs = new Date(sub.expires_at).getTime();

    const serial = await generateActivationSerial(env, productCode, bizName || vSlug, expMs);
    if (serial) {
      await sbPatch(env, `subscriptions?id=eq.${sub.id}`, { key: serial });
      finalKey = serial;
    }

    if (vSlug) {
      const av = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/slug_available`, {
        method: 'POST',
        headers: { ...sbHeaders(env), 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_slug: vSlug })
      });
      const isFree = av.ok ? await av.json() : false;
      if (isFree) {
        await fetch(`${env.SUPABASE_URL}/rest/v1/app_settings`, {
          method: 'POST',
          headers: { ...sbHeaders(env), 'Content-Type': 'application/json',
                     Prefer: 'resolution=merge-duplicates,return=minimal' },
          body: JSON.stringify({ client_id: clientId, product_code: productCode,
                                  slug: vSlug, biz_name: bizName || vSlug })
        });
        finalSlug = vSlug;
      }
      // إذا الرابط محجوز، منتابع بدون ما نوقف — الترخيص انعمل، بس بلا رابط مخصص
    }
  }

  return json(200, { ok: true, key: finalKey, expires_at: sub.expires_at, slug: finalSlug });
}

// ---------- تمديد ترخيص — بتولّد رمز موقّع جديد بالتاريخ الجديد للألمنيوم/التجارة ----------
async function adminExtendLicense(request, env) {
  const auth = request.headers.get('Authorization') || '';
  const token = auth.replace(/^Bearer\s+/i, '');
  if (!token) return json(401, { error: 'not signed in' });

  const me = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${token}` }
  });
  if (!me.ok) return json(401, { error: 'invalid session' });
  const meData = await me.json();

  const admins = await sbGet(env, `platform_admins?user_id=eq.${meData.id}&select=user_id&limit=1`);
  if (!admins.length) return json(403, { error: 'not allowed' });

  let body;
  try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const subId = body.id, days = Number(body.days);
  if (!subId || !days) return json(400, { error: 'missing fields' });

  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/extend_subscription`, {
    method: 'POST',
    headers: { ...sbHeaders(env), 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_id: subId, p_days: days })
  });
  if (!r.ok) {
    const t = await r.text();
    return json(500, { error: 'تعذّر التمديد: ' + t.slice(0, 150) });
  }
  const sub = await r.json();
  let finalKey = sub.key;

  if (sub.product_code === 'alum' || sub.product_code === 'trade') {
    const st = await sbGet(env,
      `app_settings?client_id=eq.${sub.client_id}&product_code=eq.${sub.product_code}&select=biz_name,slug&limit=1`);
    const label = (st[0] && (st[0].biz_name || st[0].slug)) || '';
    const expMs = new Date(sub.expires_at).getTime();
    const serial = await generateActivationSerial(env, sub.product_code, label, expMs);
    if (serial) {
      await sbPatch(env, `subscriptions?id=eq.${sub.id}`, { key: serial });
      finalKey = serial;
    }
  }

  return json(200, { ok: true, key: finalKey, expires_at: sub.expires_at });
}


// ============================================================
//  المتجر الإلكتروني (product = store)
// ============================================================

// هل هذا الـHost تبع المنصة نفسها (وليس دومين زبون)؟
function isPlatformHost(host, env) {
  host = String(host || '').toLowerCase();
  let site = '';
  try { site = new URL(env.WEBSITE_URL || '').hostname.toLowerCase(); } catch (e) {}
  return host === 'localhost' || host === site || host === 'www.' + site ||
         host.endsWith('.' + site) || host.endsWith('.workers.dev');
}

// ============================================================
//  بوابات الدفع للمتاجر
//  كل بوابة = adapter فيه create (بيرجّع رابط الدفع) و verify (تحقق مباشر من البوابة).
//  الإعدادات (المفاتيح) بجدول store_gateways ولا بتوصل للمتصفح أبداً.
//  لإضافة بوابة جديدة: أضف adapter بـGATEWAYS + سطر بـ_gw_ready/_gw_supports بالـSQL.
// ============================================================
const ZERO_DEC = new Set(['BIF','CLP','DJF','GNF','JPY','KMF','KRW','MGA','PYG','RWF','UGX','VND','VUV','XAF','XOF','XPF','LBP','IQD','SYP','YER','IRR','IDR']);
const THREE_DEC = new Set(['BHD','JOD','KWD','OMR','TND','LYD']);
function decimalsOf(cur) { cur = String(cur).toUpperCase(); return ZERO_DEC.has(cur) ? 0 : (THREE_DEC.has(cur) ? 3 : 2); }
function fixedAmt(amount, cur) { return Number(amount).toFixed(decimalsOf(cur)); }
// Stripe: عملات صفرية الكسور (بدون LBP/IDR اللي بتتعامل ككسرين عندهم) وثلاثية بآخر رقم 0
const STRIPE_ZERO = new Set(['BIF','CLP','DJF','GNF','JPY','KMF','KRW','MGA','PYG','RWF','UGX','VND','VUV','XAF','XOF','XPF']);
function stripeMinor(amount, cur) {
  cur = String(cur).toUpperCase();
  if (STRIPE_ZERO.has(cur)) return Math.round(amount);
  if (THREE_DEC.has(cur)) return Math.round(amount * 100) * 10;
  return Math.round(amount * 100);
}
function dig(obj, path) {
  return String(path || '').split('.').filter(Boolean).reduce((o, k) => (o && o[k] !== undefined ? o[k] : undefined), obj);
}
function fillTpl(tpl, vars, mode) {
  return String(tpl || '').replace(/\{\{(\w+)\}\}/g, (m, k) => {
    const v = vars[k] === undefined || vars[k] === null ? '' : String(vars[k]);
    if (mode === 'json') return JSON.stringify(v).slice(1, -1);
    if (mode === 'url' || mode === 'form') return encodeURIComponent(v);
    return v;
  });
}
function parseHeaderLines(txt, vars) {
  const h = {};
  String(txt || '').split(/\r?\n/).forEach(line => {
    const k = line.indexOf(':'); if (k < 1) return;
    h[line.slice(0, k).trim()] = fillTpl(line.slice(k + 1).trim(), vars, 'raw');
  });
  return h;
}
async function hmacHex(algo, secret, msg) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: algo }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(msg));
  return Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('');
}
function randId(n) {
  const a = 'abcdefghijklmnopqrstuvwxyz0123456789'; let o = '';
  const r = crypto.getRandomValues(new Uint8Array(n));
  for (let i = 0; i < n; i++) o += a[r[i] % a.length];
  return o;
}
async function jfetch(url, opt) {
  const r = await fetch(url, opt);
  let j = null; const t = await r.text();
  try { j = JSON.parse(t); } catch (e) { j = { _raw: t.slice(0, 300) }; }
  return { ok: r.ok, status: r.status, j };
}

const GATEWAYS = {
  // ---------- Whish ----------
  whish: {
    client(c) {
      return new WhishClient({ channel: c.cfg.channel, secret: c.cfg.secret, websiteUrl: c.env.WEBSITE_URL,
        environment: (c.env.WHISH_ENV === 'sandbox') ? 'sandbox' : 'production' });
    },
    async create(c) {
      const cur = c.order.currency_code === 'LBP' ? 'LBP' : 'USD';
      const r = await this.client(c).createPayment({
        amount: Number(c.order.total), currency: cur,
        invoice: `${c.store.name} — ${c.order.order_no}`, externalId: Number(c.order.id),
        successCallbackUrl: `${c.site}/api/store/whish/callback-success`,
        failureCallbackUrl: `${c.site}/api/store/whish/callback-failure`,
        successRedirectUrl: c.ret, failureRedirectUrl: c.ret });
      if (!r.success) throw new Error((r.dialog && r.dialog.message) || 'Whish rejected');
      return { url: r.collectUrl, ref: String(c.order.id) };
    },
    async verify(c) {
      const cur = c.order.currency_code === 'LBP' ? 'LBP' : 'USD';
      const st = await this.client(c).getPaymentStatus(cur, Number(c.order.id));
      return { paid: st.collectStatus === 'success', txn: st.transactionId || '' };
    }
  },
  // ---------- Stripe (Checkout Session) ----------
  stripe: {
    async create(c) {
      const cur = c.order.currency_code.toLowerCase();
      const f = new URLSearchParams();
      f.set('mode', 'payment'); f.set('success_url', c.ret); f.set('cancel_url', c.ret);
      f.set('client_reference_id', String(c.order.id)); f.set('metadata[order_id]', String(c.order.id));
      f.set('line_items[0][quantity]', '1');
      f.set('line_items[0][price_data][currency]', cur);
      f.set('line_items[0][price_data][unit_amount]', String(stripeMinor(c.order.total, cur)));
      f.set('line_items[0][price_data][product_data][name]', `${c.store.name} — ${c.order.order_no}`);
      if (/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(c.order.customer_email || '')) f.set('customer_email', c.order.customer_email);
      const r = await jfetch('https://api.stripe.com/v1/checkout/sessions', { method: 'POST',
        headers: { Authorization: 'Bearer ' + c.cfg.secret_key, 'Content-Type': 'application/x-www-form-urlencoded' }, body: f });
      if (!r.ok || !r.j.url) throw new Error((r.j.error && r.j.error.message) || 'Stripe error ' + r.status);
      return { url: r.j.url, ref: r.j.id };
    },
    async verify(c) {
      const r = await jfetch(`https://api.stripe.com/v1/checkout/sessions/${encodeURIComponent(c.order.payment_ref)}`,
        { headers: { Authorization: 'Bearer ' + c.cfg.secret_key } });
      if (!r.ok) throw new Error((r.j.error && r.j.error.message) || 'Stripe error ' + r.status);
      const okAmt = r.j.amount_total === stripeMinor(c.order.total, c.order.currency_code);
      return { paid: r.j.payment_status === 'paid' && okAmt, failed: r.j.status === 'expired',
        txn: typeof r.j.payment_intent === 'string' ? r.j.payment_intent : '' };
    },
    async test(c) {
      const r = await jfetch('https://api.stripe.com/v1/balance', { headers: { Authorization: 'Bearer ' + c.cfg.secret_key } });
      if (!r.ok) throw new Error((r.j.error && r.j.error.message) || 'Stripe error ' + r.status);
      return { note: 'Stripe OK' + (c.cfg.secret_key.startsWith('sk_test') ? ' (test mode)' : '') };
    }
  },
  // ---------- PayPal (Orders v2) ----------
  paypal: {
    base(c) { return c.cfg.mode === 'live' ? 'https://api-m.paypal.com' : 'https://api-m.sandbox.paypal.com'; },
    async token(c) {
      const r = await jfetch(this.base(c) + '/v1/oauth2/token', { method: 'POST',
        headers: { Authorization: 'Basic ' + btoa(`${c.cfg.client_id}:${c.cfg.secret}`), 'Content-Type': 'application/x-www-form-urlencoded' },
        body: 'grant_type=client_credentials' });
      if (!r.ok || !r.j.access_token) throw new Error(r.j.error_description || 'PayPal auth failed (' + r.status + ')');
      return r.j.access_token;
    },
    async create(c) {
      const t = await this.token(c), cur = c.order.currency_code;
      const r = await jfetch(this.base(c) + '/v2/checkout/orders', { method: 'POST',
        headers: { Authorization: 'Bearer ' + t, 'Content-Type': 'application/json' },
        body: JSON.stringify({ intent: 'CAPTURE',
          purchase_units: [{ reference_id: c.order.order_no, custom_id: String(c.order.id),
            description: `${c.store.name} — ${c.order.order_no}`.slice(0, 120),
            amount: { currency_code: cur, value: fixedAmt(c.order.total, cur) } }],
          application_context: { return_url: c.ret, cancel_url: c.ret, user_action: 'PAY_NOW',
            brand_name: String(c.store.name).slice(0, 120), shipping_preference: 'NO_SHIPPING' } }) });
      const link = ((r.j.links || []).find(l => l.rel === 'approve' || l.rel === 'payer-action') || {}).href;
      if (!r.ok || !link) throw new Error(r.j.message || (r.j.details && r.j.details[0] && r.j.details[0].description) || 'PayPal error ' + r.status);
      return { url: link, ref: r.j.id };
    },
    async verify(c) {
      const t = await this.token(c), h = { Authorization: 'Bearer ' + t, 'Content-Type': 'application/json' };
      let r = await jfetch(`${this.base(c)}/v2/checkout/orders/${encodeURIComponent(c.order.payment_ref)}`, { headers: h });
      if (!r.ok) throw new Error(r.j.message || 'PayPal error ' + r.status);
      if (r.j.status === 'APPROVED') {
        r = await jfetch(`${this.base(c)}/v2/checkout/orders/${encodeURIComponent(c.order.payment_ref)}/capture`,
          { method: 'POST', headers: h, body: '{}' });
        if (!r.ok && !(r.j.details || []).some(d => d.issue === 'ORDER_ALREADY_CAPTURED')) throw new Error(r.j.message || 'PayPal capture failed');
      }
      const cap = dig(r.j, 'purchase_units.0.payments.captures.0');
      const done = r.j.status === 'COMPLETED' && cap && cap.status === 'COMPLETED' &&
        Math.abs(Number(cap.amount.value) - Number(c.order.total)) < 0.011;
      return { paid: !!done, txn: cap ? cap.id : '', failed: r.j.status === 'VOIDED' };
    },
    async test(c) { await this.token(c); return { note: 'PayPal OK (' + (c.cfg.mode === 'live' ? 'live' : 'sandbox') + ')' }; }
  },
  // ---------- Binance Pay ----------
  binance: {
    async call(c, path, body) {
      const ts = String(Date.now()), nonce = randId(32), b = JSON.stringify(body);
      const sig = (await hmacHex('SHA-512', c.cfg.secret_key, `${ts}\n${nonce}\n${b}\n`)).toUpperCase();
      return jfetch('https://bpay.binanceapi.com' + path, { method: 'POST', body: b, headers: {
        'Content-Type': 'application/json', 'BinancePay-Timestamp': ts, 'BinancePay-Nonce': nonce,
        'BinancePay-Certificate-SN': c.cfg.api_key, 'BinancePay-Signature': sig } });
    },
    async create(c) {
      const sc = c.order.currency_code, want = String(c.cfg.currency || 'USDT').toUpperCase();
      const pegged = sc === 'USD' && ['USDT', 'USDC', 'BUSD', 'USD'].includes(want);
      if (!(pegged || want === sc)) throw new Error(`Binance currency ${want} does not match store currency ${sc}`);
      const no = ('L' + c.order.id + randId(10)).slice(0, 32);
      const r = await this.call(c, '/binancepay/openapi/v3/order', {
        env: { terminalType: 'WEB' }, merchantTradeNo: no, orderAmount: Number(fixedAmt(c.order.total, sc)), currency: want,
        goods: { goodsType: '02', goodsCategory: 'Z000', referenceGoodsId: String(c.order.id), goodsName: `${c.store.name} ${c.order.order_no}`.slice(0, 60) },
        returnUrl: c.ret, cancelUrl: c.ret, webhookUrl: c.webhook });
      if (r.j.status !== 'SUCCESS' || !r.j.data) throw new Error(r.j.errorMessage || 'Binance Pay error ' + (r.j.code || r.status));
      return { url: r.j.data.checkoutUrl || r.j.data.universalUrl, ref: no };
    },
    async verify(c) {
      const r = await this.call(c, '/binancepay/openapi/v2/order/query', { merchantTradeNo: c.order.payment_ref });
      if (r.j.status !== 'SUCCESS' || !r.j.data) throw new Error(r.j.errorMessage || 'Binance Pay error');
      const st = r.j.data.status;
      return { paid: st === 'PAID', failed: ['EXPIRED', 'CANCELED', 'ERROR'].includes(st), txn: r.j.data.transactionId || '' };
    }
  },
  // ---------- Areeba / Mastercard Gateway (MPGS) — Hosted Checkout ----------
  areeba: {
    base(c) { return `https://${c.cfg.host || 'areeba.gateway.mastercard.com'}/api/rest/version/${c.cfg.api_version || '100'}/merchant/${encodeURIComponent(c.cfg.merchant_id)}`; },
    auth(c) { return 'Basic ' + btoa(`merchant.${c.cfg.merchant_id}:${c.cfg.api_password}`); },
    async create(c) {
      const ref = ('A' + c.order.id + randId(8)).toUpperCase(), cur = c.order.currency_code;
      const r = await jfetch(this.base(c) + '/session', { method: 'POST',
        headers: { Authorization: this.auth(c), 'Content-Type': 'application/json' },
        body: JSON.stringify({ apiOperation: 'INITIATE_CHECKOUT',
          interaction: { operation: 'PURCHASE', returnUrl: c.ret, cancelUrl: c.ret, merchant: { name: String(c.store.name).slice(0, 40) },
            displayControl: { billingAddress: 'HIDE' } },
          order: { id: ref, amount: fixedAmt(c.order.total, cur), currency: cur, description: `${c.store.name} ${c.order.order_no}`.slice(0, 120) } }) });
      const sid = r.j.session && r.j.session.id;
      if (!r.ok || !sid) throw new Error((r.j.error && r.j.error.explanation) || 'Areeba error ' + r.status);
      return { url: `https://${c.cfg.host || 'areeba.gateway.mastercard.com'}/checkout/pay/${sid}`, ref };
    },
    async verify(c) {
      const r = await jfetch(`${this.base(c)}/order/${encodeURIComponent(c.order.payment_ref)}`, { headers: { Authorization: this.auth(c) } });
      if (!r.ok) return { paid: false };
      const okAmt = Math.abs(Number(r.j.amount) - Number(c.order.total)) < 0.011;
      return { paid: r.j.result === 'SUCCESS' && r.j.status === 'CAPTURED' && okAmt,
        failed: r.j.result === 'FAILURE', txn: (dig(r.j, 'transaction.0.transaction.id')) || '' };
    }
  }
};

// ---------- بوابة عامة قابلة للضبط (MontyPay أو أي REST gateway) ----------
const GENERIC = {
  vars(c, ref) {
    return { amount: fixedAmt(c.order.total, c.order.currency_code), amount_minor: stripeMinor(c.order.total, c.order.currency_code),
      currency: c.order.currency_code, order_id: c.order.id, order_no: c.order.order_no, reference: ref, ref,
      return_url: c.ret, cancel_url: c.ret, webhook_url: c.webhook, customer_name: c.order.customer_name,
      customer_email: c.order.customer_email || '', customer_phone: c.order.customer_phone, store_name: c.store.name };
  },
  async create(c) {
    const ref = ('L' + c.order.id + randId(8)).toUpperCase(), v = this.vars(c, ref), form = c.cfg.content_type === 'form';
    const headers = Object.assign({ 'Content-Type': form ? 'application/x-www-form-urlencoded' : 'application/json' },
      parseHeaderLines(c.cfg.headers, v));
    const r = await jfetch(c.cfg.create_url, { method: c.cfg.method || 'POST', headers,
      body: fillTpl(c.cfg.body, v, form ? 'form' : 'json') });
    const url = dig(r.j, c.cfg.redirect_path);
    if (!r.ok || !url) throw new Error('Gateway error ' + r.status + ' ' + JSON.stringify(r.j).slice(0, 160));
    const refOut = c.cfg.ref_path ? String(dig(r.j, c.cfg.ref_path) || ref) : ref;
    return { url: String(url), ref: refOut };
  },
  async verify(c) {
    if (!c.cfg.status_url) return { paid: false, manual: true };
    const v = this.vars(c, c.order.payment_ref);
    const r = await jfetch(fillTpl(c.cfg.status_url, v, 'url'),
      { method: c.cfg.status_method || 'GET', headers: parseHeaderLines(c.cfg.headers, v) });
    const val = String(dig(r.j, c.cfg.status_path) === undefined ? '' : dig(r.j, c.cfg.status_path)).toLowerCase();
    const okv = String(c.cfg.paid_values || 'paid,success,successful,captured,completed,approved,settled').toLowerCase().split(',').map(x => x.trim());
    return { paid: okv.includes(val) };
  }
};
GATEWAYS.montypay = GENERIC;
GATEWAYS.custom = GENERIC;

async function gwContext(request, env, order) {
  const stores = await sbGet(env, `stores?id=eq.${order.store_id}&select=id,slug,name,is_active&limit=1`);
  const store = stores[0];
  if (!store) throw new Error('store not found');
  const gws = await sbGet(env, `store_gateways?store_id=eq.${store.id}&provider=eq.${encodeURIComponent(order.payment_method)}&select=enabled,config&limit=1`);
  const gw = gws[0];
  if (!gw || !gw.enabled) throw new Error('payment method disabled');
  const u = new URL(request.url), site = env.WEBSITE_URL;
  const back = isPlatformHost(u.hostname, env) ? `${u.origin}/portal-store/${store.slug}` : u.origin;
  return { env, order, store, cfg: gw.config || {}, site, origin: u.origin,
    ret: `${back}?paid=${encodeURIComponent(order.token)}`,
    webhook: `${site}/api/store/pay/webhook?t=${encodeURIComponent(order.token)}` };
}
const ORDER_COLS = 'id,order_no,store_id,total,currency_code,status,payment_method,payment_ref,token,customer_name,customer_email,customer_phone';

// إنشاء دفعة: الرمز السري للطلب هو الإثبات
async function payCreate(request, env) {
  let body; try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const token = String(body.token || '');
  if (!token) return json(400, { error: 'missing token' });
  const order = (await sbGet(env, `store_orders?token=eq.${encodeURIComponent(token)}&select=${ORDER_COLS}&limit=1`))[0];
  if (!order) return json(404, { error: 'order not found' });
  if (order.status === 'paid') return json(400, { error: 'already paid' });
  if (!['awaiting_payment', 'pending'].includes(order.status)) return json(400, { error: 'order not payable' });
  const adapter = GATEWAYS[order.payment_method];
  if (!adapter) return json(400, { error: 'هذه الطلبية مش لدفع أونلاين' });
  try {
    const c = await gwContext(request, env, order);
    const r = await adapter.create(c);
    await sbPatch(env, `store_orders?id=eq.${order.id}`, { payment_ref: r.ref, status: 'awaiting_payment' });
    return json(200, { url: r.url });
  } catch (e) {
    console.error('pay create failed', order.payment_method, e && e.message);
    return json(502, { error: 'بوابة الدفع رفضت العملية: ' + ((e && e.message) || '') });
  }
}

// تحقق مباشر من البوابة — بيناديه المتجر بعد رجوع الزبون، وwebhook، ولوحة التحكم
async function verifyOrder(request, env, order) {
  if (order.status === 'paid') return { status: 'paid', paid: true };
  const adapter = GATEWAYS[order.payment_method];
  if (!adapter || !order.payment_ref) return { status: order.status, paid: false };
  const c = await gwContext(request, env, order);
  const r = await adapter.verify(c);
  if (r.paid) {
    await sbPatch(env, `store_orders?id=eq.${order.id}&status=neq.paid`, {
      status: 'paid', paid_at: new Date().toISOString(), whish_txn_id: r.txn || null });
    return { status: 'paid', paid: true };
  }
  if (r.failed && order.status === 'awaiting_payment') {
    await sbPatch(env, `store_orders?id=eq.${order.id}&status=eq.awaiting_payment`, { status: 'failed' });
    return { status: 'failed', paid: false };
  }
  return { status: order.status, paid: false, manual: !!r.manual };
}
async function payVerify(request, env) {
  const u = new URL(request.url);
  let token = u.searchParams.get('t') || '';
  if (!token && request.method === 'POST') { try { token = String((await request.json()).token || ''); } catch (e) {} }
  if (!token) return json(400, { error: 'missing token' });
  const order = (await sbGet(env, `store_orders?token=eq.${encodeURIComponent(token)}&select=${ORDER_COLS}&limit=1`))[0];
  if (!order) return json(404, { error: 'order not found' });
  try { return json(200, Object.assign({ ok: true, order_no: order.order_no }, await verifyOrder(request, env, order))); }
  catch (e) { console.error('pay verify failed', e && e.message); return json(200, { ok: true, status: order.status, paid: false, error: String((e && e.message) || '') }); }
}
async function payWebhook(request, env) {
  const u = new URL(request.url), token = u.searchParams.get('t') || '';
  if (token) {
    const order = (await sbGet(env, `store_orders?token=eq.${encodeURIComponent(token)}&select=${ORDER_COLS}&limit=1`))[0];
    if (order) { try { await verifyOrder(request, env, order); } catch (e) { console.error('webhook verify', e && e.message); } }
  }
  return json(200, { returnCode: 'SUCCESS', returnMessage: null });   // الشكل اللي بتتوقعه Binance
}

// ---------- callbacks تبع Whish (بتشغّل نفس التحقق) ----------
async function storeWhishSuccess(request, env) {
  const { externalId } = parseCallbackUrl(request.url) || {};
  if (!externalId) return json(400, { error: 'malformed callback' });
  const order = (await sbGet(env, `store_orders?id=eq.${Number(externalId)}&select=${ORDER_COLS}&limit=1`))[0];
  if (!order) return json(404, { error: 'unknown order' });
  try { return json(200, Object.assign({ ok: true }, await verifyOrder(request, env, order))); }
  catch (e) { return json(502, { error: 'status check failed' }); }
}
async function storeWhishFailure(request, env) {
  const { externalId } = parseCallbackUrl(request.url) || {};
  if (!externalId) return json(400, { error: 'malformed callback' });
  await sbPatch(env, `store_orders?id=eq.${Number(externalId)}&status=eq.awaiting_payment`, { status: 'failed' });
  return json(200, { ok: true });
}

// ---------- فحص المفاتيح من لوحة التحكم ----------
async function ownerCheck(request, env, storeId) {
  const me = await currentUser(request, env);
  if (!me) return { err: json(401, { error: 'سجّل دخولك أولاً' }) };
  if (!/^[0-9a-f-]{36}$/i.test(String(storeId || ''))) return { err: json(400, { error: 'bad store' }) };
  const store = (await sbGet(env, `stores?id=eq.${storeId}&select=id,client_id,slug,name&limit=1`))[0];
  if (!store) return { err: json(404, { error: 'store not found' }) };
  const cl = await sbGet(env, `clients?id=eq.${store.client_id}&select=user_id&limit=1`);
  let allowed = cl[0] && cl[0].user_id === me.id;
  if (!allowed) allowed = (await sbGet(env, `platform_admins?user_id=eq.${me.id}&select=user_id&limit=1`)).length > 0;
  if (!allowed) return { err: json(403, { error: 'not allowed' }) };
  return { store, me };
}
async function payTest(request, env) {
  let body; try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const o = await ownerCheck(request, env, body.store_id); if (o.err) return o.err;
  const provider = String(body.provider || '');
  const gw = (await sbGet(env, `store_gateways?store_id=eq.${o.store.id}&provider=eq.${encodeURIComponent(provider)}&select=config&limit=1`))[0];
  if (!gw) return json(400, { error: 'احفظ الإعدادات أولاً' });
  const adapter = GATEWAYS[provider];
  if (!adapter || !adapter.test) return json(200, { ok: true, note: 'ما في فحص تلقائي لهذه البوابة — جرّب طلب صغير.' });
  try { return json(200, Object.assign({ ok: true }, await adapter.test({ env, cfg: gw.config || {}, store: o.store }))); }
  catch (e) { return json(200, { ok: false, error: String((e && e.message) || e) }); }
}


// ---------- استيراد صورة من رابط خارجي (WooCommerce…) لتخزينها عند صاحب المتجر ----------
function isBlockedHost(h) {
  h = String(h || '').toLowerCase();
  return !h || h === 'localhost' || h.endsWith('.local') || h.endsWith('.internal') ||
    /^(\d{1,3}\.){3}\d{1,3}$/.test(h) || h.includes(':') || h.startsWith('[');
}
async function importImage(request, env) {
  let body; try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const o = await ownerCheck(request, env, body.store_id); if (o.err) return o.err;
  let u; try { u = new URL(String(body.url || '')); } catch { return json(400, { error: 'bad url', reason: 'bad_url' }); }
  if (!/^https?:$/.test(u.protocol) || isBlockedHost(u.hostname)) return json(400, { error: 'url not allowed', reason: 'bad_url' });
  const ctl = new AbortController(); const to = setTimeout(() => ctl.abort(), 20000);
  let r;
  try {
    // UA و Accept-Language متل متصفح حقيقي — مواقع كتير (خصوصاً خلف Cloudflare) بتحظر أي طلب شكلو "بوت"
    r = await fetch(u.toString(), { signal: ctl.signal, redirect: 'follow', headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8', 'Accept-Language': 'en-US,en;q=0.9,ar;q=0.8', 'Referer': u.origin + '/' } });
  } catch (e) {
    clearTimeout(to);
    const reason = (e && e.name === 'AbortError') ? 'timeout' : 'network';
    return json(502, { error: reason === 'timeout' ? 'انتهت المهلة (تعليق من المصدر)' : 'تعذّر الاتصال بالمصدر', reason });
  }
  clearTimeout(to);
  if (!r.ok) {
    const reason = r.status === 403 ? 'blocked' : r.status === 404 ? 'not_found' : r.status === 429 ? 'rate_limited' : 'http_' + r.status;
    return json(502, { error: 'المصدر رجّع ' + r.status, reason, status: r.status });
  }
  let ct = (r.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
  const extFromUrl = (u.pathname.match(/\.([a-z0-9]{3,4})$/i) || [])[1];
  const byExt = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp', gif: 'image/gif', avif: 'image/avif', svg: 'image/svg+xml' };
  if (!ct.startsWith('image/')) ct = byExt[(extFromUrl || '').toLowerCase()] || '';
  if (!ct.startsWith('image/')) return json(415, { error: 'الرابط مش صورة', reason: 'not_image' });
  const buf = await r.arrayBuffer();
  if (buf.byteLength > 8 * 1024 * 1024) return json(413, { error: 'الصورة أكبر من 8MB', reason: 'too_large' });
  if (buf.byteLength < 200) return json(415, { error: 'ملف فارغ', reason: 'empty' });
  const ext = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/gif': 'gif', 'image/avif': 'avif', 'image/svg+xml': 'svg' }[ct] || 'jpg';
  const path = `st-${o.store.id}/imp-${Date.now().toString(36)}-${randId(6)}.${ext}`;
  const up = await fetch(`${env.SUPABASE_URL}/storage/v1/object/items/${path}`, { method: 'POST', body: buf,
    headers: { apikey: env.SUPABASE_SERVICE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_KEY}`, 'Content-Type': ct, 'x-upsert': 'false' } });
  if (!up.ok) return json(502, { error: 'تعذّر الحفظ بمخزن المتجر (' + up.status + ')', reason: 'storage' });
  return json(200, { ok: true, url: `${env.SUPABASE_URL}/storage/v1/object/public/items/${path}`, bytes: buf.byteLength });
}

// ---------- الدومين الخاص (Cloudflare for SaaS — Custom Hostnames) ----------
//  المتغيرات المطلوبة (Secrets): CF_API_TOKEN (صلاحية SSL and Certificates: Edit) + CF_ZONE_ID
//  متغير عادي اختياري: STORE_CNAME_TARGET (الافتراضي stores.libanapps.com)
async function cfApi(env, method, path, body) {
  const r = await fetch(`https://api.cloudflare.com/client/v4/zones/${env.CF_ZONE_ID}${path}`, {
    method,
    headers: { Authorization: `Bearer ${env.CF_API_TOKEN}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined
  });
  let j = {}; try { j = await r.json(); } catch (e) {}
  return j;
}
function cfError(j) {
  return (j && j.errors && j.errors[0] && j.errors[0].message) || 'Cloudflare error';
}
function normalizeDomain(v) {
  let d = String(v || '').trim().toLowerCase().replace(/^https?:\/\//, '').replace(/\/.*$/, '').replace(/:\d+$/, '');
  if (!/^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$/.test(d)) return '';
  return d;
}
function mapCf(res) {
  const st = res.status || '', ssl = (res.ssl && res.ssl.status) || '';
  const active = st === 'active' && (!ssl || ssl === 'active');
  const failed = ['blocked', 'moved', 'deleted'].includes(st) || ['deleted', 'validation_timed_out', 'issuance_timed_out'].includes(ssl);
  return { status: active ? 'active' : (failed ? 'failed' : 'pending'), cf_status: st, ssl_status: ssl };
}

async function storeDomain(request, env) {
  const me = await currentUser(request, env);
  if (!me) return json(401, { error: 'سجّل دخولك أولاً' });
  let body;
  try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const storeId = String(body.store_id || '');
  if (!/^[0-9a-f-]{36}$/i.test(storeId)) return json(400, { error: 'bad store' });

  const stores = await sbGet(env, `stores?id=eq.${storeId}&select=id,client_id,slug&limit=1`);
  const store = stores[0];
  if (!store) return json(404, { error: 'store not found' });
  const clients = await sbGet(env, `clients?id=eq.${store.client_id}&select=user_id&limit=1`);
  let allowed = clients[0] && clients[0].user_id === me.id;
  if (!allowed) {
    const adm = await sbGet(env, `platform_admins?user_id=eq.${me.id}&select=user_id&limit=1`);
    allowed = adm.length > 0;
  }
  if (!allowed) return json(403, { error: 'not allowed' });

  const cfOn = !!(env.CF_API_TOKEN && env.CF_ZONE_ID);
  const target = env.STORE_CNAME_TARGET || 'stores.libanapps.com';
  const existing = (await sbGet(env, `store_domains?store_id=eq.${store.id}&select=*&limit=1`))[0];
  const action = body.action;

  if (action === 'add') {
    if (existing) return json(400, { error: 'عندك دومين مربوط — احذفه أولاً' });
    const domain = normalizeDomain(body.domain);
    if (!domain) return json(400, { error: 'الدومين غير صالح — مثال: shop.mybrand.com' });
    if (isPlatformHost(domain, env)) return json(400, { error: 'هذا الدومين محجوز للمنصة' });
    const dup = await sbGet(env, `store_domains?domain=eq.${encodeURIComponent(domain)}&select=id&limit=1`);
    if (dup.length) return json(400, { error: 'هذا الدومين مربوط بمتجر آخر' });

    const info = { cname_target: target };
    let cfId = null, mapped = { status: 'pending', cf_status: '', ssl_status: '' };
    if (cfOn) {
      const j = await cfApi(env, 'POST', '/custom_hostnames',
        { hostname: domain, ssl: { method: 'http', type: 'dv', settings: { min_tls_version: '1.2' } } });
      if (!j.success) return json(400, { error: cfError(j) });
      cfId = j.result.id; mapped = mapCf(j.result);
      const ov = j.result.ownership_verification;
      if (ov && ov.name) { info.txt_name = ov.name; info.txt_value = ov.value; }
    }
    const ins = await fetch(`${env.SUPABASE_URL}/rest/v1/store_domains`, {
      method: 'POST',
      headers: { ...sbHeaders(env), 'Content-Type': 'application/json', Prefer: 'return=representation' },
      body: JSON.stringify({ store_id: store.id, domain, cf_hostname_id: cfId, info, ...mapped })
    });
    if (!ins.ok) return json(500, { error: 'تعذّر حفظ الدومين: ' + (await ins.text()).slice(0, 120) });
    const row = (await ins.json())[0];
    return json(200, { ok: true, domain: row, cname_target: target, manual: !cfOn,
      message: cfOn ? undefined : 'تم تسجيل طلبك — رح يتفعّل الدومين من قبل الدعم بعد ما تضيف سجل CNAME.' });
  }

  if (!existing) return json(404, { error: 'ما في دومين مربوط' });

  if (action === 'refresh') {
    if (!(cfOn && existing.cf_hostname_id)) return json(200, { ok: true, domain: existing, cname_target: target });
    const j = await cfApi(env, 'GET', `/custom_hostnames/${existing.cf_hostname_id}`);
    if (!j.success) return json(400, { error: cfError(j) });
    const m = mapCf(j.result);
    const upd = { ...m, verified_at: m.status === 'active' ? (existing.verified_at || new Date().toISOString()) : null };
    await sbPatch(env, `store_domains?id=eq.${existing.id}`, upd);
    return json(200, { ok: true, domain: { ...existing, ...upd }, cname_target: target });
  }

  if (action === 'remove') {
    if (cfOn && existing.cf_hostname_id) await cfApi(env, 'DELETE', `/custom_hostnames/${existing.cf_hostname_id}`);
    await fetch(`${env.SUPABASE_URL}/rest/v1/store_domains?id=eq.${existing.id}`, { method: 'DELETE', headers: sbHeaders(env) });
    domCache.delete(existing.domain);
    return json(200, { ok: true });
  }
  return json(400, { error: 'unknown action' });
}

// ---------- خدمة متجر على دومين الزبون ----------
const domCache = new Map();
async function resolveDomain(env, ctx, host) {
  const c = domCache.get(host);
  if (c && c.exp > Date.now()) return c.slug;
  let row;
  try {
    const rows = await sbGet(env, `store_domains?domain=eq.${encodeURIComponent(host)}&select=id,status,stores(slug)&limit=1`);
    row = rows[0];
  } catch (e) { return undefined; }            // خطأ مؤقت — ما منخزّنه
  const slug = (row && row.stores && row.stores.slug) || null;
  // وصلنا طلب على هالدومين = Cloudflare فعّله؛ منحدّث الحالة تلقائياً
  if (row && row.status === 'pending' && ctx && ctx.waitUntil) {
    ctx.waitUntil(sbPatch(env, `store_domains?id=eq.${row.id}`, { status: 'active', verified_at: new Date().toISOString() }));
  }
  domCache.set(host, { slug, exp: Date.now() + 60000 });
  return slug;
}
async function serveStore(env, url, slug) {
  const res = await env.ASSETS.fetch(new URL('/store.html', url.origin));
  let html = await res.text();
  html = html.replace('<!--STORE_BOOT-->', '<script>window.__STORE_SLUG__=' + JSON.stringify(slug) + ';</script>');
  return new Response(html, {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache' }
  });
}

// ---------- سياسة التخزين المؤقت ----------
//  HTML: المتصفح يسأل السيرفر كل مرة (no-cache) — التعديلات تصل فوراً
//  الصور والخطوط: تُخزَّن طويلاً — لا تتغيّر عادةً
//  CSS/JS: تُخزَّن ساعة مع إعادة تحقق
function withCache(res, pathname) {
  const h = new Headers(res.headers);
  let rule;
  if (/\.(png|jpe?g|gif|webp|svg|ico|woff2?|ttf)$/i.test(pathname)) {
    rule = 'public, max-age=604800';                       // أسبوع
  } else if (/\.(css|js)$/i.test(pathname)) {
    rule = 'public, max-age=3600, must-revalidate';         // ساعة
  } else {
    rule = 'no-cache';                                      // HTML وكل ما عداه
  }
  h.set('Cache-Control', rule);
  return new Response(res.body, { status: res.status, headers: h });
}

// ============================================================
//  اشتراك نظام التوصيل ومقاعد الموظفين — دفع Whish من لوحة المطعم
//  أرقام العمليات (addon_purchases) بتبلّش من 900000001 = externalId
// ============================================================
async function addonRow(env, id) {
  const rows = await sbGet(env, `addon_purchases?id=eq.${Number(id)}&select=*,restaurants(slug)&limit=1`);
  return rows[0];
}
async function addonProvision(env, id, txn) {
  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/provision_addon`, {
    method: 'POST',
    headers: { ...sbHeaders(env), 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_id: Number(id), p_txn: txn || null })
  });
  if (!r.ok) { const t = await r.text(); console.error('provision_addon failed', t); throw new Error(t.slice(0, 120)); }
  return r.json();
}
function amountOk(w, got, want, cur) {
  if (got === undefined || got === null || got === '') return true;   // Whish أحياناً ما بيرجّع المبلغ
  const g = Number(got);
  return w.client.validateAmount(g, want, cur || 'USD') || (isFinite(g) && g >= want - 0.01);
}
async function addonPay(request, env) {
  const me = await currentUser(request, env);
  if (!me) return json(401, { error: 'سجّل دخولك أولاً' });
  let body; try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  let p = await addonRow(env, body.id);
  if (!p) return json(404, { error: 'purchase not found' });
  if (p.user_id !== me.id) return json(403, { error: 'not allowed' });
  if (p.status === 'paid') return json(400, { error: 'مدفوعة مسبقاً' });

  // رابط Whish صالح لمرة وحدة — إعادة المحاولة بدها رقم عملية جديد
  if (p.status === 'awaiting_payment') {
    const clone = await fetch(`${env.SUPABASE_URL}/rest/v1/addon_purchases`, {
      method: 'POST',
      headers: { ...sbHeaders(env), 'Content-Type': 'application/json', Prefer: 'return=representation' },
      body: JSON.stringify({ user_id: p.user_id, restaurant_id: p.restaurant_id, kind: p.kind, seat_id: p.seat_id,
                             seat_ids: p.seat_ids, qty: p.qty, days: p.days, amount_usd: p.amount_usd })
    });
    if (clone.ok) {
      const made = await clone.json();
      if (made && made[0]) {
        await sbPatch(env, `addon_purchases?id=eq.${p.id}`, { status: 'cancelled' });
        made[0].restaurants = p.restaurants; p = made[0];
      }
    }
  }

  const w = await platformWhish(env);
  if (!w) return json(400, { error: 'الدفع الإلكتروني غير مفعّل حالياً — تواصل معنا' });
  const site = env.WEBSITE_URL;
  const slug = (p.restaurants && p.restaurants.slug) || '';
  const back = `${site}/${encodeURIComponent(slug)}/admin`;
  const label = { delivery: 'Delivery system', seat_new: 'Driver seat', seat_renew: 'Driver seat renewal', renew_all: 'Delivery renewal' }[p.kind] || p.kind;
  try {
    const res = await w.client.createPayment({
      amount: Number(p.amount_usd), currency: 'USD',
      invoice: `LibanApps — ${label} #${p.id}`,
      externalId: Number(p.id),
      successCallbackUrl: `${site}/api/addon/callback-success`,
      failureCallbackUrl: `${site}/api/addon/callback-failure`,
      successRedirectUrl: `${back}?addon=${p.id}`,
      failureRedirectUrl: `${back}?addon_failed=${p.id}`
    });
    if (!res.success) {
      console.error('addon whish rejected', JSON.stringify(res));
      return json(400, { error: (res.dialog && res.dialog.message) || 'رفضت بوابة الدفع العملية' });
    }
    await sbPatch(env, `addon_purchases?id=eq.${p.id}`, { status: 'awaiting_payment' });
    return json(200, { collectUrl: res.collectUrl });
  } catch (e) {
    console.error('addon pay failed', JSON.stringify(e, Object.getOwnPropertyNames(e)));
    return json(502, { error: 'بوابة الدفع: ' + ((e && e.dialog && e.dialog.message) || (e && (e.code || e.message)) || '') });
  }
}
async function addonVerify(request, env) {
  const me = await currentUser(request, env);
  if (!me) return json(401, { error: 'سجّل دخولك أولاً' });
  let body; try { body = await request.json(); } catch { return json(400, { error: 'bad json' }); }
  const p = await addonRow(env, body.id);
  if (!p) return json(404, { error: 'purchase not found' });
  if (p.user_id !== me.id) {
    const adm = await sbGet(env, `platform_admins?user_id=eq.${me.id}&select=user_id&limit=1`);
    if (!adm.length) return json(403, { error: 'not allowed' });
  }
  if (p.status === 'paid') return json(200, { ok: true, already: true, kind: p.kind });
  const w = await platformWhish(env);
  if (!w) return json(400, { error: 'الدفع الإلكتروني غير مفعّل' });
  let st;
  try { st = await w.client.getPaymentStatus('USD', Number(p.id)); }
  catch (e) { console.error('addon verify failed', e); return json(502, { error: 'ما قدرنا نتحقق من الدفعة عند Whish' }); }
  if (st.collectStatus !== 'success') return json(200, { ok: false, status: st.collectStatus || 'pending' });
  if (!amountOk(w, st.amount, Number(p.amount_usd), 'USD')) return json(400, { error: 'المبلغ غير مطابق' });
  try { await addonProvision(env, p.id, st.transactionId); }
  catch (e) { return json(500, { error: 'تعذّر التفعيل: ' + e.message }); }
  return json(200, { ok: true, activated: true, kind: p.kind });
}
async function addonCallbackSuccess(request, env) {
  const { externalId, currency } = parseCallbackUrl(request.url) || {};
  if (!externalId) return json(400, { error: 'malformed callback' });
  const p = await addonRow(env, externalId);
  if (!p) return json(404, { error: 'unknown purchase' });
  if (p.status === 'paid') return json(200, { ok: true, already: true });
  const w = await platformWhish(env);
  if (!w) return json(400, { error: 'no platform credentials' });
  let st;
  try { st = await w.client.getPaymentStatus(currency || 'USD', Number(externalId)); }
  catch (e) { return json(502, { error: 'status check failed' }); }
  if (st.collectStatus !== 'success') return json(400, { error: 'not confirmed' });
  if (!amountOk(w, st.amount, Number(p.amount_usd), currency)) return json(400, { error: 'amount mismatch' });
  try { await addonProvision(env, p.id, st.transactionId); } catch (e) { return json(500, { error: 'provision failed' }); }
  return json(200, { ok: true });
}
async function addonCallbackFailure(request, env) {
  const { externalId } = parseCallbackUrl(request.url) || {};
  if (!externalId) return json(400, { error: 'malformed callback' });
  await sbPatch(env, `addon_purchases?id=eq.${Number(externalId)}&status=eq.awaiting_payment`, { status: 'failed' });
  return json(200, { ok: true });
}

// ============================================================
//  استقبال مواقع أجهزة التتبع
//  بيقبل: تطبيق Traccar Client (القديم والجديد) · Traccar Server forward
//         · أي جهاز GPS بيبعت HTTP بصيغة OsmAnd أو JSON
// ============================================================
function numOr(v) { const n = Number(v); return (v === null || v === undefined || v === '' || !isFinite(n)) ? null : n; }
function parseFix(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  let d;
  if (isFinite(n)) d = new Date(n > 1e12 ? n : n * 1000);   // ثواني أو ميلي ثانية
  else d = new Date(String(v));
  return isNaN(d.getTime()) ? null : d.toISOString();
}
async function trackPush(request, env, url) {
  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_KEY) return json(500, { error: 'server not configured' });
  const q = Object.fromEntries(url.searchParams);
  let p = { ...q }, j = null;

  if (request.method === 'POST') {
    const ct = (request.headers.get('content-type') || '').toLowerCase();
    const raw = await request.text();
    if (raw.length > 20000) return json(413, { error: 'too large' });
    if (ct.includes('json') || /^\s*[\[{]/.test(raw)) {
      try { j = JSON.parse(raw); } catch { return json(400, { error: 'bad json' }); }
      if (Array.isArray(j)) j = j[j.length - 1] || {};
    } else if (raw) {
      Object.assign(p, Object.fromEntries(new URLSearchParams(raw)));
    }
  }

  let id, lat, lng, kmh = null, heading = null, battery = null, fix = null;

  if (j && j.location && j.location.coords) {
    // Traccar Client الجديد (v9+): السرعة بالمتر/ثانية
    const c = j.location.coords;
    id = j.device_id || j.id || p.id;
    lat = numOr(c.latitude); lng = numOr(c.longitude);
    const ms = numOr(c.speed); kmh = ms !== null && ms >= 0 ? ms * 3.6 : null;
    heading = numOr(c.heading);
    const lvl = j.location.battery && numOr(j.location.battery.level);
    battery = lvl !== null && lvl !== undefined && lvl >= 0 ? (lvl <= 1 ? lvl * 100 : lvl) : null;
    fix = parseFix(j.location.timestamp);
  } else if (j && j.position) {
    // Traccar Server forward (json): السرعة بالعقدة
    const ps = j.position, dv = j.device || {};
    id = dv.uniqueId || p.id;
    lat = numOr(ps.latitude); lng = numOr(ps.longitude);
    const kn = numOr(ps.speed); kmh = kn !== null ? kn * 1.852 : null;
    heading = numOr(ps.course);
    battery = ps.attributes ? numOr(ps.attributes.batteryLevel) : null;
    fix = parseFix(ps.fixTime || ps.deviceTime);
  } else {
    // OsmAnd (Traccar Client القديم وأغلب الأجهزة): السرعة بالعقدة
    const s = j ? { ...p, ...j } : p;
    id = s.id || s.deviceid || s.device_id || s.imei;
    lat = numOr(s.lat ?? s.latitude); lng = numOr(s.lon ?? s.lng ?? s.longitude);
    if (s.speed_kmh !== undefined) kmh = numOr(s.speed_kmh);
    else { const kn = numOr(s.speed); kmh = kn !== null ? kn * 1.852 : null; }
    heading = numOr(s.bearing ?? s.heading ?? s.course);
    battery = numOr(s.batt ?? s.battery);
    fix = parseFix(s.timestamp ?? s.time ?? s.fixtime);
  }

  if (!id || lat === null || lng === null) return json(400, { error: 'missing id/lat/lon' });

  const r = await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/device_ping`, {
    method: 'POST',
    headers: { ...sbHeaders(env), 'Content-Type': 'application/json' },
    body: JSON.stringify({
      p_identifier: String(id).slice(0, 64), p_key: String(p.key || (j && j.key) || ''),
      p_lat: lat, p_lng: lng,
      p_speed_kmh: kmh === null ? null : Math.round(kmh * 10) / 10,
      p_heading: heading, p_battery: battery, p_fix_at: fix
    })
  });
  if (!r.ok) { console.error('device_ping', r.status, await r.text()); return json(500, { error: 'db error' }); }
  const result = await r.json();
  // منرجّع 200 دايماً لحتى التطبيق ما يضل يعيد نفس النقطة بلا نهاية
  return json(200, { result });
}

// ---------- أي صفحة نعرض لأي مسار ----------
function pageFor(pathname) {
  var p = pathname.replace(/\/+$/, '') || '/';
  if (p === '/')              return '/index.html';
  if (p === '/menus')         return '/product-menus.html';
  if (p === '/industrial')    return '/product-industrial.html';
  if (p === '/menus-info')    return '/product-menus.html';
  if (p === '/trade-info')    return '/product-trade.html';
  if (p === '/signup')        return '/signup.html';
  if (p === '/login')         return '/login.html';
  if (p === '/account')       return '/account.html';
  if (p === '/alum')          return '/app-alum.html';
  if (p === '/trade')         return '/app-trade.html';
  if (p === '/store-info' || p === '/portal-store') return '/product-store.html';
  if (/^\/portal-store\/[^/]+\/admin\/?$/.test(p)) return '/store-admin.html';
  if (/^\/portal-store\/[^/]+\/?$/.test(p)) return '/store.html';
  if (p.startsWith('/i/'))    return '/invoice.html';
  if (p === '/t' || p.startsWith('/t/')) return '/track.html';    // رابط تتبع الطلب للزبون
  if (p === '/d' || p.startsWith('/d/')) return '/driver.html';   // صفحة موظف التوصيل
  // رابط لوحة تحكم مطعم محدد: /اسم-المحل/admin
  if (/^\/[^/]+\/admin\/?$/.test(p)) return '/admin.html';
  // رابط برنامج ألمنيوم مخصص لزبون معيّن: /portal/اسم-محله
  if (/^\/portal\/[^/]+\/?$/.test(p))  return '/app-alum.html';
  // رابط برنامج تجارة مخصص لزبون معيّن: /portal-trade/اسم-محله
  if (/^\/portal-trade\/[^/]+\/?$/.test(p)) return '/app-trade.html';
  if (p.startsWith('/admin')) return '/admin.html';
  if (p.startsWith('/super')) return '/super.html';
  return '/menu.html';   // أي مسار آخر = رابط مطعم
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // 0) الصور — قبل أي شي، لتنخدم من الكاش
    if (url.pathname.startsWith('/img/')) return imageProxy(request, env, ctx, url);

    // 0.5) أي طلب لـ sw.js تحت أي مسار (كان ممكن ينسجّل من مكان مختلف قبل هيك)
    //      لازم ياخد نفس ملف الإلغاء الحقيقي، مش يروح غلط لصفحة تانية
    if (url.pathname.endsWith('/sw.js') || url.pathname === '/sw.js') {
      const swAsset = await env.ASSETS.fetch(new Request(new URL('/sw.js', url), request));
      if (swAsset.status !== 404) {
        const h = new Headers(swAsset.headers);
        h.set('Cache-Control', 'no-cache, no-store, must-revalidate');
        h.set('Content-Type', 'application/javascript; charset=utf-8');
        return new Response(swAsset.body, { status: swAsset.status, headers: h });
      }
    }

    // 1) الـAPI — أي مسار تحت /api/ يرجّع JSON دائماً، حتى لو صار خطأ داخلي
    if (url.pathname.startsWith('/api/')) {
      try {
        if (url.pathname === '/api/addon/pay') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await addonPay(request, env);
        }
        if (url.pathname === '/api/addon/verify') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await addonVerify(request, env);
        }
        if (url.pathname === '/api/addon/callback-success') return await addonCallbackSuccess(request, env);
        if (url.pathname === '/api/addon/callback-failure') return await addonCallbackFailure(request, env);
        if (url.pathname === '/api/track/osmand' || url.pathname === '/api/track/push') {
          return await trackPush(request, env, url);
        }
        if (url.pathname === '/api/store-invoice') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await storeInvoice(request, env);
        }
        if (url.pathname === '/api/whish/create') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await whishCreate(request, env);
        }
        if (url.pathname === '/api/whish/callback-success') return await whishSuccess(request, env);
        if (url.pathname === '/api/whish/callback-failure') return await whishFailure(request, env);
        if (url.pathname === '/api/store/pay/create') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await payCreate(request, env);
        }
        if (url.pathname === '/api/store/pay/verify') return await payVerify(request, env);
        if (url.pathname === '/api/store/pay/webhook') return await payWebhook(request, env);
        if (url.pathname === '/api/store/import-image') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await importImage(request, env);
        }
        if (url.pathname === '/api/store/pay/test') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await payTest(request, env);
        }
        if (url.pathname === '/api/store/whish/callback-success') return await storeWhishSuccess(request, env);
        if (url.pathname === '/api/store/whish/callback-failure') return await storeWhishFailure(request, env);
        if (url.pathname === '/api/store/domain') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await storeDomain(request, env);
        }
        if (url.pathname === '/api/buy/create') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await buyCreate(request, env);
        }
        if (url.pathname === '/api/buy/verify') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await buyVerify(request, env);
        }
        if (url.pathname === '/api/buy/callback-success') return await buySuccess(request, env);
        if (url.pathname === '/api/buy/callback-failure') return await buyFailure(request, env);
        if (url.pathname === '/api/create-owner') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await createOwner(request, env);
        }
        if (url.pathname === '/api/admin/new-license') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await adminNewLicense(request, env);
        }
        if (url.pathname === '/api/admin/extend-license') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await adminExtendLicense(request, env);
        }
        if (url.pathname === '/api/mfa/backup-codes/generate') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await mfaBackupGenerate(request, env);
        }
        if (url.pathname === '/api/mfa/backup-codes/status') return await mfaBackupStatus(request, env);
        if (url.pathname === '/api/mfa/backup-codes/verify') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await mfaBackupVerify(request, env);
        }
        if (url.pathname === '/api/mfa/backup-codes/clear') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await mfaBackupClear(request, env);
        }
        if (url.pathname === '/api/admin/mfa-status') return await adminMfaStatus(request, env);
        if (url.pathname === '/api/admin/mfa-disable') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await adminMfaDisable(request, env);
        }
        if (url.pathname === '/api/admin/delete-client') {
          if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
          return await adminDeleteClient(request, env);
        }
        if (url.pathname === '/api/portal-token') {
          if (request.method !== 'GET') return json(405, { error: 'method not allowed' });
          return await portalToken(request, env);
        }
        if (url.pathname === '/api/portal-client') {
          if (request.method !== 'GET') return json(405, { error: 'method not allowed' });
          return await portalClient(request, env);
        }
        return json(404, { error: 'unknown endpoint: ' + url.pathname });
      } catch (e) {
        console.error('API error on', url.pathname, e);
        return json(500, {
          error: (e && (e.message || e.code)) || 'internal error',
          where: url.pathname
        });
      }
    }

    // 1.5) دومين خاص بمتجر زبون — أي مسار غير الـAPI والصور بيعرض متجره
    if (!isPlatformHost(url.hostname, env)) {
      const slug = await resolveDomain(env, ctx, url.hostname.toLowerCase());
      if (slug === undefined) return new Response('Temporary error, try again', { status: 503 });
      if (!slug) {
        return new Response('This domain is not connected to any store.', {
          status: 404, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
      }
      if (url.pathname.replace(/\/+$/, '').endsWith('/admin')) {
        return Response.redirect(`${env.WEBSITE_URL}/portal-store/${slug}/admin`, 302);
      }
      if (/\.[a-z0-9]{2,5}$/i.test(url.pathname)) {
        return new Response('Not found', { status: 404, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
      }
      return await serveStore(env, url, slug);
    }

    // 2) طلب لملف حقيقي (فيه امتداد صريح متل .css / .js / .png) — نخدمه متل ما هو
    if (/\.[a-z0-9]{2,5}$/i.test(url.pathname)) {
      const asset = await env.ASSETS.fetch(request);
      if (asset.status !== 404) return withCache(asset, url.pathname);
      // ملف ناقص — نرجّع 404 صريح بدل ما نرجّع HTML
      // وإلا بيوصل للمتصفح HTML مكان css/js والصفحة بتطلع بيضا بلا سبب واضح
      return new Response('Not found: ' + url.pathname, {
        status: 404,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' }
      });
    }

    // 3) مسار صفحة (بدون امتداد) — نحدد الصفحة الصحيحة بأنفسنا دايماً،
    //    بدون ما نسأل Cloudflare مباشرة (تفادياً لأي تخمين افتراضي غير متوقع منه)
    const page = pageFor(url.pathname);
    const res = await env.ASSETS.fetch(new URL(page, url.origin));
    return new Response(res.body, {
      status: 200,
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-cache'
      }
    });
  }
};
