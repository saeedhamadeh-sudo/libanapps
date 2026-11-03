// ============================================================
//  محرّك البيانات المحلي — نفس قواعد «الوضع الآمن» يلي بالسحابة
//  (secure-apps.sql) بس منفّذة هون على الكمبيوتر:
//   · ما في قراءة لبيانات المؤسسة قبل تسجيل الدخول (إلا الاسم والشعار)
//   · الزبون بيشوف حسابه بس، والعامل يومياته ودفعاته بس
//   · المستخدم المخصّص بيكتب بس بأقسام صلاحياته
//   · كلمات السر مشفّرة وأسرار 2FA ما بتطلع للمتصفح أبداً
// ============================================================
'use strict';
const crypto = require('crypto');

const PRODUCTS = ['alum', 'trade'];
const ACCOUNT_TABLES = ['app_users', 'customer_accounts', 'worker_accounts'];
const COL_RE = /^[a-z_][a-z0-9_]*$/i;
const TBL_RE = /^(alum|trade)_[a-z_]+$/;

// الجداول يلي بيستعملها كل برنامج (بدون السابقة) — للنقل من السحابة
const TABLES = {
  alum: ['app_settings', 'app_users', 'customers', 'invoices', 'receipts', 'suppliers', 'purchase_invoices',
    'payment_vouchers', 'workers', 'work_entries', 'worker_payments', 'deductions', 'quotes', 'warehouse_items',
    'stock_ins', 'stock_outs', 'cutting_orders', 'customer_accounts', 'worker_accounts', 'budget_categories', 'budget_entries'],
  trade: ['app_settings', 'app_users', 'customers', 'invoices', 'receipts', 'suppliers', 'purchase_invoices',
    'payment_vouchers', 'warehouse_items', 'stock_ins', 'stock_outs', 'customer_accounts', 'budget_categories',
    'budget_entries', 'cash_movements', 'day_closures', 'cashier_shifts', 'workers', 'work_entries',
    'worker_payments', 'worker_accounts']
};

function permTables(product, perm){
  const m = {
    alum: { customers: ['customers', 'invoices', 'receipts'], suppliers: ['suppliers', 'purchase_invoices', 'payment_vouchers'],
      workers: ['workers', 'work_entries', 'worker_payments'], deductions: ['deductions'], quotes: ['quotes'],
      warehouse: ['warehouse_items', 'stock_ins', 'stock_outs'], orders: ['cutting_orders'], budget: ['budget_categories', 'budget_entries'] },
    trade: { pos: ['customers', 'invoices', 'receipts', 'stock_outs', 'stock_ins', 'cash_movements', 'cashier_shifts'],
      customers: ['customers', 'invoices', 'receipts', 'stock_outs'], suppliers: ['suppliers', 'purchase_invoices', 'payment_vouchers'],
      warehouse: ['warehouse_items', 'stock_ins', 'stock_outs'], budget: ['budget_categories', 'budget_entries'],
      workers: ['workers', 'work_entries', 'worker_payments'] }
  };
  return (m[product] && m[product][perm]) || [];
}

function splitTbl(tbl){ const i = tbl.indexOf('_'); return { product: tbl.slice(0, i), t: tbl.slice(i + 1) }; }
function pkOf(row){
  if(row.id !== undefined && row.id !== null && row.id !== '') return String(row.id);
  if(row.client_id) return String(row.client_id);
  return 'singleton';
}
const isPriv = s => s && s.kind === 'staff' && (s.role === 'admin' || s.role === 'superuser');

// ---------- كلمات السر ----------
// bcrypt ($2a$) — نفس شكل السحابة، فبينفحص كمان بقاعدة البيانات للنسخة «للقراءة بس»
let _bcrypt = null; try{ _bcrypt = require('bcryptjs'); }catch(e){}
function hashPassword(pw){
  if(_bcrypt) return _bcrypt.hashSync(String(pw), 10);
  const salt = crypto.randomBytes(16);
  const h = crypto.scryptSync(String(pw), salt, 32, { N: 16384, r: 8, p: 1 });
  return 'scrypt$' + salt.toString('base64') + '$' + h.toString('base64');
}
function verifyPassword(pw, stored){
  if(!stored) return false;
  // كلمات سر منقولة من السحابة (bcrypt من pgcrypto) — بتضل شغّالة متل ما هي
  if(/^\$2[aby]\$/.test(stored)){
    try{ return require('bcryptjs').compareSync(String(pw || ''), stored); }catch(e){ return false; }
  }
  const [kind, s, h] = String(stored).split('$');
  if(kind !== 'scrypt') return false;
  const want = Buffer.from(h, 'base64');
  const got = crypto.scryptSync(String(pw || ''), Buffer.from(s, 'base64'), want.length, { N: 16384, r: 8, p: 1 });
  return crypto.timingSafeEqual(want, got);
}
function base32Decode(s){
  const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  s = String(s || '').toUpperCase().replace(/[^A-Z2-7]/g, '');
  let bits = '', out = [];
  for(const c of s) bits += A.indexOf(c).toString(2).padStart(5, '0');
  for(let i = 0; i + 8 <= bits.length; i += 8) out.push(parseInt(bits.substr(i, 8), 2));
  return Buffer.from(out);
}
function totpOk(secret, code){
  if(!/^\d{6}$/.test(String(code || ''))) return false;
  const key = base32Decode(secret); if(!key.length) return false;
  const now = Math.floor(Date.now() / 1000 / 30);
  for(let w = -1; w <= 1; w++){
    const msg = Buffer.alloc(8); msg.writeBigUInt64BE(BigInt(now + w));
    const h = crypto.createHmac('sha1', key).update(msg).digest();
    const off = h[19] & 15;
    const bin = ((h[off] & 127) << 24) | (h[off + 1] << 16) | (h[off + 2] << 8) | h[off + 3];
    if(String(bin % 1000000).padStart(6, '0') === String(code)) return true;
  }
  return false;
}

class DataEngine {
  constructor(store, opts){
    this.store = store;
    this.clientId = opts.clientId;   // دالة بترجّع هوية المؤسسة الحالية
    this.access = opts.access;       // دالة الترخيص (app_access)
  }
  // ---------- الجلسات ----------
  session(sid, product){
    if(!sid || !product) return null;
    const s = this.store.get('SELECT * FROM sessions WHERE sid=? AND product=?', sid, product);
    if(!s) return null;
    s.perms = (() => { try{ return JSON.parse(s.perms || '[]'); }catch(e){ return []; } })();
    if(Date.now() - (s.last_seen || 0) > 60000) this.store.run('UPDATE sessions SET last_seen=? WHERE sid=? AND product=?', Date.now(), sid, product);
    return s;
  }
  // ---------- شروط القراءة (نفس app_can_read) كجملة SQL ----------
  readClause(tbl, sid){
    const { product, t } = splitTbl(tbl);
    if(t === 'app_settings') return { sql: '1', p: [] };
    const s = this.session(sid, product);
    if(!s) return { sql: '0', p: [] };
    if(s.kind === 'staff'){
      if(ACCOUNT_TABLES.includes(t)){
        if(isPriv(s)) return { sql: '1', p: [] };
        if(t === 'app_users') return { sql: 'pk = ?', p: [String(s.account_id)] };
        return { sql: '0', p: [] };
      }
      return { sql: '1', p: [] };
    }
    if(s.kind === 'customer'){
      if(t === 'customers') return { sql: 'pk = ?', p: [String(s.customer_id)] };
      if(t === 'invoices' || t === 'receipts') return { sql: "CAST(json_extract(data,'$.customer_id') AS TEXT) = ?", p: [String(s.customer_id)] };
      return { sql: '0', p: [] };
    }
    if(s.kind === 'worker'){
      if(t === 'workers') return { sql: 'pk = ?', p: [String(s.worker_id)] };
      if(t === 'work_entries' || t === 'worker_payments') return { sql: "CAST(json_extract(data,'$.worker_id') AS TEXT) = ?", p: [String(s.worker_id)] };
      return { sql: '0', p: [] };
    }
    return { sql: '0', p: [] };
  }
  // ---------- صلاحية الكتابة (نفس app_can_write) ----------
  canWrite(tbl, sid){
    const { product, t } = splitTbl(tbl);
    const s = this.session(sid, product);
    if(!s || s.kind !== 'staff') return false;
    if(isPriv(s)) return true;
    if(['app_users', 'customer_accounts', 'worker_accounts', 'day_closures'].includes(t)) return false;
    if(t === 'app_settings' || t === 'budget_categories') return true;
    return (s.perms || []).some(p => permTables(product, p).includes(t));
  }

  // ---------- استعلام عام (من نسخة supabase المحلية بالمتصفح) ----------
  query(q, sid){
    const tbl = String(q.t || '');
    if(tbl === 'clients') return { data: q.single ? null : [], error: null };
    if(!TBL_RE.test(tbl)) return { data: null, error: { code: '42P01', message: 'relation "' + tbl + '" does not exist' } };
    const { product } = splitTbl(tbl);
    if(!PRODUCTS.includes(product)) return { data: null, error: { code: '42P01', message: 'bad table' } };

    // الفلاتر
    const where = ['tbl = ?'], params = [tbl];
    for(const f of (q.f || [])){
      const [col, op, val] = f;
      if(!COL_RE.test(col)) return { data: null, error: { code: '42703', message: 'bad column ' + col } };
      if(col === 'client_id') continue;   // نسخة محلية لمؤسسة وحدة — هوية المؤسسة ما بتفرق
      const expr = col === 'id' ? 'pk' : `CAST(json_extract(data,'$.${col}') AS TEXT)`;
      const norm = v => v === true ? '1' : v === false ? '0' : String(v);
      if(op === 'eq'){ where.push(expr + ' = ?'); params.push(norm(val)); }
      else if(op === 'neq'){ where.push('(' + expr + ' IS NULL OR ' + expr + ' <> ?)'); params.push(norm(val)); }
      else if(op === 'in' || op === 'notin'){
        const arr = Array.isArray(val) ? val : [];
        if(!arr.length){ where.push(op === 'in' ? '0' : '1'); continue; }
        const ph = arr.map(() => '?').join(',');
        where.push(op === 'in' ? `${expr} IN (${ph})` : `(${expr} IS NULL OR ${expr} NOT IN (${ph}))`);
        arr.forEach(v => params.push(norm(v)));
      }
      else if(op === 'notnull'){ where.push(expr + ' IS NOT NULL'); }
      else if(op === 'is'){ where.push(val === null ? expr + ' IS NULL' : expr + ' = ?'); if(val !== null) params.push(norm(val)); }
      else if(['gt', 'gte', 'lt', 'lte'].includes(op)){
        const sym = { gt: '>', gte: '>=', lt: '<', lte: '<=' }[op];
        const num = typeof val === 'number';
        const e2 = col === 'id' ? 'pk' : (num ? `json_extract(data,'$.${col}')` : expr);
        where.push(`${e2} ${sym} ?`); params.push(num ? val : String(val));
      }
      else return { data: null, error: { code: 'PGRST100', message: 'unsupported filter ' + op } };
    }

    if(q.op === 'select'){
      const rc = this.readClause(tbl, sid);
      where.push('(' + rc.sql + ')'); params.push(...rc.p);
      let sql = 'SELECT pk, data FROM rows WHERE ' + where.join(' AND ');
      if(q.order && COL_RE.test(q.order[0])){
        const oc = q.order[0] === 'id' ? 'pk' : `json_extract(data,'$.${q.order[0]}')`;
        sql += ' ORDER BY ' + oc + (q.order[1] === false ? ' DESC' : ' ASC');
      }
      if(q.range){ sql += ' LIMIT ? OFFSET ?'; params.push(q.range[1] - q.range[0] + 1, q.range[0]); }
      else if(q.limit){ sql += ' LIMIT ?'; params.push(q.limit); }
      let rows = this.store.all(sql, ...params).map(r => JSON.parse(r.data));
      rows.forEach(r => { r.client_id = this.clientId(); });
      const cols = String(q.cols || '*').split(',').map(s => s.trim()).filter(Boolean);
      if(!cols.includes('*')) rows = rows.map(r => { const o = {}; cols.forEach(c => { o[c] = r[c] === undefined ? null : r[c]; }); return o; });
      if(q.single){
        if(rows.length > 1) return { data: null, error: { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned' } };
        if(!rows.length && q.single === 'one') return { data: null, error: { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned' } };
        return { data: rows[0] || null, error: null };
      }
      return { data: rows, error: null };
    }

    if(!this.canWrite(tbl, sid)) return { data: null, error: { code: '42501', message: 'new row violates row-level security policy for table "' + tbl + '"' } };

    if(q.op === 'upsert' || q.op === 'insert'){
      const list = Array.isArray(q.rows) ? q.rows : [q.rows];
      const { t } = splitTbl(tbl);
      const now = Date.now(), out = [];
      this.store.tx(() => {
        for(const raw of list){
          if(!raw || typeof raw !== 'object') continue;
          const row = Object.assign({}, raw, { client_id: this.clientId() });
          const pk = pkOf(row);
          if(ACCOUNT_TABLES.includes(t)) this._protectSecrets(tbl, t, pk, row);
          const old = this.store.get('SELECT data FROM rows WHERE tbl=? AND pk=?', tbl, pk);
          const merged = old ? Object.assign(JSON.parse(old.data), row) : row;
          this.store.run('INSERT INTO rows(tbl,pk,data,updated_at) VALUES(?,?,?,?) ON CONFLICT(tbl,pk) DO UPDATE SET data=excluded.data, updated_at=excluded.updated_at',
            tbl, pk, JSON.stringify(merged), now);
          out.push(merged);
        }
      });
      return { data: q.returning ? out : null, error: null };
    }

    if(q.op === 'update'){
      const sel = this.store.all('SELECT pk, data FROM rows WHERE ' + where.join(' AND '), ...params);
      const { t } = splitTbl(tbl);
      this.store.tx(() => {
        for(const r of sel){
          const row = Object.assign(JSON.parse(r.data), q.values || {});
          if(ACCOUNT_TABLES.includes(t)) this._protectSecrets(tbl, t, r.pk, row);
          this.store.run('UPDATE rows SET data=?, updated_at=? WHERE tbl=? AND pk=?', JSON.stringify(row), Date.now(), tbl, r.pk);
        }
      });
      return { data: null, error: null };
    }

    if(q.op === 'delete'){
      const { t } = splitTbl(tbl);
      const sel = this.store.all('SELECT pk FROM rows WHERE ' + where.join(' AND '), ...params);
      this.store.tx(() => {
        for(const r of sel){
          this.store.run('DELETE FROM rows WHERE tbl=? AND pk=?', tbl, r.pk);
          if(ACCOUNT_TABLES.includes(t)) this.store.run('DELETE FROM secrets WHERE tbl=? AND id=?', tbl, r.pk);
        }
      });
      return { data: null, error: null };
    }
    return { data: null, error: { code: 'PGRST000', message: 'bad op' } };
  }

  // كلمة السر بتنحفظ مشفّرة بجدول منفصل، وبالسطر بتضل فاضية (متل app_protect_secrets)
  _protectSecrets(tbl, t, pk, row){
    const pw = row.password, ts = row.totp_secret;
    if(pw !== undefined && pw !== null && pw !== ''){
      this.store.run('INSERT INTO secrets(tbl,id,password_hash) VALUES(?,?,?) ON CONFLICT(tbl,id) DO UPDATE SET password_hash=excluded.password_hash',
        tbl, pk, hashPassword(pw));
    }
    if(ts !== undefined && ts !== null && ts !== ''){
      this.store.run('INSERT INTO secrets(tbl,id,totp_secret) VALUES(?,?,?) ON CONFLICT(tbl,id) DO UPDATE SET totp_secret=excluded.totp_secret', tbl, pk, ts);
    }
    if('password' in row) row.password = '';
    if(t === 'app_users' && 'totp_secret' in row) row.totp_secret = null;
  }

  // ---------- الدوال (RPC) ----------
  rpc(name, args, sid){
    args = args || {};
    const product = args.p_product;
    switch(name){
      case 'app_mode': return { data: { secure: true, local: true }, error: null };
      case 'is_admin': return { data: false, error: null };
      case 'autolink_my_client': return { data: null, error: null };
      case 'my_client_id': return { data: this.clientId(), error: null };
      case 'app_access':
        if(!PRODUCTS.includes(product)) return { data: null, error: { message: 'bad product' } };
        return { data: this.access(product), error: null };
      case 'app_login': return { data: this.login(product, args.p_username, args.p_password, args.p_totp, sid), error: null };
      case 'app_logout':
        if(sid) this.store.run('DELETE FROM sessions WHERE sid=? AND product=?', sid, product);
        return { data: null, error: null };
      case 'app_change_password': return { data: this.changePassword(product, args.p_old, args.p_new, sid), error: null };
      case 'app_login_wa': return { data: { ok: false, reason: 'error', message: 'الدخول بالواتساب مش متوفّر بالنسخة المحلية — ادخل باسم المستخدم وكلمة السر' }, error: null };
      default: return { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.' + name } };
    }
  }

  findAccount(tbl, username){
    const u = String(username || '').trim().toLowerCase();
    const rows = this.store.all("SELECT pk, data FROM rows WHERE tbl=? AND lower(json_extract(data,'$.username')) = ?", tbl, u);
    return rows.length ? Object.assign(JSON.parse(rows[0].data), { __pk: rows[0].pk }) : null;
  }
  pwOk(tbl, acc, pw){
    const sec = this.store.get('SELECT password_hash FROM secrets WHERE tbl=? AND id=?', tbl, acc.__pk);
    if(!(sec && sec.password_hash)) return false;
    const ok = verifyPassword(pw, sec.password_hash);
    // بصمة قديمة (scrypt): منحوّلها لـbcrypt بأول دخول صحيح
    if(ok && _bcrypt && /^scrypt\$/.test(sec.password_hash))
      this.store.run('UPDATE secrets SET password_hash=? WHERE tbl=? AND id=?', hashPassword(pw), tbl, acc.__pk);
    return ok;
  }
  login(product, username, password, totp, sid){
    if(!PRODUCTS.includes(product)) return { ok: false, reason: 'error', message: 'bad product' };
    if(!sid) return { ok: false, reason: 'no_session' };
    const u = String(username || '').trim().toLowerCase();
    const since = Date.now() - 15 * 60000;
    this.store.run('DELETE FROM login_attempts WHERE at < ?', Date.now() - 86400000);
    const fails = this.store.get('SELECT COUNT(*) AS n FROM login_attempts WHERE product=? AND username=? AND at > ?', product, u, since).n;
    if(fails >= 8) return { ok: false, reason: 'locked' };
    const strip = (a, extra) => { const o = Object.assign({}, a); delete o.__pk; delete o.password; delete o.client_id; (extra || []).forEach(k => delete o[k]); return o; };
    const setSession = (kind, acc, extra) => {
      this.store.run(`INSERT INTO sessions(sid,product,kind,account_id,role,perms,customer_id,worker_id,created_at,last_seen)
        VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(sid,product) DO UPDATE SET kind=excluded.kind, account_id=excluded.account_id,
        role=excluded.role, perms=excluded.perms, customer_id=excluded.customer_id, worker_id=excluded.worker_id, created_at=excluded.created_at, last_seen=excluded.last_seen`,
        sid, product, kind, String(acc.__pk), extra.role || null, JSON.stringify(extra.perms || []), extra.customer_id || null, extra.worker_id || null, Date.now(), Date.now());
    };
    // 1) مستخدمو البرنامج
    let t = product + '_app_users';
    let acc = this.findAccount(t, u);
    if(acc){
      let ok = this.pwOk(t, acc, password);
      if(ok && acc.totp_enabled){
        if(!totp) return { ok: false, need_totp: true };
        const sec = this.store.get('SELECT totp_secret FROM secrets WHERE tbl=? AND id=?', t, acc.__pk);
        ok = totpOk((sec && sec.totp_secret) || acc.totp_secret, totp);
      }
      if(ok){
        setSession('staff', acc, { role: acc.role, perms: Array.isArray(acc.permissions) ? acc.permissions : [] });
        return { ok: true, kind: 'staff', account: strip(acc, ['totp_secret']) };
      }
    }
    // 2) حسابات الزبائن
    if(!acc){
      t = product + '_customer_accounts';
      acc = this.findAccount(t, u);
      if(acc && this.pwOk(t, acc, password)){
        setSession('customer', acc, { customer_id: acc.customer_id });
        return { ok: true, kind: 'customer', account: strip(acc) };
      }
    }
    // 3) حسابات العمال
    if(!acc){
      t = product + '_worker_accounts';
      acc = this.findAccount(t, u);
      if(acc && this.pwOk(t, acc, password)){
        setSession('worker', acc, { worker_id: acc.worker_id });
        return { ok: true, kind: 'worker', account: strip(acc) };
      }
    }
    this.store.run('INSERT INTO login_attempts(product,username,at) VALUES(?,?,?)', product, u, Date.now());
    return { ok: false, reason: 'invalid' };
  }
  changePassword(product, oldPw, newPw, sid){
    const s = this.session(sid, product);
    if(!s || s.kind !== 'staff') return { ok: false, reason: 'no_session' };
    if(String(newPw || '').length < 4) return { ok: false, reason: 'short' };
    const t = product + '_app_users';
    const r = this.store.get('SELECT pk, data FROM rows WHERE tbl=? AND pk=?', t, String(s.account_id));
    if(!r) return { ok: false, reason: 'invalid' };
    const acc = Object.assign(JSON.parse(r.data), { __pk: r.pk });
    if(!this.pwOk(t, acc, oldPw)) return { ok: false, reason: 'invalid' };
    this.setPassword(product, r.pk, newPw);
    return { ok: true };
  }

  // ---------- إدارة المستخدمين من شاشة الكمبيوتر (للمدير بس، محلياً) ----------
  listUsers(product){
    return this.store.all('SELECT pk, data FROM rows WHERE tbl=?', product + '_app_users').map(r => {
      const d = JSON.parse(r.data);
      const sec = this.store.get('SELECT password_hash FROM secrets WHERE tbl=? AND id=?', product + '_app_users', r.pk);
      return { id: r.pk, username: d.username, role: d.role, hasPassword: !!(sec && sec.password_hash), totp: !!d.totp_enabled };
    });
  }
  setPassword(product, id, pw){
    this.store.run('INSERT INTO secrets(tbl,id,password_hash) VALUES(?,?,?) ON CONFLICT(tbl,id) DO UPDATE SET password_hash=excluded.password_hash',
      product + '_app_users', String(id), hashPassword(pw));
  }
  saveUser(product, u){
    if(!PRODUCTS.includes(product)) throw new Error('bad product');
    const tbl = product + '_app_users';
    const username = String(u.username || '').trim();
    if(!username) throw new Error('اسم المستخدم مطلوب');
    let id = u.id;
    const dupe = this.findAccount(tbl, username);
    if(dupe && String(dupe.__pk) !== String(id || '')) throw new Error('اسم المستخدم موجود — اختار اسم تاني');
    if(!id){
      id = Date.now().toString(36) + crypto.randomBytes(3).toString('hex');
      const row = { id, username, password: '', role: u.role || 'admin', permissions: [], totp_secret: null, totp_enabled: false, client_id: this.clientId() };
      this.store.run('INSERT INTO rows(tbl,pk,data,updated_at) VALUES(?,?,?,?)', tbl, id, JSON.stringify(row), Date.now());
    } else {
      const r = this.store.get('SELECT data FROM rows WHERE tbl=? AND pk=?', tbl, String(id));
      if(!r) throw new Error('المستخدم مش موجود');
      const row = Object.assign(JSON.parse(r.data), { username });
      if(u.disable2fa){ row.totp_enabled = false; this.store.run('UPDATE secrets SET totp_secret=NULL WHERE tbl=? AND id=?', tbl, String(id)); }
      this.store.run('UPDATE rows SET data=?, updated_at=? WHERE tbl=? AND pk=?', JSON.stringify(row), Date.now(), tbl, String(id));
    }
    if(u.password){
      if(String(u.password).length < 4) throw new Error('كلمة السر لازم تكون ٤ أحرف أو أكتر');
      this.setPassword(product, id, u.password);
      this.store.run('DELETE FROM login_attempts WHERE product=? AND username=?', product, username.toLowerCase());
    }
    return { ok: true, id };
  }
  // كلمات السر وأسرار 2FA المنقولة من السحابة (مشفّرة متل ما هي)
  importSecrets(product, rows){
    let n = 0;
    this.store.tx(() => {
      for(const r of rows || []){
        if(!r || !r.tbl || !r.id || String(r.tbl).indexOf(product + '_') !== 0) continue;
        if(!ACCOUNT_TABLES.includes(String(r.tbl).slice(product.length + 1))) continue;
        this.store.run(`INSERT INTO secrets(tbl,id,password_hash,totp_secret) VALUES(?,?,?,?)
          ON CONFLICT(tbl,id) DO UPDATE SET password_hash=COALESCE(excluded.password_hash, secrets.password_hash), totp_secret=COALESCE(excluded.totp_secret, secrets.totp_secret)`,
          r.tbl, String(r.id), r.password_hash || null, r.totp_secret || null);
        n++;
      }
    });
    return n;
  }
  hasPassword(tbl, id){ const r = this.store.get('SELECT password_hash FROM secrets WHERE tbl=? AND id=?', tbl, String(id)); return !!(r && r.password_hash); }
  // ---------- نقل بيانات من السحابة: استبدال جداول برنامج كامل ----------
  replaceProductData(product, tables){
    this.store.tx(() => {
      this.store.run("DELETE FROM rows WHERE substr(tbl,1,?) = ?", product.length + 1, product + '_');
      this.store.run("DELETE FROM secrets WHERE substr(tbl,1,?) = ?", product.length + 1, product + '_');
      this.store.run('DELETE FROM sessions WHERE product=?', product);
      const now = Date.now();
      for(const [t, rows] of Object.entries(tables)){
        const tbl = product + '_' + t;
        for(const raw of rows){
          const row = Object.assign({}, raw, { client_id: this.clientId() });
          const pk = pkOf(row);
          if(ACCOUNT_TABLES.includes(t)) this._protectSecrets(tbl, t, pk, row);
          this.store.run('INSERT INTO rows(tbl,pk,data,updated_at) VALUES(?,?,?,?) ON CONFLICT(tbl,pk) DO UPDATE SET data=excluded.data',
            tbl, pk, JSON.stringify(row), now);
        }
      }
    });
  }
}

module.exports = { DataEngine, TABLES, PRODUCTS, hashPassword, verifyPassword, totpOk };
