// ============================================================
//  قائمة ملفات التحديث — مشتركة بين:
//   · scripts/publish-update.js (عندك قبل النشر: بيعمل public/offline-update.json)
//   · server/updater.js (عند الزبون: بيقارن وبينزّل يلي تغيّر)
// ============================================================
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// الملفات يلي بتتحدّث «أونلاين» (صفحات البرنامجين وملفاتها) — بلا vendor (خطوط/مكتبات ثابتة)
const SAFE_PATH = /^(app-(alum|trade)\.html|assets\/[A-Za-z0-9_\-./]+\.(js|css|json|png|jpe?g|svg|webp|woff2?))$/;

function sha256(buf){ return crypto.createHash('sha256').update(buf).digest('hex'); }

function listFiles(root){
  const out = [];
  for(const f of ['app-alum.html', 'app-trade.html']) if(fs.existsSync(path.join(root, f))) out.push(f);
  const walk = rel => {
    const dir = path.join(root, rel);
    if(!fs.existsSync(dir)) return;
    for(const e of fs.readdirSync(dir, { withFileTypes: true })){
      const r = rel + '/' + e.name;
      if(e.isDirectory()) walk(r); else if(SAFE_PATH.test(r)) out.push(r);
    }
  };
  walk('assets');
  return out.sort();
}

function buildManifest(root, extra){
  const files = listFiles(root).map(p => {
    const buf = fs.readFileSync(path.join(root, p));
    return { path: p, sha256: sha256(buf), size: buf.length };
  });
  const all = sha256(files.map(f => f.path + ':' + f.sha256).join('\n')).slice(0, 10);
  const d = new Date();
  const stamp = d.getUTCFullYear() + '.' + String(d.getUTCMonth() + 1).padStart(2, '0') + '.' + String(d.getUTCDate()).padStart(2, '0');
  return Object.assign({ version: stamp + '-' + all, contentHash: all, builtAt: d.toISOString(), minLocal: '2.0.0', files }, extra || {});
}

function cmpVer(a, b){
  const pa = String(a || '0').split('.').map(n => parseInt(n, 10) || 0), pb = String(b || '0').split('.').map(n => parseInt(n, 10) || 0);
  for(let i = 0; i < Math.max(pa.length, pb.length); i++){ const d = (pa[i] || 0) - (pb[i] || 0); if(d) return d > 0 ? 1 : -1; }
  return 0;
}

module.exports = { SAFE_PATH, sha256, listFiles, buildManifest, cmpVer };
