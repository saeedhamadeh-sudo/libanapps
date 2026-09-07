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

    // 1) الـAPI
    if (url.pathname === '/api/store-invoice') {
      if (request.method !== 'POST') return json(405, { error: 'method not allowed' });
      return storeInvoice(request, env);
    }

    // 2) ملف موجود؟ نخدمه كما هو
    const asset = await env.ASSETS.fetch(request);
    if (asset.status !== 404) return asset;

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
      headers: { 'Content-Type': 'text/html; charset=utf-8' }
    });
  }
};
