// ============================================================
//  تجهيز ملفات النسخة المحلية قبل البناء:
//   1) نسخ صفحات البرنامجين و assets من ../public → app/
//   2) تنزيل مكتبة QR والخطوط (Cairo/Tajawal) لتشتغل بلا إنترنت → app/vendor/
//   3) تنزيل cloudflared.exe للوصول من برّا → bin/
//  بيتشغّل تلقائياً مع:  npm run build
// ============================================================
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const PUB = path.join(ROOT, '..', 'public');
const OUT = path.join(ROOT, 'app');
const BIN = path.join(ROOT, 'bin');

function copyDir(src, dst){
  fs.mkdirSync(dst, { recursive: true });
  for(const e of fs.readdirSync(src, { withFileTypes: true })){
    const s = path.join(src, e.name), d = path.join(dst, e.name);
    if(e.isDirectory()) copyDir(s, d); else fs.copyFileSync(s, d);
  }
}
async function get(url, opts){
  const r = await fetch(url, opts);
  if(!r.ok) throw new Error(url + ' → HTTP ' + r.status);
  return r;
}

(async () => {
  // 1) الصفحات
  fs.rmSync(OUT, { recursive: true, force: true });
  fs.mkdirSync(OUT, { recursive: true });
  for(const f of ['app-alum.html', 'app-trade.html']) fs.copyFileSync(path.join(PUB, f), path.join(OUT, f));
  copyDir(path.join(PUB, 'assets'), path.join(OUT, 'assets'));
  for(const f of fs.readdirSync(PUB)) if(/\.(png|ico|json|webmanifest|svg)$/i.test(f)) fs.copyFileSync(path.join(PUB, f), path.join(OUT, f));
  console.log('✓ نسخ صفحات البرنامجين');

  // 2) vendor
  const V = path.join(OUT, 'vendor'); fs.mkdirSync(path.join(V, 'fonts'), { recursive: true });
  try{
    const qr = await (await get('https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js')).text();
    fs.writeFileSync(path.join(V, 'qrcode.min.js'), qr);
    console.log('✓ مكتبة QR');
  }catch(e){ console.warn('⚠ ما قدرنا ننزّل مكتبة QR (رح تنحمّل من الإنترنت):', e.message); }
  try{
    const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';
    let css = await (await get('https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&family=Tajawal:wght@400;500;700&family=Roboto+Mono:wght@500;700&display=swap', { headers: { 'User-Agent': UA } })).text();
    const urls = Array.from(new Set(css.match(/https:\/\/fonts\.gstatic\.com\/[^)]+/g) || []));
    let i = 0;
    for(const u of urls){
      const name = 'f' + (i++) + path.extname(new URL(u).pathname);
      fs.writeFileSync(path.join(V, 'fonts', name), Buffer.from(await (await get(u)).arrayBuffer()));
      css = css.split(u).join(name);
    }
    fs.writeFileSync(path.join(V, 'fonts', 'fonts.css'), css);
    console.log('✓ الخطوط (' + urls.length + ' ملف)');
  }catch(e){ console.warn('⚠ ما قدرنا ننزّل الخطوط (رح تنحمّل من الإنترنت):', e.message); }

  // 3) cloudflared
  fs.mkdirSync(BIN, { recursive: true });
  const exe = path.join(BIN, 'cloudflared.exe');
  if(process.env.SKIP_CLOUDFLARED){ console.log('… تخطّي cloudflared'); return; }
  if(fs.existsSync(exe) && fs.statSync(exe).size > 1e6){ console.log('✓ cloudflared موجود'); return; }
  try{
    const r = await get('https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe', { redirect: 'follow' });
    fs.writeFileSync(exe, Buffer.from(await r.arrayBuffer()));
    console.log('✓ cloudflared.exe');
  }catch(e){ console.warn('⚠ ما قدرنا ننزّل cloudflared — الوصول من برّا ما رح يشتغل لحد ما تحطو بـbin/cloudflared.exe:', e.message); }
})().catch(e => { console.error(e); process.exit(1); });
