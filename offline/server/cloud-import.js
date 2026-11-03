// ============================================================
//  نقل بيانات برنامج (ألمنيوم / تجارة) من السحابة للكمبيوتر — مرة وحدة
//  بيدخل على السحابة بنفس الطريقة يلي بيدخل فيها البرنامج (حساب libanapps.com +
//  مستخدم البرنامج)، بيسحب كل الجداول، وبيحفظها بالقاعدة المحلية.
// ============================================================
'use strict';
const { sbFetch } = require('./license');
const { TABLES } = require('./data');

async function importFromCloud(engine, license, product, username, password, totp, onProgress){
  if(!TABLES[product]) throw new Error('برنامج غير معروف');
  const tok = await license.token();
  const cid = license.clientId();
  const prog = onProgress || (() => {});

  prog('تسجيل الدخول عالسحابة...');
  const lr = await license.rpc('app_login', { p_product: product, p_username: username, p_password: password, p_totp: totp || null }, tok);
  let loggedIn = false;
  if(lr.ok && lr.data && lr.data.ok){
    if(lr.data.kind !== 'staff' || !['admin', 'superuser'].includes(lr.data.account && lr.data.account.role))
      throw new Error('لازم تدخل بحساب مدير (admin) لحتى ينسحبو كل البيانات');
    loggedIn = true;
  } else if(lr.ok && lr.data && lr.data.need_totp){
    throw new Error('هالحساب عليه رمز 2FA — حط الرمز من تطبيق المصادقة');
  } else {
    const m = await license.rpc('app_mode', {}, tok);
    if(m.ok && m.data && m.data.secure) throw new Error(lr.data && lr.data.reason === 'locked' ? 'محاولات كتيرة — جرّب بعد ١٥ دقيقة' : 'اسم المستخدم أو كلمة السر غلط');
  }

  const tables = {};
  try{
    for(const t of TABLES[product]){
      const tbl = product + '_' + t;
      const rows = [];
      for(let off = 0; ; off += 1000){
        prog('عم نسحب ' + t + ' (' + rows.length + ')...');
        const order = t === 'app_settings' ? '' : '&order=id.asc';
        const r = await sbFetch('/rest/v1/' + tbl + '?select=*&client_id=eq.' + encodeURIComponent(cid) + order + '&offset=' + off + '&limit=1000',
          { headers: { Authorization: 'Bearer ' + tok }, timeout: 60000 });
        if(r.status === 404 || (r.data && r.data.code === '42P01')) break;   // جدول مش موجود بالسحابة
        if(!r.ok) throw new Error('تعذّر سحب ' + t + ': ' + ((r.data && r.data.message) || r.status));
        rows.push(...(r.data || []));
        if(!r.data || r.data.length < 1000) break;
      }
      tables[t] = rows;
    }
  } finally {
    if(loggedIn) await license.rpc('app_logout', { p_product: product }, tok).catch(() => {});
  }

  prog('عم نحفظ عالكمبيوتر...');
  engine.replaceProductData(product, tables);
  // كلمات السر بالسحابة مشفّرة وما بتنقرى — منحط كلمة سر المستخدم يلي دخل هلق، والباقي بيتعيّن من «المستخدمين»
  const me = engine.findAccount(product + '_app_users', username);
  if(me) engine.setPassword(product, me.__pk, password);
  const counts = {}; Object.keys(tables).forEach(k => { counts[k] = tables[k].length; });
  return { ok: true, counts };
}

module.exports = { importFromCloud };
