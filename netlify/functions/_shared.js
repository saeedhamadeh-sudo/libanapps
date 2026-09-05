// ============================================================
//  مساعد مشترك للدوال — يستعمل مفتاح service_role
//  هذا الملف يعمل على السيرفر فقط ولا يصل للمتصفح أبداً
// ============================================================
const { createClient } = require('@supabase/supabase-js');

function db() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_KEY;
  if (!url || !key) throw new Error('Missing SUPABASE_URL / SUPABASE_SERVICE_KEY');
  return createClient(url, key, { auth: { persistSession: false } });
}

function json(statusCode, body) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    body: JSON.stringify(body)
  };
}

// حارس: يمنع تشغيل الدفع الحقيقي على بيئة الاختبار بالغلط
function assertProduction() {
  if (process.env.NODE_ENV !== 'production') {
    throw new Error('NODE_ENV is not "production" — Whish would run in sandbox mode');
  }
}

module.exports = { db, json, assertProduction };
