// ============================================================
//  نسخة «للقراءة بس» على السحابة — للزباين والعمال
//  كل ١٠ دقايق (إذا في نت وحساب libanapps.com مربوط) بيرفع:
//   · لكل حساب زبون: الزبون + فواتيرو + إيصالاتو
//   · لكل حساب عامل: العامل + يومياتو + دفعاتو
//   · إعدادات البرنامج (لشاشة الدخول)
//  لما الكمبيوتر يكون مطفي، libanapps.com بيفتح البرنامج من هالنسخة للقراءة بس.
//  بيرفع بس إذا في شي تغيّر.
// ============================================================
'use strict';
const crypto = require('crypto');

const PRODUCTS = ['alum', 'trade'];

class Mirror {
  constructor(store, license){
    this.store = store; this.license = license;
    this.running = false; this.lastError = '';
  }
  get enabled(){ return this.store.kvGet('mirror_on', true) !== false; }
  setEnabled(on){ this.store.kvSet('mirror_on', !!on); if(on) this.run(true).catch(() => {}); return this.status(); }
  status(){
    return { enabled: this.enabled, last: this.store.kvGet('mirror_last', null), lastError: this.lastError,
      available: this.license.state.mode === 'cloud' };
  }
  _rows(tbl){ return this.store.all('SELECT data FROM rows WHERE tbl=?', tbl).map(r => JSON.parse(r.data)); }
  _secret(tbl, id){ const r = this.store.get('SELECT password_hash FROM secrets WHERE tbl=? AND id=?', tbl, String(id)); return r && r.password_hash; }

  build(product){
    const P = t => product + '_' + t;
    const strip = r => { const o = Object.assign({}, r); delete o.password; delete o.totp_secret; return o; };
    const items = [];
    const settings = this._rows(P('app_settings'))[0];
    items.push({ kind: 'settings', username: '', payload: { app_settings: settings ? [settings] : [] } });

    const custAcc = this._rows(P('customer_accounts'));
    if(custAcc.length){
      const customers = this._rows(P('customers')), invoices = this._rows(P('invoices')), receipts = this._rows(P('receipts'));
      for(const a of custAcc){
        const hash = this._secret(P('customer_accounts'), a.id);
        if(!a.username || !hash || !/^\$2a\$/.test(hash)) continue;   // بلا كلمة سر bcrypt ما منقدر نفحصها بالسحابة
        const cid = String(a.customer_id);
        items.push({ kind: 'customer', username: a.username, account: strip(a), password_hash: hash, payload: {
          customers: customers.filter(c => String(c.id) === cid),
          invoices: invoices.filter(r => String(r.customer_id) === cid),
          receipts: receipts.filter(r => String(r.customer_id) === cid)
        } });
      }
    }
    const workAcc = this._rows(P('worker_accounts'));
    if(workAcc.length){
      const workers = this._rows(P('workers')), entries = this._rows(P('work_entries')), pays = this._rows(P('worker_payments'));
      for(const a of workAcc){
        const hash = this._secret(P('worker_accounts'), a.id);
        if(!a.username || !hash || !/^\$2a\$/.test(hash)) continue;
        const wid = String(a.worker_id);
        items.push({ kind: 'worker', username: a.username, account: strip(a), password_hash: hash, payload: {
          workers: workers.filter(w => String(w.id) === wid),
          work_entries: entries.filter(r => String(r.worker_id) === wid),
          worker_payments: pays.filter(r => String(r.worker_id) === wid)
        } });
      }
    }
    return items;
  }

  async run(force){
    if(this.running || !this.enabled || this.license.state.mode !== 'cloud') return this.status();
    this.running = true;
    try{
      const sent = this.store.kvGet('mirror_hashes', {});
      let pushed = 0, accounts = 0;
      for(const p of PRODUCTS){
        const items = this.build(p);
        accounts += items.length - 1;
        const h = crypto.createHash('sha256').update(JSON.stringify(items)).digest('hex');
        if(!force && sent[p] === h) continue;
        const r = await this.license.rpc('local_mirror_push', { p_product: p, p_items: items });
        if(!r.ok) throw new Error((r.data && (r.data.message || r.data.hint)) || ('HTTP ' + r.status));
        if(r.data && r.data.ok === false) throw new Error(r.data.reason || 'رفض');
        sent[p] = h; pushed++;
      }
      this.store.kvSet('mirror_hashes', sent);
      this.store.kvSet('mirror_last', { at: Date.now(), accounts, pushed });
      this.lastError = '';
    }catch(e){
      const m = String(e && e.message || e);
      this.lastError = /fetch failed|ENOTFOUND|EAI_AGAIN|ECONN|abort/i.test(m) ? 'ما في اتصال بالإنترنت' :
        /local_mirror_push|PGRST202/.test(m) ? 'لازم تشغّل db/upgrade-local-mirror.sql على Supabase' : m;
    }finally{ this.running = false; }
    return this.status();
  }
  start(){
    setTimeout(() => this.run().catch(() => {}), 45000);
    this._t = setInterval(() => this.run().catch(() => {}), 10 * 60000);
    if(this._t.unref) this._t.unref();
  }
}

module.exports = { Mirror };
