// ============================================================
//  GET /api/whish/callback-failure
// ============================================================
const { parseCallbackUrl } = require('whish-pay');
const { db, json } = require('./_shared');

exports.handler = async (event) => {
  const site = process.env.WEBSITE_URL;
  const full = `${site}${event.path}${event.rawQuery ? '?' + event.rawQuery : ''}`;

  const { externalId, errorCode, errorMessage } = parseCallbackUrl(full) || {};
  if (!externalId) return json(400, { error: 'malformed callback' });

  const sb = db();

  // لا نلمس الطلبات المدفوعة أبداً
  await sb.from('orders')
    .update({ status: 'failed' })
    .eq('id', Number(externalId))
    .eq('status', 'awaiting_payment');

  console.log('payment failed', { externalId, errorCode, errorMessage });
  return json(200, { ok: true });
};
