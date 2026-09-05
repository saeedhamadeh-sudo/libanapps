// ============================================================
//  GET /api/whish/callback-success
//  Whish ينادي هذا الرابط من سيرفره. لا نثق بالمعطيات القادمة:
//  نستعلم عن حالة الدفعة من Whish ونقارن المبلغ بسجلنا.
// ============================================================
const { WhishClient, parseCallbackUrl } = require('whish-pay');
const { db, json } = require('./_shared');

exports.handler = async (event) => {
  const site = process.env.WEBSITE_URL;
  const full = `${site}${event.path}${event.rawQuery ? '?' + event.rawQuery : ''}`;

  const parsed = parseCallbackUrl(full) || {};
  const { externalId, currency } = parsed;
  if (!externalId || !currency) return json(400, { error: 'malformed callback' });

  const sb = db();

  const { data: order } = await sb
    .from('orders')
    .select('id, restaurant_id, total_usd, total_lbp, status')
    .eq('id', Number(externalId))
    .maybeSingle();

  if (!order) return json(404, { error: 'unknown order' });

  // مدفوعة من قبل — لا نعيد المعالجة (Whish قد يكرّر النداء)
  if (order.status === 'paid') return json(200, { ok: true, already: true });

  const { data: cred } = await sb
    .from('payment_credentials').select('*').eq('restaurant_id', order.restaurant_id).maybeSingle();
  if (!cred) return json(400, { error: 'no credentials' });

  const whish = new WhishClient({
    channel: cred.whish_channel,
    secret: cred.whish_secret,
    websiteUrl: cred.website_url || site,
    environment: 'production'
  });

  let status;
  try {
    status = await whish.getPaymentStatus(currency, Number(externalId));
  } catch (e) {
    console.error('status check failed', e.code || e.message);
    return json(502, { error: 'status check failed' });
  }

  if (status.collectStatus !== 'success') {
    return json(400, { error: 'not confirmed', status: status.collectStatus });
  }

  // المبلغ لازم يطابق سجلنا
  const expected = currency === 'LBP' ? Number(order.total_lbp) : Number(order.total_usd);
  if (!whish.validateAmount(Number(status.amount), expected, currency)) {
    console.error('amount mismatch', { orderId: order.id, got: status.amount, expected });
    return json(400, { error: 'amount mismatch' });
  }

  await sb.from('orders').update({
    status: 'paid',
    paid_at: new Date().toISOString(),
    whish_txn_id: status.transactionId || null,
    whish_currency: currency
  }).eq('id', order.id).neq('status', 'paid');   // idempotent

  return json(200, { ok: true });
};
