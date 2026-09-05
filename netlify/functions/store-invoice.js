// ============================================================
//  POST /api/store-invoice
//  body: { token, pdf_base64 }
//  يرفع الفاتورة إلى bucket "invoices" ويحفظ الرابط بالطلب
// ============================================================
const { db, json } = require('./_shared');

const MAX_BYTES = 3 * 1024 * 1024; // 3MB

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return json(405, { error: 'method not allowed' });

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return json(400, { error: 'bad json' }); }

  const { token, pdf_base64 } = body;
  if (!token || !pdf_base64) return json(400, { error: 'missing fields' });

  const bytes = Buffer.from(pdf_base64, 'base64');
  if (!bytes.length || bytes.length > MAX_BYTES) return json(400, { error: 'bad file size' });
  // التأكد أنه ملف PDF فعلاً
  if (bytes.slice(0, 4).toString() !== '%PDF') return json(400, { error: 'not a pdf' });

  const sb = db();

  const { data: order, error } = await sb
    .from('orders')
    .select('id, order_no, invoice_pdf_url')
    .eq('token', token)
    .maybeSingle();

  if (error || !order) return json(404, { error: 'order not found' });

  // مولّدة من قبل — نرجّع الرابط الموجود بدل ما نكتب فوقه
  if (order.invoice_pdf_url) return json(200, { url: order.invoice_pdf_url, cached: true });

  const path = `${order.id}-${order.order_no}.pdf`;

  const up = await sb.storage.from('invoices').upload(path, bytes, {
    contentType: 'application/pdf',
    upsert: false
  });
  if (up.error && !String(up.error.message).includes('exists')) {
    return json(500, { error: 'upload failed' });
  }

  const { data: pub } = sb.storage.from('invoices').getPublicUrl(path);
  const url = pub.publicUrl;

  await sb.from('orders').update({ invoice_pdf_url: url }).eq('id', order.id);

  return json(200, { url });
};
