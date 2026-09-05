// ============================================================
//  POST /api/whish/create
//  body: { order_id, slug }
//  يقرأ بيانات Whish الخاصة بالمطعم ويُنشئ عملية دفع
// ============================================================
const { WhishClient } = require('whish-pay');
const { db, json, assertProduction } = require('./_shared');

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return json(405, { error: 'method not allowed' });

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return json(400, { error: 'bad json' }); }

  const { order_id, slug } = body;
  if (!order_id || !slug) return json(400, { error: 'missing fields' });

  try {
    assertProduction();
  } catch (e) {
    // نمنع الدفع بدل ما نقبض بالوهم على بيئة الاختبار
    return json(500, { error: e.message });
  }

  const sb = db();

  // 1) الطلب — المبلغ يؤخذ من قاعدة البيانات، لا من المتصفح
  const { data: order, error: oErr } = await sb
    .from('orders')
    .select('id, order_no, restaurant_id, total_usd, total_lbp, status, token')
    .eq('id', order_id)
    .maybeSingle();

  if (oErr || !order) return json(404, { error: 'order not found' });
  if (order.status === 'paid') return json(400, { error: 'already paid' });

  // 2) المطعم
  const { data: rest } = await sb
    .from('restaurants').select('id, slug, name_en').eq('id', order.restaurant_id).maybeSingle();
  if (!rest || rest.slug !== slug) return json(400, { error: 'restaurant mismatch' });

  // 3) بيانات Whish الخاصة بهذا المطعم (لا تُقرأ إلا هنا)
  const { data: cred } = await sb
    .from('payment_credentials').select('*').eq('restaurant_id', rest.id).maybeSingle();

  if (!cred || !cred.whish_enabled || !cred.whish_channel || !cred.whish_secret) {
    return json(400, { error: 'whish not configured for this restaurant' });
  }

  const currency = cred.whish_currency === 'LBP' ? 'LBP' : 'USD';
  const amount = currency === 'LBP' ? Number(order.total_lbp) : Number(order.total_usd);
  if (!(amount > 0)) return json(400, { error: 'invalid amount' });

  const site = process.env.WEBSITE_URL;

  const whish = new WhishClient({
    channel: cred.whish_channel,
    secret: cred.whish_secret,
    websiteUrl: cred.website_url || site,
    environment: 'production'
  });

  try {
    const result = await whish.createPayment({
      amount,
      currency,
      invoice: `${rest.name_en} — ${order.order_no}`,
      externalId: Number(order.id),          // معرّفنا الرقمي = رقم الطلب
      successCallbackUrl: `${site}/api/whish/callback-success`,
      failureCallbackUrl: `${site}/api/whish/callback-failure`,
      successRedirectUrl: `${site}/i/${encodeURIComponent(order.token)}`,
      failureRedirectUrl: `${site}/${rest.slug}?payment=failed`
    });

    if (!result.success) {
      return json(400, { error: result.dialog?.message || 'payment rejected', code: result.code });
    }

    await sb.from('orders')
      .update({ status: 'awaiting_payment', whish_currency: currency })
      .eq('id', order.id);

    return json(200, { collectUrl: result.collectUrl });

  } catch (e) {
    console.error('whish create failed', e.code || e.message);
    return json(502, { error: 'payment provider error' });
  }
};
