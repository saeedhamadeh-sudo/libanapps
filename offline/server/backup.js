// ============================================================
//  النسخ الاحتياطي — نسخة كاملة من قاعدة البيانات، مضغوطة ومشفّرة
//  · على الكمبيوتر: بمجلد «LibanApps Backups» (آخر 30 نسخة)
//  · على السحابة (اختياري): مشفّرة بكلمة سر النسخ — حتى نحن ما منقدر نقراها
//  شكل الملف: LABK1 | salt(16) | iv(12) | tag(16) | AES-256-GCM(gzip(sqlite))
// ============================================================
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const crypto = require('crypto');
const { sbFetch } = require('./license');

const MAGIC = Buffer.from('LABK1');
const BUCKET = 'local-backups';

function deriveKey(pass, salt){ return crypto.scryptSync(String(pass), salt, 32, { N: 32768, r: 8, p: 1, maxmem: 64 * 1024 * 1024 }); }
function encrypt(buf, pass){
  const salt = crypto.randomBytes(16), iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', deriveKey(pass, salt), iv);
  const enc = Buffer.concat([c.update(buf), c.final()]);
  return Buffer.concat([MAGIC, salt, iv, c.getAuthTag(), enc]);
}
function decrypt(buf, pass){
  if(!buf.subarray(0, 5).equals(MAGIC)) throw new Error('الملف مش نسخة احتياطية من LibanApps');
  const salt = buf.subarray(5, 21), iv = buf.subarray(21, 33), tag = buf.subarray(33, 49), enc = buf.subarray(49);
  const d = crypto.createDecipheriv('aes-256-gcm', deriveKey(pass, salt), iv);
  d.setAuthTag(tag);
  try{ return Buffer.concat([d.update(enc), d.final()]); }
  catch(e){ throw new Error('كلمة سر النسخ غلط'); }
}

class Backup {
  constructor(store, license, opts){
    this.store = store; this.license = license;
    this.dir = opts.backupDir; this.tmp = opts.tmpDir;
    fs.mkdirSync(this.dir, { recursive: true }); fs.mkdirSync(this.tmp, { recursive: true });
    this.running = false; this.lastError = '';
  }
  get cfg(){ return this.store.kvGet('backup_cfg', { cloud: false, keepLocal: 30, keepCloud: 14, everyHours: 24 }); }
  setCfg(v){
    const cur = this.cfg;
    const next = Object.assign({}, cur, {
      cloud: !!v.cloud,
      keepLocal: Math.max(3, Math.min(365, Number(v.keepLocal) || cur.keepLocal)),
      everyHours: Math.max(1, Math.min(168, Number(v.everyHours) || cur.everyHours))
    });
    if(v.passphrase){
      if(String(v.passphrase).length < 8) throw new Error('كلمة سر النسخ لازم تكون ٨ أحرف أو أكتر');
      // منحفظ بصمة بس للتأكد — كلمة السر نفسها لازم تنحفظ لحتى النسخ التلقائي يشتغل
      next.passphrase = String(v.passphrase);
    }
    if(next.cloud && !next.passphrase) throw new Error('حط كلمة سر للنسخ قبل ما تفعّل الرفع عالسحابة');
    this.store.kvSet('backup_cfg', next);
    return this.status();
  }
  status(){
    const c = this.cfg;
    return { cloud: !!c.cloud, hasPassphrase: !!c.passphrase, keepLocal: c.keepLocal, everyHours: c.everyHours,
      last: this.store.kvGet('backup_last', null), lastCloud: this.store.kvGet('backup_last_cloud', null),
      lastError: this.lastError, dir: this.dir, files: this.listLocal().slice(0, 15) };
  }
  listLocal(){
    try{
      return fs.readdirSync(this.dir).filter(f => /\.(labk|labz)$/.test(f))
        .map(f => { const st = fs.statSync(path.join(this.dir, f)); return { name: f, size: st.size, at: st.mtimeMs }; })
        .sort((a, b) => b.at - a.at);
    }catch(e){ return []; }
  }
  async run(reason){
    if(this.running) return this.status();
    this.running = true;
    try{
      const c = this.cfg;
      const stamp = new Date().toISOString().replace(/[:T]/g, '-').slice(0, 19);
      const raw = path.join(this.tmp, 'snap-' + stamp + '.db');
      this.store.snapshotTo(raw);
      const gz = zlib.gzipSync(fs.readFileSync(raw), { level: 9 });
      fs.unlinkSync(raw);
      const out = c.passphrase ? encrypt(gz, c.passphrase) : gz;
      const name = 'libanapps-' + stamp + (c.passphrase ? '.labk' : '.labz');
      fs.writeFileSync(path.join(this.dir, name), out);
      this.store.kvSet('backup_last', { at: Date.now(), name, size: out.length, reason: reason || 'manual' });
      // تنظيف النسخ القديمة
      this.listLocal().slice(c.keepLocal).forEach(f => { try{ fs.unlinkSync(path.join(this.dir, f.name)); }catch(e){} });
      this.lastError = '';
      if(c.cloud && c.passphrase) await this.upload(name, out).catch(e => { this.lastError = 'الرفع عالسحابة: ' + e.message; });
    }catch(e){ this.lastError = String(e && e.message || e); }
    finally{ this.running = false; }
    return this.status();
  }
  async upload(name, buf){
    const tok = await this.license.token();
    const cid = this.license.clientId();
    const r = await sbFetch('/storage/v1/object/' + BUCKET + '/' + cid + '/' + name, {
      method: 'POST', headers: { Authorization: 'Bearer ' + tok, 'Content-Type': 'application/octet-stream', 'x-upsert': 'true' }, body: buf, timeout: 120000 });
    if(!r.ok) throw new Error((r.data && (r.data.message || r.data.error)) || ('HTTP ' + r.status));
    this.store.kvSet('backup_last_cloud', { at: Date.now(), name, size: buf.length });
    // نخلّي آخر keepCloud نسخة بس
    const list = await this.listCloud().catch(() => []);
    const old = list.slice(this.cfg.keepCloud || 14).map(f => cid + '/' + f.name);
    if(old.length) await sbFetch('/storage/v1/object/' + BUCKET, { method: 'DELETE', headers: { Authorization: 'Bearer ' + tok }, body: JSON.stringify({ prefixes: old }) }).catch(() => {});
  }
  async listCloud(){
    const tok = await this.license.token();
    const cid = this.license.clientId();
    const r = await sbFetch('/storage/v1/object/list/' + BUCKET, { method: 'POST', headers: { Authorization: 'Bearer ' + tok },
      body: JSON.stringify({ prefix: cid + '/', limit: 200, sortBy: { column: 'name', order: 'desc' } }) });
    if(!r.ok) throw new Error((r.data && r.data.message) || ('HTTP ' + r.status));
    return (r.data || []).filter(f => /\.labk$/.test(f.name)).map(f => ({ name: f.name, size: f.metadata && f.metadata.size, at: f.created_at }));
  }
  async downloadCloud(name){
    if(!/^libanapps-[\d-]+\.labk$/.test(name)) throw new Error('اسم ملف غلط');
    const tok = await this.license.token();
    const cid = this.license.clientId();
    const { SB_URL, SB_ANON } = require('./license');
    const r = await fetch(SB_URL + '/storage/v1/object/authenticated/' + BUCKET + '/' + cid + '/' + name, { headers: { apikey: SB_ANON, Authorization: 'Bearer ' + tok } });
    if(!r.ok) throw new Error('تعذّر تنزيل النسخة (HTTP ' + r.status + ')');
    return Buffer.from(await r.arrayBuffer());
  }
  // استرجاع: منحفظ نسخة من الوضع الحالي أول شي، وبعدين منستبدل
  async restore(buf, passphrase){
    let gz = buf;
    if(buf.subarray(0, 5).equals(MAGIC)) gz = decrypt(buf, passphrase || this.cfg.passphrase || '');
    let dbBuf;
    try{ dbBuf = zlib.gunzipSync(gz); }catch(e){ throw new Error('الملف تالف أو مش نسخة احتياطية'); }
    if(!dbBuf.subarray(0, 15).equals(Buffer.from('SQLite format 3'))) throw new Error('الملف مش قاعدة بيانات');
    await this.run('before-restore');
    const tmpFile = path.join(this.tmp, 'restore-' + Date.now() + '.db');
    fs.writeFileSync(tmpFile, dbBuf);
    this.store.replaceWith(tmpFile);
    try{ fs.unlinkSync(tmpFile); }catch(e){}
    return { ok: true, counts: this.store.counts() };
  }
  restoreLocalFile(name, passphrase){
    if(!/^libanapps-[\w-]+\.(labk|labz)$/.test(name)) throw new Error('اسم ملف غلط');
    return this.restore(fs.readFileSync(path.join(this.dir, name)), passphrase);
  }
  start(){
    const tick = () => {
      const last = this.store.kvGet('backup_last', null);
      if(!last || Date.now() - last.at > this.cfg.everyHours * 3600000) this.run('auto').catch(() => {});
    };
    setTimeout(tick, 60000);
    this._t = setInterval(tick, 15 * 60000);
    if(this._t.unref) this._t.unref();
  }
}

module.exports = { Backup, encrypt, decrypt };
