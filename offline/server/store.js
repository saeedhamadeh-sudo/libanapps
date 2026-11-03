// ============================================================
//  التخزين المحلي — قاعدة بيانات SQLite وحدة على الكمبيوتر
//  كل جداول البرنامجين (alum_* و trade_*) بتنحفظ كسطور JSON،
//  فما في داعي نلحق كل تعديل بأعمدة الجداول بالسحابة.
// ============================================================
'use strict';
const fs = require('fs');
const path = require('path');

function openSqlite(file){
  // بنسخة الكمبيوتر (Electron): better-sqlite3 — وإذا مش موجودة: SQLite المدمجة بـNode 22+
  try{ const Better = require('better-sqlite3'); const db = new Better(file); db.__engine = 'better-sqlite3'; return db; }
  catch(e){ /* fallthrough */ }
  const { DatabaseSync } = require('node:sqlite');
  const db = new DatabaseSync(file); db.__engine = 'node:sqlite'; return db;
}

const SCHEMA = `
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
CREATE TABLE IF NOT EXISTS rows (
  tbl TEXT NOT NULL, pk TEXT NOT NULL, data TEXT NOT NULL, updated_at INTEGER NOT NULL,
  PRIMARY KEY (tbl, pk)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS secrets (
  tbl TEXT NOT NULL, id TEXT NOT NULL, password_hash TEXT, totp_secret TEXT,
  PRIMARY KEY (tbl, id)
);
CREATE TABLE IF NOT EXISTS sessions (
  sid TEXT NOT NULL, product TEXT NOT NULL, kind TEXT NOT NULL, account_id TEXT NOT NULL,
  role TEXT, perms TEXT, customer_id TEXT, worker_id TEXT, created_at INTEGER, last_seen INTEGER,
  PRIMARY KEY (sid, product)
);
CREATE TABLE IF NOT EXISTS login_attempts (product TEXT, username TEXT, at INTEGER);
CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT);
`;

class Store {
  constructor(file){ this.file = file; this.open(); }
  open(){
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    this.db = openSqlite(this.file);
    this.db.exec(SCHEMA);
  }
  close(){ try{ this.db.close(); }catch(e){} }
  all(sql, ...p){ return this.db.prepare(sql).all(...p); }
  get(sql, ...p){ return this.db.prepare(sql).get(...p); }
  run(sql, ...p){ return this.db.prepare(sql).run(...p); }
  tx(fn){
    this.db.exec('BEGIN');
    try{ const r = fn(); this.db.exec('COMMIT'); return r; }
    catch(e){ try{ this.db.exec('ROLLBACK'); }catch(x){} throw e; }
  }
  // ---- key/value للإعدادات الداخلية (الترخيص، النسخ، الرابط...) ----
  kvGet(k, def){ const r = this.get('SELECT v FROM kv WHERE k=?', k); if(!r) return def; try{ return JSON.parse(r.v); }catch(e){ return def; } }
  kvSet(k, v){ this.run('INSERT INTO kv(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v', k, JSON.stringify(v)); }
  // ---- نسخة كاملة من القاعدة (للنسخ الاحتياطي) ----
  snapshotTo(dest){
    try{ fs.unlinkSync(dest); }catch(e){}
    this.db.exec('PRAGMA wal_checkpoint(TRUNCATE)');
    this.db.exec(`VACUUM INTO '${dest.replace(/'/g, "''")}'`);
  }
  // ---- استبدال القاعدة كلها بنسخة (استرجاع) ----
  replaceWith(srcFile){
    this.close();
    for(const ext of ['-wal', '-shm']){ try{ fs.unlinkSync(this.file + ext); }catch(e){} }
    fs.copyFileSync(srcFile, this.file);
    this.open();
  }
  counts(){
    return this.all("SELECT tbl, COUNT(*) AS n FROM rows GROUP BY tbl ORDER BY tbl");
  }
}

module.exports = { Store };
