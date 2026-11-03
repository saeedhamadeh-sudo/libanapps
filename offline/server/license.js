// ============================================================
//  الترخيص — النسخة المحلية بتتأكد من الاشتراك من libanapps.com
//  · صاحب المحل بيسجّل دخول مرة وحدة بحساب libanapps.com
//  · البرنامج بيتحقق من الاشتراك كل ٦ ساعات إذا في إنترنت
//  · بلا إنترنت: بيكمّل شغل لحد GRACE_DAYS من آخر تحقق ناجح
//  · أو تفعيل بلا إنترنت أبداً برقم تفعيل موقّع HMDH1 (نفس أرقام البرنامج)
// ============================================================
'use strict';
const crypto = require('crypto');

const SB_URL = 'https://moriwmhlgugmjzddwfgv.supabase.co';
const SB_ANON = 'sb_publishable_ypfm_aulpcqBpeFpyD_7iw_mA4DNlR5';
const GRACE_DAYS = 10;
const LICENSE_PUBLIC_JWK = { kty: 'EC', crv: 'P-256', x: 'E9z9bLEvr9oDV_jpdky7p1lqO7oumiEiLMRo2Q9fmLA', y: 'JQIHnNDyTcEKGSlFjfI_BlhPijabEh22t2uVn1SJ4_E' };

async function sbFetch(path, opts){
  const o = opts || {};
  const headers = Object.assign({ apikey: SB_ANON, 'Content-Type': 'application/json' }, o.headers || {});
  const ctl = new AbortController(); const tm = setTimeout(() => ctl.abort(), o.timeout || 20000);
  try{
    const r = await fetch(SB_URL + path, { method: o.method || 'GET', headers, body: o.body, signal: ctl.signal });
    const txt = await r.text(); let j = null; try{ j = txt ? JSON.parse(txt) : null; }catch(e){ j = txt; }
    return { status: r.status, ok: r.ok, data: j, headers: r.headers };
  } finally { clearTimeout(tm); }
}

function verifySerial(serial){
  try{
    const parts = String(serial || '').trim().split('.');
    if(parts.length !== 3 || parts[0] !== 'HMDH1') return null;
    const key = crypto.createPublicKey({ key: LICENSE_PUBLIC_JWK, format: 'jwk' });
    const sig = Buffer.from(parts[2].replace(/-/g, '+').replace(/_/g, '/'), 'base64');
    const ok = crypto.verify('sha256', Buffer.from(parts[1]), { key, dsaEncoding: 'ieee-p1363' }, sig);
    if(!ok) return null;
    const payload = JSON.parse(Buffer.from(parts[1].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8'));
    return payload && typeof payload.exp === 'number' ? payload : null;
  }catch(e){ return null; }
}

class License {
  constructor(store){
    this.store = store;
    this._timer = null;
    this.lastError = '';
  }
  get state(){ return this.store.kvGet('license', {}); }
  set state(v){ this.store.kvSet('license', v); }
  clientId(){
    const s = this.state;
    if(s.client_id) return s.client_id;
    let local = this.store.kvGet('local_client_id', null);
    if(!local){ local = crypto.randomUUID(); this.store.kvSet('local_client_id', local); }
    return local;
  }
  // حماية بسيطة من ترجيع ساعة الكمبيوتر لورا
  _now(){
    const now = Date.now(), seen = this.store.kvGet('max_seen_time', 0);
    if(now > seen) this.store.kvSet('max_seen_time', now);
    return { now, tampered: seen - now > 2 * 86400000 };
  }

  // ---------- app_access: نفس شكل الرد يلي بالسحابة ----------
  access(product){
    const s = this.state, cid = this.clientId();
    const { now, tampered } = this._now();
    if(tampered) return { ok: false, reason: 'error', client_id: cid, message: 'ساعة الكمبيوتر مش مظبوطة — صحّح التاريخ والوقت' };
    const build = (exp, plan) => {
      const left = Math.max(0, Math.ceil((exp - now) / 86400000));
      return { ok: exp > now, reason: exp > now ? 'active' : 'expired', client_id: cid, plan: plan || 'paid', trial: plan === 'trial',
        expires_at: new Date(exp).toISOString(), days_left: left, local: true };
    };
    if(s.mode === 'serial'){
      const p = verifySerial(s.serial);
      if(!p) return { ok: false, reason: 'no_subscription', client_id: cid };
      return build(p.exp, 'serial');
    }
    if(s.mode === 'cloud'){
      const a = (s.products || {})[product];
      if(!a || !a.client_id) return { ok: false, reason: a && a.reason === 'no_client' ? 'no_client' : 'no_subscription', client_id: cid };
      if(now - (s.checked_at || 0) > GRACE_DAYS * 86400000)
        return { ok: false, reason: 'error', client_id: cid, message: 'لازم يتصل الكمبيوتر بالإنترنت مرة كل ' + GRACE_DAYS + ' أيام ليتأكد من الاشتراك' };
      if(a.reason === 'suspended') return { ok: false, reason: 'suspended', client_id: cid };
      if(!a.expires_at) return { ok: false, reason: a.reason || 'no_subscription', client_id: cid };
      return build(new Date(a.expires_at).getTime(), a.plan);
    }
    return { ok: false, reason: 'no_client', client_id: cid };
  }
  summary(){
    const s = this.state;
    return { mode: s.mode || null, email: s.email || '', checked_at: s.checked_at || 0, lastError: this.lastError,
      alum: this.access('alum'), trade: this.access('trade') };
  }

  // ---------- تسجيل دخول صاحب المحل بحساب libanapps.com ----------
  async signIn(email, password){
    const r = await sbFetch('/auth/v1/token?grant_type=password', { method: 'POST', body: JSON.stringify({ email, password }) });
    if(!r.ok) throw new Error((r.data && (r.data.error_description || r.data.msg || r.data.message)) || 'الإيميل أو كلمة السر غلط');
    const s = Object.assign({}, this.state, { mode: 'cloud', email, refresh_token: r.data.refresh_token });
    this.state = s;
    this._access_token = r.data.access_token;
    this._token_exp = Date.now() + (r.data.expires_in || 3600) * 1000 - 60000;
    await this.refresh();
    this.start();
    return this.summary();
  }
  activateSerial(serial){
    const p = verifySerial(serial);
    if(!p) throw new Error('رقم التفعيل غير صحيح');
    if(p.exp <= Date.now()) throw new Error('رقم التفعيل منتهي الصلاحية');
    this.state = Object.assign({}, this.state, { mode: 'serial', serial: String(serial).trim(), label: p.label || '' });
    return this.summary();
  }
  signOut(){
    const s = this.state; const keep = s.client_id ? { client_id: s.client_id } : {};
    this.state = keep; this._access_token = null;
  }
  // رمز دخول صالح للسحابة (بيتجدّد تلقائياً)
  async token(){
    if(this._access_token && Date.now() < this._token_exp) return this._access_token;
    const s = this.state;
    if(s.mode !== 'cloud' || !s.refresh_token) throw new Error('ما في حساب libanapps.com مربوط');
    const r = await sbFetch('/auth/v1/token?grant_type=refresh_token', { method: 'POST', body: JSON.stringify({ refresh_token: s.refresh_token }) });
    if(!r.ok){
      if(r.status === 400 || r.status === 401) { this.lastError = 'انتهت جلسة حساب libanapps.com — سجّل دخول من جديد'; }
      throw new Error(this.lastError || 'تعذّر تجديد الجلسة');
    }
    this.state = Object.assign({}, s, { refresh_token: r.data.refresh_token });
    this._access_token = r.data.access_token;
    this._token_exp = Date.now() + (r.data.expires_in || 3600) * 1000 - 60000;
    return this._access_token;
  }
  async rpc(name, args, tok){
    const t = tok || await this.token();
    return sbFetch('/rest/v1/rpc/' + name, { method: 'POST', headers: { Authorization: 'Bearer ' + t }, body: JSON.stringify(args || {}) });
  }
  // التحقق من الاشتراك بالسحابة
  async refresh(){
    const s = this.state;
    if(s.mode !== 'cloud') return this.summary();
    try{
      const products = {};
      let cid = s.client_id || null;
      for(const p of ['alum', 'trade']){
        let r = await this.rpc('app_access', { p_product: p });
        if(r.ok && r.data && r.data.reason === 'no_client'){ await this.rpc('autolink_my_client', {}); r = await this.rpc('app_access', { p_product: p }); }
        if(!r.ok) throw new Error((r.data && r.data.message) || ('HTTP ' + r.status));
        products[p] = r.data || {};
        if(r.data && r.data.client_id) cid = r.data.client_id;
      }
      if(s.client_id && cid && s.client_id !== cid){
        // حساب تاني غير يلي انربط فيه البرنامج أول مرة — منمنع خلط بيانات مؤسستين
        throw new Error('هالحساب لمؤسسة تانية غير المؤسسة يلي على هالكمبيوتر');
      }
      this.state = Object.assign({}, this.state, { products, client_id: cid || this.clientId(), checked_at: Date.now() });
      this.lastError = '';
    }catch(e){
      this.lastError = (e && e.name === 'AbortError') ? 'ما في اتصال بالإنترنت' : String(e && e.message || e);
      if(/fetch failed|ENOTFOUND|ECONN|EAI_AGAIN/i.test(this.lastError)) this.lastError = 'ما في اتصال بالإنترنت';
      if(/مؤسسة تانية/.test(this.lastError)) { this.signOut(); throw e; }
    }
    return this.summary();
  }
  start(){
    clearInterval(this._timer);
    this._timer = setInterval(() => { this.refresh().catch(() => {}); }, 6 * 3600 * 1000);
    if(this._timer.unref) this._timer.unref();
  }
}

module.exports = { License, sbFetch, SB_URL, SB_ANON, verifySerial };
