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
    `purchases?id=eq.${pid}&select=id,user_id,amount_usd,status,product_code&limit=1`);
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
  if (p.startsWith('/i/'))    return '/invoice.html';
  if (p.startsWith('/admin')) return '/admin.html';
  if (p.startsWith('/super')) return '/super.html';
  return '/menu.html';   // أي مسار آخر = رابط مطعم
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // 0) الصور — قبل أي شي، لتنخدم من الكاش
    if (url.pathname.startsWith('/img/')) return imageProxy(request, env, ctx, url);

    // 1) الـAPI — أي مسار تحت /api/ يرجّع JSON دائماً، حتى لو صار خطأ داخلي
    if (url.pathname.startsWith('/api/')) {
      try {
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
        return json(404, { error: 'unknown endpoint: ' + url.pathname });
      } catch (e) {
        console.error('API error on', url.pathname, e);
        return json(500, {
          error: (e && (e.message || e.code)) || 'internal error',
          where: url.pathname
        });
      }
    }

    // 2) ملف موجود؟ نخدمه كما هو
    const asset = await env.ASSETS.fetch(request);
    if (asset.status !== 404) return withCache(asset, url.pathname);

    // 3) ملف ناقص (له امتداد) — نرجّع 404 صريح بدل ما نرجّع HTML
    //    وإلا بيوصل للمتصفح HTML مكان css/js والصفحة بتطلع بيضا بلا سبب واضح
    if (/\.[a-z0-9]{2,5}$/i.test(url.pathname)) {
      return new Response('Not found: ' + url.pathname, {
        status: 404,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' }
      });
    }

    // 4) مسار صفحة، نعرض الصفحة المناسبة
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
