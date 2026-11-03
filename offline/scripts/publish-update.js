// ============================================================
//  نشر تحديث للنسخة المحلية — بتشغّلو عندك قبل ما ترفع على GitHub:
//
//    node offline/scripts/publish-update.js
//
//  بيعمل public/offline-update.json فيه بصمة (sha256) كل ملف من صفحات البرنامجين.
//  برامج الزباين بتقرا هالملف من libanapps.com لما يكبسو «تحديث»،
//  بتنزّل بس الملفات يلي تغيّرت، وبتتأكد من البصمة قبل ما تبدّل.
//
//  إذا عملت installer جديد (تغيير بالسيرفر المحلي نفسو):
//    node offline/scripts/publish-update.js --installer dist\LibanApps-Local-Setup-2.1.0.exe --url https://...exe
// ============================================================
'use strict';
const fs = require('fs');
const path = require('path');
const { buildManifest, sha256 } = require('../server/manifest');

const PUB = path.join(__dirname, '..', '..', 'public');
const OUT = path.join(PUB, 'offline-update.json');
const args = process.argv.slice(2);
const arg = n => { const i = args.indexOf('--' + n); return i >= 0 ? args[i + 1] : null; };

let prev = {};
try{ prev = JSON.parse(fs.readFileSync(OUT, 'utf8')); }catch(e){}

const extra = {};
// minLocal: أقل نسخة من برنامج الكمبيوتر بتقدر تاخد هالتحديث (إذا الصفحات صارت بحاجة شي جديد بالسيرفر المحلي)
extra.minLocal = arg('min-local') || prev.minLocal || '2.0.0';
if(arg('installer')){
  const file = arg('installer'), url = arg('url');
  if(!url){ console.error('حط --url للرابط يلي رح ترفع عليه ملف التثبيت'); process.exit(1); }
  const buf = fs.readFileSync(file);
  const ver = (path.basename(file).match(/(\d+\.\d+\.\d+)/) || [])[1];
  if(!ver){ console.error('ما قدرت إعرف رقم النسخة من اسم الملف'); process.exit(1); }
  extra.installer = { version: ver, url, sha256: sha256(buf), size: buf.length };
} else if(prev.installer) extra.installer = prev.installer;

const m = buildManifest(PUB, extra);
if(prev.contentHash === m.contentHash && JSON.stringify(prev.installer || null) === JSON.stringify(m.installer || null)){
  console.log('ما في تغيير من آخر مرة (' + prev.version + ')');
  process.exit(0);
}
fs.writeFileSync(OUT, JSON.stringify(m, null, 1));
console.log('✓ public/offline-update.json — النسخة ' + m.version + ' (' + m.files.length + ' ملف)');
if(m.installer) console.log('  installer: ' + m.installer.version);
console.log('ارفع على GitHub متل العادة، وبعدها الزباين بيشوفو «في تحديث» بالبرنامج.');
