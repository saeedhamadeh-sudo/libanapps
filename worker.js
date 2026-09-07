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

  const expected = currency === 'LBP' ? Number(order.total_lbp) : Number(order.total_usd);
  if (!w.client.validateAmount(Number(status.amount), expected, currency)) {
    console.error('amount mismatch', order.id, status.amount, expected);
    return json(400, { error: 'amount mismatch' });
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
  if (pathname.startsWith('/i/'))     return '/invoice.html';
  if (pathname.startsWith('/admin'))  return '/admin.html';
  if (pathname.startsWith('/super'))  return '/super.html';
  return '/menu.html';   // أي مسار آخر = رابط مطعم
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

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
