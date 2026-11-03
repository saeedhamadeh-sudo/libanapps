// ============================================================
//  LibanApps Local — السيرفر المحلي
//  بيشتغل جوّا البرنامج المثبّت على الكمبيوتر:
//   · بيعرض برنامج الألمنيوم والتجارة على http://127.0.0.1:47801
//   · البيانات كلها بـSQLite على الكمبيوتر
//   · نفق Cloudflare (اختياري) للفوت من برّا
//  للتجربة بلا Electron:  node server/index.js
// ============================================================
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Store } = require('./store');
const { DataEngine, PRODUCTS } = require('./data');
const { License } = require('./license');
const { Backup } = require('./backup');
const { Tunnel } = require('./tunnel');
const { importFromCloud } = require('./cloud-import');
const { Updater } = require('./updater');

const VERSION = require('../package.json').version;
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'application/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.webp': 'image/webp', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf', '.webmanifest': 'application/manifest+json' };
const APP_PAGES = { '/alum': 'app-alum.html', '/trade': 'app-trade.html' };

function start(opts){
  const port = opts.port || 47801;
  const dataDir = opts.dataDir;
  const appDir = opts.appDir;                       // نسخة من public/ (صفحات البرامج + assets + vendor)
  const webDir = opts.webDir || path.join(__dirname, '..', 'web');
  fs.mkdirSync(dataDir, { recursive: true });

  const store = new Store(path.join(dataDir, 'libanapps.db'));
  const license = new License(store);
  const engine = new DataEngine(store, { clientId: () => license.clientId(), access: p => license.access(p) });
  const backup = new Backup(store, license, { backupDir: opts.backupDir || path.join(dataDir, 'backups'), tmpDir: path.join(dataDir, 'tmp') });
  const tunnel = new Tunnel(store, { port, cloudflaredPath: opts.cloudflaredPath });
  const importJobs = {};
  const htmlCache = new Map();
  const updater = new Updater(store, { appDir, dataDir, version: VERSION, runInstaller: opts.runInstaller, onChange: () => htmlCache.clear() });

  // ---------- تحويل صفحة البرنامج لتشتغل محلياً ----------
  function appHtml(file){
    const full = updater.resolve(file);
    const st = fs.statSync(full);
    const c = htmlCache.get(full);
    if(c && c.m === st.mtimeMs) return c.html;
    let html = fs.readFileSync(full, 'utf8');
    html = html.replace(/<script[^>]+@supabase\/supabase-js[^>]*><\/script>/,
      '<script>window.LA_LOCAL={version:"' + VERSION + '"};</script><script src="/local/supabase-local.js?v=' + VERSION + '"></script><script src="/local/auto-refresh.js?v=' + VERSION + '" defer></script><script src="/local/local-ui.js?v=' + VERSION + '" defer></script>');
    if(fs.existsSync(path.join(appDir, 'vendor', 'qrcode.min.js')))
      html = html.replace(/https:\/\/cdnjs\.cloudflare\.com\/ajax\/libs\/qrcodejs\/1\.0\.0\/qrcode\.min\.js/g, '/vendor/qrcode.min.js');
    if(fs.existsSync(path.join(appDir, 'vendor', 'fonts', 'fonts.css')))
      html = html.replace(/<link[^>]+fonts\.googleapis\.com\/css2[^>]*>/, '<link href="/vendor/fonts/fonts.css" rel="stylesheet">')
        .replace(/<link rel="preconnect"[^>]+fonts\.(googleapis|gstatic)\.com[^>]*>/g, '');
    htmlCache.set(full, { m: st.mtimeMs, html });
    return html;
  }

  // ---------- مساعدات ----------
  const isLocalReq = req => {
    if(req.headers['cf-connecting-ip'] || req.headers['cf-ray'] || req.headers['x-forwarded-for']) return false;
    const ra = req.socket.remoteAddress || '';
    if(!(ra === '127.0.0.1' || ra === '::1' || ra === '::ffff:127.0.0.1')) return false;
    const host = String(req.headers.host || '');
    return host === '127.0.0.1:' + port || host === 'localhost:' + port;
  };
  const send = (res, code, body, type, extra) => {
    res.writeHead(code, Object.assign({ 'Content-Type': type || 'application/json; charset=utf-8', 'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'same-origin' }, extra || {}));
    res.end(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body));
  };
  const json = (res, obj, code) => send(res, code || 200, obj);
  const readBody = (req, limit) => new Promise((resolve, reject) => {
    const chunks = []; let n = 0;
    req.on('data', c => { n += c.length; if(n > (limit || 60e6)){ reject(new Error('too large')); req.destroy(); } else chunks.push(c); });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
  const readJson = async req => { const b = await readBody(req); return b.length ? JSON.parse(b.toString('utf8')) : {}; };
  function serveFile(res, base, rel, resolved){
    const full = resolved || path.normalize(path.join(base, rel));
    if(!resolved && !full.startsWith(path.normalize(base + path.sep))) return send(res, 403, 'forbidden', 'text/plain');
    fs.stat(full, (err, st) => {
      if(err || !st.isFile()) return send(res, 404, 'not found', 'text/plain');
      res.writeHead(200, { 'Content-Type': MIME[path.extname(full).toLowerCase()] || 'application/octet-stream', 'Content-Length': st.size,
        'Cache-Control': /\.(woff2?|ttf|png|jpe?g|svg|webp|ico)$/.test(full) ? 'public, max-age=604800' : 'no-cache' });
      fs.createReadStream(full).pipe(res);
    });
  }

  // ---------- لايف بين الأجهزة (بدل Supabase Realtime) ----------
  const channels = new Map();   // name -> Set<{res, conn}>
  function liveSubscribe(req, res, url){
    const ch = url.searchParams.get('ch') || '', conn = url.searchParams.get('conn') || '';
    if(!/^la-(alum|trade)-[\w-]+$/.test(ch)) return send(res, 400, 'bad channel', 'text/plain');
    res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
    res.write('retry: 3000\n\n');
    const sub = { res, conn };
    if(!channels.has(ch)) channels.set(ch, new Set());
    channels.get(ch).add(sub);
    const ping = setInterval(() => { try{ res.write(': ping\n\n'); }catch(e){} }, 25000);
    req.on('close', () => { clearInterval(ping); const s = channels.get(ch); if(s){ s.delete(sub); if(!s.size) channels.delete(ch); } });
  }
  function liveSend(ch, from, msg){
    const s = channels.get(ch); if(!s) return;
    const line = 'data: ' + JSON.stringify(msg) + '\n\n';
    s.forEach(sub => { if(sub.conn !== from) try{ sub.res.write(line); }catch(e){} });
  }

  // ---------- واجهات المدير (من الكمبيوتر نفسه بس) ----------
  async function adminApi(req, res, p){
    if(req.method === 'POST' && req.headers['x-la-admin'] !== '1') return json(res, { error: 'forbidden' }, 403);
    const body = req.method === 'POST' && p !== '/backup/upload' ? await readJson(req) : {};
    switch(p){
      case '/license': return json(res, license.summary());
      case '/license/signin': return json(res, await license.signIn(String(body.email || '').trim(), String(body.password || '')));
      case '/license/serial': return json(res, license.activateSerial(body.serial));
      case '/license/refresh': return json(res, await license.refresh());
      case '/license/signout': license.signOut(); return json(res, license.summary());
      case '/users': return json(res, { alum: engine.listUsers('alum'), trade: engine.listUsers('trade') });
      case '/users/save': return json(res, engine.saveUser(body.product, body));
      case '/tunnel': return json(res, tunnel.status());
      case '/tunnel/save': return json(res, tunnel.setCfg(body));
      case '/tunnel/domain': {
        // الدومين الخاص للزبون (app.mydomain.com) — action: add | refresh | remove
        if(license.state.mode !== 'cloud') throw new Error('لازم تسجّل دخول بحساب libanapps.com من «التفعيل» أول');
        const tok = await license.token();
        const r = await fetch((process.env.LA_SITE || 'https://libanapps.com') + '/api/tunnel/domain', {
          method: 'POST', headers: { Authorization: 'Bearer ' + tok, 'Content-Type': 'application/json' },
          body: JSON.stringify({ action: body.action || 'refresh', domain: body.domain || '' }), signal: AbortSignal.timeout(60000) });
        const j = await r.json().catch(() => ({}));
        if(!r.ok || !j.ok) throw new Error(j.error || ('HTTP ' + r.status));
        return json(res, j);
      }
      case '/tunnel/auto': {
        // كبسة وحدة: libanapps.com بيعمل النفق والرابط، ومنشغّلو هون
        if(license.state.mode !== 'cloud') throw new Error('لازم تسجّل دخول بحساب libanapps.com من «التفعيل» أول');
        const tok = await license.token();
        const r = await fetch((process.env.LA_SITE || 'https://libanapps.com') + '/api/tunnel/provision', {
          method: 'POST', headers: { Authorization: 'Bearer ' + tok, 'Content-Type': 'application/json' },
          body: JSON.stringify({ subdomain: String(body.subdomain || '') }), signal: AbortSignal.timeout(60000) });
        const j = await r.json().catch(() => ({}));
        if(!r.ok || !j.ok) throw new Error(j.error || ('HTTP ' + r.status));
        return json(res, tunnel.setCfg({ enabled: true, mode: 'token', token: j.token, hostname: j.hostname }));
      }
      case '/backup': return json(res, backup.status());
      case '/backup/save': return json(res, backup.setCfg(body));
      case '/backup/now': return json(res, await backup.run('manual'));
      case '/backup/restore-local': return json(res, await backup.restoreLocalFile(body.name, body.passphrase));
      case '/backup/cloud-list': return json(res, await backup.listCloud());
      case '/backup/restore-cloud': return json(res, await backup.restore(await backup.downloadCloud(body.name), body.passphrase));
      case '/backup/upload': {
        const buf = await readBody(req, 500e6);
        return json(res, await backup.restore(buf, decodeURIComponent(String(req.headers['x-la-pass'] || ''))));
      }
      case '/counts': return json(res, store.counts());
      case '/update': return json(res, updater.status());
      case '/update/check': await updater.check(); return json(res, updater.status());
      case '/update/apply': return json(res, await updater.apply());
      case '/update/rollback': return json(res, updater.rollback());
      case '/update/installer': return json(res, await updater.downloadInstaller(false));
      case '/update/auto': return json(res, updater.setAuto(body.on));
      case '/import': {
        const id = crypto.randomBytes(6).toString('hex');
        importJobs[id] = { state: 'running', msg: 'بلّشنا...' };
        importFromCloud(engine, license, body.product, String(body.username || ''), String(body.password || ''), body.totp,
          m => { importJobs[id].msg = m; })
          .then(r => { importJobs[id] = { state: 'done', msg: 'تم', result: r }; })
          .catch(e => { importJobs[id] = { state: 'error', msg: String(e && e.message || e) }; });
        return json(res, { id });
      }
      case '/import/status': return json(res, importJobs[body.id] || { state: 'error', msg: 'مش موجود' });
      case '/open-folder': if(opts.openPath) opts.openPath(backup.dir); return json(res, { ok: true });
      default: return json(res, { error: 'not found' }, 404);
    }
  }

  // ---------- الطلبات ----------
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    const p = url.pathname;
    try{
      if(p === '/local-api/q' && req.method === 'POST'){
        const q = await readJson(req);
        return json(res, engine.query(q, String(req.headers['x-la-sid'] || '')));
      }
      if(p.startsWith('/local-api/rpc/') && req.method === 'POST'){
        const args = await readJson(req);
        return json(res, engine.rpc(p.slice(15), args, String(req.headers['x-la-sid'] || '')));
      }
      if(p === '/local-api/live' && req.method === 'GET') return liveSubscribe(req, res, url);
      if(p === '/local-api/live' && req.method === 'POST'){
        const b = await readJson(req);
        if(/^la-(alum|trade)-[\w-]+$/.test(b.ch || '')) liveSend(b.ch, b.conn, { event: b.event, payload: b.payload });
        return json(res, { ok: true });
      }
      if(p === '/local-api/status'){
        const local = isLocalReq(req);
        return json(res, { version: VERSION, webVersion: updater.state.version || 'bundled', local, alum: license.access('alum'), trade: license.access('trade'),
          licensed: !!license.state.mode, desktop: !!opts.desktop, engine: store.db.__engine,
          update: local ? (function(){ const l = updater.status().last; return l && !l.error ? { web: !!l.webAvailable, installer: l.installer, needsInstaller: !!l.needsInstaller } : null; })() : undefined });
      }
      if(p.startsWith('/local-api/admin/')){
        if(!isLocalReq(req)) return json(res, { error: 'هالإعدادات بتنفتح من الكمبيوتر الأساسي بس' }, 403);
        return await adminApi(req, res, p.slice(16));
      }
      // صور المنتجات من الإنترنت (برنامج التجارة) — بتمرق عبر libanapps.com إذا في نت
      if(p === '/api/app/img-search' || p === '/api/app/img-fetch'){
        try{
          const r = await fetch('https://libanapps.com' + p + url.search, { signal: AbortSignal.timeout(20000) });
          const buf = Buffer.from(await r.arrayBuffer());
          return send(res, r.status, buf, r.headers.get('content-type') || 'application/octet-stream');
        }catch(e){ return json(res, { ok: false, error: 'ما في إنترنت' }, 503); }
      }
      if(p === '/api/portal-client' || p === '/api/portal-token') return json(res, { ok: false });
      if(p === '/sw.js' || p === '/app-sw.js'){
        return send(res, 200, "self.addEventListener('install',()=>self.skipWaiting());self.addEventListener('activate',e=>e.waitUntil(self.registration.unregister()));", MIME['.js']);
      }
      const clean = p.replace(/\/+$/, '') || '/';
      if(APP_PAGES[clean]) return send(res, 200, appHtml(APP_PAGES[clean]), MIME['.html']);
      // روابط النسخة الأونلاين القديمة (/portal-trade/اسم-المحل) — بتفتح البرنامج المحلي
      const pm = clean.match(/^\/portal-(trade|alum)(\/|$)/);
      if(pm){ res.writeHead(302, { Location: '/' + pm[1] }); return res.end(); }
      if(clean === '/') return serveFile(res, webDir, 'home.html');
      if(['/login', '/account', '/super', '/signup', '/reset'].includes(clean)){ res.writeHead(302, { Location: '/#license' }); return res.end(); }
      if(p.startsWith('/local/')) return serveFile(res, webDir, p.slice(7));
      const rel = path.posix.normalize(decodeURIComponent(p.slice(1)));
      if(rel.startsWith('..') || rel.includes('\\') || rel.includes(':') || path.isAbsolute(rel)) return send(res, 403, 'forbidden', 'text/plain');
      return serveFile(res, appDir, rel, updater.resolve(rel));
    }catch(e){
      console.error('[local]', p, e);
      return json(res, { error: String(e && e.message || e) }, 500);
    }
  });

  return new Promise((resolve, reject) => {
    server.on('error', reject);
    server.listen(port, '127.0.0.1', () => {
      license.start();
      if(license.state.mode === 'cloud') license.refresh().catch(() => {});
      backup.start();
      updater.start();
      tunnel.start();
      resolve({ server, port, store, license, backup, tunnel, engine, updater,
        stop: async () => { tunnel.stop(); server.close(); store.close(); } });
    });
  });
}

module.exports = { start, VERSION };

if(require.main === module){
  const root = path.join(__dirname, '..');
  start({
    port: Number(process.env.PORT) || 47801,
    dataDir: process.env.LA_DATA || path.join(root, '.data'),
    appDir: process.env.LA_APP || (fs.existsSync(path.join(root, 'app')) ? path.join(root, 'app') : path.join(root, '..', 'public')),
    cloudflaredPath: process.env.CLOUDFLARED || ''
  }).then(s => console.log('LibanApps Local → http://127.0.0.1:' + s.port));
}
