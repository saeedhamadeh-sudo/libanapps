// ============================================================
//  التحديث من libanapps.com — زر «تحديث» بالبرنامج المحلي
//  1) صفحات البرنامجين (app-alum / app-trade / assets):
//     بيقرا offline-update.json، بينزّل بس الملفات يلي تغيّرت، بيتأكد من بصمة كل ملف (sha256)،
//     وبيبدّل مرة وحدة. النسخة السابقة بتضل محفوظة للرجوع.
//  2) البرنامج نفسو (السيرفر المحلي): إذا في installer أحدث، بينزّلو، بيتأكد منو، وبيشغّلو.
//  البيانات ما بتتأثر أبداً بالتحديث.
// ============================================================
'use strict';
const fs = require('fs');
const path = require('path');
const { SAFE_PATH, sha256, cmpVer } = require('./manifest');

const SITE = process.env.LA_UPDATE_SITE || 'https://libanapps.com';   // للتجربة بس

async function get(url, ms){
  const r = await fetch(url, { signal: AbortSignal.timeout(ms || 30000), headers: { 'Cache-Control': 'no-cache' } });
  if(!r.ok) throw new Error('HTTP ' + r.status + ' — ' + url.replace(SITE, ''));
  return Buffer.from(await r.arrayBuffer());
}
function netMsg(e){
  const m = String(e && e.message || e);
  return /fetch failed|ENOTFOUND|EAI_AGAIN|ECONN|timeout|aborted/i.test(m) ? 'ما في اتصال بالإنترنت' : m;
}

class Updater {
  constructor(store, opts){
    this.store = store;
    this.bundled = opts.appDir;                       // الصفحات يلي إجت مع ملف التثبيت
    this.root = path.join(opts.dataDir, 'web-updates');
    this.tmp = path.join(opts.dataDir, 'tmp');
    this.localVersion = opts.version;
    this.onChange = opts.onChange || (() => {});
    this.runInstaller = opts.runInstaller || null;
    this.busy = false; this.progress = '';
    fs.mkdirSync(this.root, { recursive: true }); fs.mkdirSync(this.tmp, { recursive: true });
  }
  get state(){ return this.store.kvGet('web_update', { active: null, version: null, previous: null }); }
  set state(v){ this.store.kvSet('web_update', v); }
  activeDir(){ const a = this.state.active; return a ? path.join(this.root, a) : null; }
  // وين ملف معيّن هلق: بالتحديث إذا موجود، وإلا من ملف التثبيت
  resolve(rel){
    const d = this.activeDir();
    if(d && SAFE_PATH.test(rel)){ const p = path.join(d, rel); if(fs.existsSync(p)) return p; }
    return path.join(this.bundled, rel);
  }
  status(){
    const s = this.state, last = this.store.kvGet('update_last_check', null);
    return { localVersion: this.localVersion, webVersion: s.version || 'الأصلية (مع التثبيت)', canRollback: !!(s.previous || s.active),
      previousVersion: s.previous ? s.previous.version : (s.active ? 'الأصلية' : null), appliedAt: s.active ? (s.appliedAt || null) : null,
      busy: this.busy, progress: this.progress, last, auto: this.auto,
      pendingInstaller: (this.store.kvGet('pending_installer', null) || {}).version || null };
  }

  async check(){
    let m;
    try{
      // الأساس: الموقع بيحسب البصمات من الملفات المنشورة هلق — وإذا الـworker قديم: الملف الثابت
      try{ m = JSON.parse((await get(SITE + '/api/offline/manifest?t=' + Date.now(), 30000)).toString('utf8')); }
      catch(e1){ if(/HTTP 404/.test(String(e1 && e1.message)) || e1 instanceof SyntaxError) m = null; else throw e1; }
      if(!m || !Array.isArray(m.files)) m = JSON.parse((await get(SITE + '/offline-update.json?t=' + Date.now(), 20000)).toString('utf8'));
    }
    catch(e){
      const msg = /HTTP 404/.test(String(e && e.message)) ? 'ما في تحديثات منشورة على libanapps.com بعد' : netMsg(e);
      const r = { at: Date.now(), error: msg }; this.store.kvSet('update_last_check', r); return r;
    }
    if(!m || !Array.isArray(m.files) || !m.version) throw new Error('ملف التحديث على الموقع مش صالح');
    const files = m.files.filter(f => f && SAFE_PATH.test(f.path) && !f.path.includes('..') && /^[a-f0-9]{64}$/.test(f.sha256));
    const changed = files.filter(f => {
      try{ return sha256(fs.readFileSync(this.resolve(f.path))) !== f.sha256; }catch(e){ return true; }
    });
    const r = {
      at: Date.now(), latest: m.version, builtAt: m.builtAt,
      changed: changed.map(f => f.path), changedSize: changed.reduce((a, f) => a + (f.size || 0), 0),
      webAvailable: changed.length > 0,
      needsInstaller: cmpVer(this.localVersion, m.minLocal) < 0,
      installer: m.installer && cmpVer(m.installer.version, this.localVersion) > 0 ? { version: m.installer.version, size: m.installer.size } : null
    };
    this.store.kvSet('update_last_check', r);
    this._manifest = m;
    return r;
  }

  async apply(){
    if(this.busy) throw new Error('في تحديث شغّال هلق');
    this.busy = true; this.progress = 'عم نفحص...';
    const work = path.join(this.root, '_new');
    try{
      const r = await this.check();
      if(r.error) throw new Error(r.error);
      if(r.needsInstaller) throw new Error('هالتحديث بدّو نسخة أحدث من البرنامج نفسو — نزّل البرنامج الجديد أول');
      if(!r.webAvailable){ this.busy = false; this.progress = ''; return { ok: true, nothing: true, status: this.status() }; }
      const m = this._manifest;
      fs.rmSync(work, { recursive: true, force: true });
      const files = m.files.filter(f => SAFE_PATH.test(f.path) && !f.path.includes('..'));
      let i = 0;
      for(const f of files){
        i++;
        const dest = path.join(work, f.path);
        fs.mkdirSync(path.dirname(dest), { recursive: true });
        let buf = null;
        try{ const cur = fs.readFileSync(this.resolve(f.path)); if(sha256(cur) === f.sha256) buf = cur; }catch(e){}
        if(!buf){
          this.progress = 'عم ننزّل ' + f.path + ' (' + i + '/' + files.length + ')';
          buf = await get(SITE + '/' + f.path.split('/').map(encodeURIComponent).join('/') + '?v=' + f.sha256.slice(0, 12), 120000);
          if(sha256(buf) !== f.sha256) throw new Error('الملف ' + f.path + ' وصل ناقص أو مختلف — جرّب مرة تانية بعد شوي');
        }
        fs.writeFileSync(dest, buf);
      }
      // تبديل مرة وحدة: النسخة الجديدة بتصير فعّالة، والقديمة بتضل للرجوع
      const name = String(m.version).replace(/[^\w.\-]/g, '_');
      const final = path.join(this.root, name);
      fs.rmSync(final, { recursive: true, force: true });
      fs.renameSync(work, final);
      const s = this.state;
      const previous = s.active ? { dir: s.active, version: s.version } : null;
      this.state = { active: name, version: m.version, previous, appliedAt: Date.now() };
      // تنظيف: منخلّي الحالية والسابقة بس
      const keep = new Set([name, previous && previous.dir].filter(Boolean));
      for(const d of fs.readdirSync(this.root)) if(!keep.has(d)) fs.rmSync(path.join(this.root, d), { recursive: true, force: true });
      this.onChange();
      this.store.kvSet('update_last_check', Object.assign({}, r, { webAvailable: false, changed: [], changedSize: 0 }));
      this.busy = false; this.progress = '';
      return { ok: true, version: m.version, files: r.changed.length, status: this.status() };
    }catch(e){
      fs.rmSync(work, { recursive: true, force: true });
      throw new Error(netMsg(e));
    }finally{ this.busy = false; this.progress = ''; }
  }

  rollback(){
    const s = this.state;
    if(!s.active) throw new Error('شغّال على النسخة الأصلية — ما في شي ترجعلو');
    const prev = s.previous;
    if(prev && fs.existsSync(path.join(this.root, prev.dir))) this.state = { active: prev.dir, version: prev.version, previous: null, appliedAt: Date.now() };
    else this.state = { active: null, version: null, previous: null, appliedAt: Date.now() };
    this.onChange();
    return this.status();
  }

  // ---------- تحديث البرنامج نفسو (installer) ----------
  // background=true: بينزّل بالخلفية وبيخلّيه «جاهز» — بيتركّب لحالو بأول تشغيل أو بالليل
  async downloadInstaller(background){
    if(this.busy) throw new Error('في تحديث شغّال هلق');
    this.busy = true; this.progress = 'عم ننزّل البرنامج الجديد...';
    try{
      const m = this._manifest || (await this.check(), this._manifest);
      const ins = m && m.installer;
      if(!ins || cmpVer(ins.version, this.localVersion) <= 0) throw new Error('ما في نسخة أحدث من البرنامج');
      if(!/^https:\/\//.test(ins.url || '') || !/^[a-f0-9]{64}$/.test(ins.sha256 || '')) throw new Error('معلومات ملف التثبيت مش صالحة');
      const file = path.join(this.tmp, 'LibanApps-Local-Setup-' + ins.version + '.exe');
      let ok = false;
      try{ ok = sha256(fs.readFileSync(file)) === ins.sha256; }catch(e){}
      if(!ok){
        const buf = await get(ins.url, 15 * 60000);
        if(sha256(buf) !== ins.sha256) throw new Error('ملف التثبيت وصل ناقص أو مختلف — جرّب مرة تانية');
        fs.writeFileSync(file, buf);
      }
      this.store.kvSet('pending_installer', { version: ins.version, file, sha256: ins.sha256 });
      if(!background && this.runInstaller){ setTimeout(() => this.runInstaller(file, false), 800); return { ok: true, started: true }; }
      return { ok: true, file, pending: true };
    }catch(e){ throw new Error(netMsg(e)); }
    finally{ this.busy = false; this.progress = ''; }
  }
  // تركيب البرنامج الجديد إذا جاهز (صامت، وبيرجع يفتح لحالو)
  installPending(){
    const p = this.store.kvGet('pending_installer', null);
    if(!p || !this.runInstaller) return false;
    if(cmpVer(p.version, this.localVersion) <= 0 || !fs.existsSync(p.file)){ this.store.kvSet('pending_installer', null); return false; }
    try{ if(sha256(fs.readFileSync(p.file)) !== p.sha256){ this.store.kvSet('pending_installer', null); return false; } }catch(e){ return false; }
    this.store.kvSet('pending_installer', null);
    this.runInstaller(p.file, true);
    return true;
  }
  get auto(){ return this.store.kvGet('update_auto', true) !== false; }
  setAuto(on){ this.store.kvSet('update_auto', !!on); return this.status(); }

  // ---------- تلقائي: كل ساعة بيفحص، وبيحدّث لحالو ----------
  async autoRun(){
    if(this.busy) return;
    const r = await this.check();
    if(r.error || !this.auto) return;
    if(r.webAvailable && !r.needsInstaller) await this.apply().catch(() => {});
    if(r.installer && this.runInstaller) await this.downloadInstaller(true).catch(() => {});
    // البرنامج الجديد بيتركّب بالليل (٢–٥ الصبح) حتى ما يقطع الشغل
    const h = new Date().getHours();
    if(h >= 2 && h < 5) this.installPending();
  }
  start(){
    const tick = () => { this.autoRun().catch(() => {}); };
    setTimeout(tick, 20000);
    this._t = setInterval(tick, 3600000); if(this._t.unref) this._t.unref();
  }
}

module.exports = { Updater };
