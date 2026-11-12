/* LibanApps — WhatsApp connector (واتساب ويب على كمبيوتر المكتب)
   بيشتغل على http://127.0.0.1:3999 بس (ما بينفتح من برا الكمبيوتر).
   البرنامج على libanapps.com بيحكي معو بمفتاح سري (config.json). */
'use strict';
const http = require('http'), fs = require('fs'), path = require('path'), crypto = require('crypto');
// Baileys 7 (بلا git) — منحمّلو بـ import حتى يشتغل سواء كان ESM أو CommonJS
let B = null, makeWASocket, useMultiFileAuthState, DisconnectReason, fetchLatestBaileysVersion, Browsers, makeCacheableSignalKeyStore, pino;
async function lib() {
  if (B) return;
  const m = await import('@whiskeysockets/baileys');
  const d = (m.default && m.default.default) ? m.default : m;
  makeWASocket = (typeof m.makeWASocket === 'function' && m.makeWASocket) || (typeof m.default === 'function' && m.default) || (d.default && typeof d.default === 'function' && d.default) || d.makeWASocket;
  useMultiFileAuthState = m.useMultiFileAuthState || d.useMultiFileAuthState;
  DisconnectReason = m.DisconnectReason || d.DisconnectReason;
  fetchLatestBaileysVersion = m.fetchLatestBaileysVersion || d.fetchLatestBaileysVersion;
  Browsers = m.Browsers || d.Browsers;
  makeCacheableSignalKeyStore = m.makeCacheableSignalKeyStore || d.makeCacheableSignalKeyStore;
  const pm = await import('pino'); pino = pm.default || pm;
  B = m;
}

const DIR = __dirname, CFG = path.join(DIR, 'config.json'), AUTH = path.join(DIR, 'auth');
let cfg = {}; try { cfg = JSON.parse(fs.readFileSync(CFG, 'utf8')); } catch (e) {}
if (!cfg.key) cfg.key = crypto.randomBytes(12).toString('hex');
cfg.port = cfg.port || 3999;
cfg.origins = cfg.origins || ['https://libanapps.com', 'https://www.libanapps.com'];
cfg.minGapMs = cfg.minGapMs || 3500;          // أقل وقت بين رسالتين (يخفف الحظر)
cfg.maxGapMs = cfg.maxGapMs || 7000;
fs.writeFileSync(CFG, JSON.stringify(cfg, null, 2));

let sock = null, starting = false;
const ACKS = new Map(), LOG = path.join(__dirname, 'sent.log');
// libsignal بيطبع جلسات التشفير كاملة على الشاشة — منخبّيها
for (const k of ['log', 'info', 'warn']) { const o = console[k].bind(console);
  console[k] = (...a) => { const f = typeof a[0] === 'string' ? a[0] : ''; if (/^(Closing|Removing old closed|Migrating|Session already|Decrypted message with closed)/i.test(f) || (a[0] && a[0].constructor && a[0].constructor.name === 'SessionEntry')) return; o(...a); }; }
function logLine(s) { const l = new Date().toLocaleString('en-GB') + '  ' + s; console.log(l); try { fs.appendFileSync(LOG, l + '\n'); } catch (e) {} }
const S = { status: 'starting', qr: null, me: null, sent: 0, lastError: null };

async function start() {
  if (starting) return; starting = true;
  try {
    await lib();
    const { state, saveCreds } = await useMultiFileAuthState(AUTH);
    let version; try { ({ version } = await fetchLatestBaileysVersion()); } catch (e) {}
    const logger = pino({ level: 'silent' });
    const auth = makeCacheableSignalKeyStore ? { creds: state.creds, keys: makeCacheableSignalKeyStore(state.keys, logger) } : state;
    sock = makeWASocket({ auth, version, logger, browser: Browsers ? Browsers.windows('LibanApps') : ['LibanApps', 'Chrome', '1.0'],
      printQRInTerminal: false, markOnlineOnConnect: false, syncFullHistory: false, getMessage: async () => undefined });
    sock.ev.on('creds.update', saveCreds);
    // تأكيد وصول الرسالة لسيرفر واتساب (status 2) أو للزبون (3) أو قراءتها (4)
    sock.ev.on('messages.update', (ups) => { for (const u of ups || []) { const id = u.key && u.key.id, st = u.update && u.update.status;
      if (id && st != null && ACKS.has(id)) ACKS.get(id)(st, u.update.messageStubParameters); } });
    sock.ev.on('connection.update', (u) => {
      if (u.qr) { S.qr = u.qr; S.status = 'qr'; console.log('📱 امسح رمز QR من إعدادات البرنامج (واتساب ← الأجهزة المرتبطة)'); }
      if (u.connection === 'open') { S.status = 'connected'; S.qr = null; S.me = sock.user ? { id: sock.user.id.split(':')[0].split('@')[0], name: sock.user.name || '' } : null;
        console.log('✅ واتساب مربوط:', S.me && S.me.id); }
      if (u.connection === 'close') {
        const code = u.lastDisconnect && u.lastDisconnect.error && u.lastDisconnect.error.output && u.lastDisconnect.error.output.statusCode;
        if (code === DisconnectReason.loggedOut) { try { fs.rmSync(AUTH, { recursive: true, force: true }); } catch (e) {} S.me = null; S.status = 'starting'; console.log('🔌 تم فك الربط'); }
        else S.status = 'reconnecting';
        starting = false; setTimeout(start, 2500);
      }
    });
  } catch (e) { S.lastError = String(e && e.message || e); console.log('⚠️', S.lastError); starting = false; setTimeout(start, 5000); return; }
  starting = false;
}

// إرسال بالدور مع فاصل عشوائي بين الرسائل
let chain = Promise.resolve(), lastAt = 0;
function queue(fn) { const p = chain.then(async () => {
    const gap = cfg.minGapMs + Math.random() * (cfg.maxGapMs - cfg.minGapMs), wait = lastAt + gap - Date.now();
    if (wait > 0) await new Promise(r => setTimeout(r, wait));
    try { return await fn(); } finally { lastAt = Date.now(); } });
  chain = p.catch(() => {}); return p; }

function err(code, msg) { const e = new Error(msg || code); e.code = code; return e; }
async function send(b) {
  if (S.status !== 'connected' || !sock) throw err('not_connected');
  const num = String(b.to || '').replace(/\D/g, '');
  if (num.length < 8) throw err('bad_number');
  const text = String(b.text || '').slice(0, 6000);
  return queue(async () => {
    const r = (await sock.onWhatsApp(num))[0];
    if (!r || !r.exists) { logLine('X ' + num + ' - not on WhatsApp'); throw err('not_on_whatsapp'); }
    let content;
    if (b.doc_url && /^https:\/\//.test(b.doc_url)) {
      const res = await fetch(b.doc_url); if (!res.ok) throw err('doc_fetch');
      content = { document: Buffer.from(await res.arrayBuffer()), mimetype: 'application/pdf', fileName: String(b.doc_name || 'invoice.pdf').slice(0, 80), caption: text };
    } else { if (!text) throw err('empty'); content = { text }; }
    // ارسال + انتظار تأكيد سيرفر واتساب (لحد 20 ثانية)
    async function trySend(jid) {
      const m = await sock.sendMessage(jid, content), id = m && m.key && m.key.id;
      if (!id) return { st: null };
      return await new Promise((ok) => { const tm = setTimeout(() => { ACKS.delete(id); ok({ id, st: null }); }, 20000);
        ACKS.set(id, (v, prm) => { if (v >= 2 || v === 0) { clearTimeout(tm); ACKS.delete(id); ok({ id, st: v, code: (prm || []).join(',') }); } }); });
    }
    let a = await trySend(r.jid);
    if (a.st === 0) {
      // 463 = واتساب قافل الرقم مؤقتاً عن مراسلة ناس ما راسلوه قبل. إعادة المحاولة بتزيد الحظر — ما منعيد.
      logLine('X ' + num + ' - REJECTED by WhatsApp' + (a.code ? ' (code ' + a.code + ')' : '') +
        (a.code === '463' ? ' - this number is temporarily locked from messaging people who never chatted with it' : ''));
      throw err(a.code === '463' ? 'wa_463' : 'rejected');
    }
    S.sent++; logLine((a.st >= 2 ? 'OK ' : '.. ') + num + (a.st >= 3 ? ' - delivered' : a.st === 2 ? ' - sent' : ' - sent (no confirmation yet)'));
    return { ok: true, id: a.id, to: num, status: a.st };
  });
}

function allowOrigin(o) { return !!o && (cfg.origins.indexOf(o) >= 0 || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(o)); }
function reply(req, res, code, obj, type) {
  const o = req.headers.origin, h = { 'Content-Type': type || 'application/json; charset=utf-8', 'Cache-Control': 'no-store' };
  if (allowOrigin(o)) Object.assign(h, { 'Access-Control-Allow-Origin': o, 'Vary': 'Origin', 'Access-Control-Allow-Headers': 'content-type,x-key',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS', 'Access-Control-Allow-Private-Network': 'true', 'Access-Control-Max-Age': '600' });
  res.writeHead(code, h); res.end(type ? obj : JSON.stringify(obj));
}
function body(req) { return new Promise((ok) => { let d = ''; req.on('data', c => { d += c; if (d.length > 1e6) req.destroy(); }); req.on('end', () => { try { ok(JSON.parse(d || '{}')); } catch (e) { ok({}); } }); }); }

http.createServer(async (req, res) => {
  const u = new URL(req.url, 'http://x'), p = u.pathname;
  if (req.method === 'OPTIONS') return reply(req, res, 204, '', 'text/plain');
  // صفحة الربط: بتبعت المفتاح للبرنامج يلّي فتحها (من المواقع المسموحة بس)
  if (p === '/pair') {
    const html = '<!doctype html><meta charset="utf-8"><title>LibanApps WhatsApp</title><body style="font-family:Tahoma;text-align:center;padding:40px">' +
      '<h2>✅ تم ربط البرنامج بواتساب المكتب</h2><p>تقدر تسكّر هالنافذة.</p><script>var K=' + JSON.stringify(cfg.key) + ',O=' + JSON.stringify(cfg.origins.concat(['http://localhost:8787', 'http://127.0.0.1:8787'])) + ';' +
      'if(window.opener){O.forEach(function(o){try{window.opener.postMessage({lawa_key:K},o)}catch(e){}});setTimeout(function(){window.close()},1200)}else{document.body.insertAdjacentHTML("beforeend","<p>افتحها من إعدادات البرنامج</p>")}</script>';
    return reply(req, res, 200, html, 'text/html; charset=utf-8');
  }
  if (p === '/') return reply(req, res, 200, '<!doctype html><meta charset="utf-8"><body style="font-family:Tahoma;padding:30px"><h2>LibanApps — WhatsApp</h2><p>الحالة: <b>' + S.status + '</b>' + (S.me ? ' — ' + S.me.id : '') + '</p><p>شغّال. اربط من إعدادات البرنامج.</p>', 'text/html; charset=utf-8');
  if (req.headers['x-key'] !== cfg.key) return reply(req, res, 401, { ok: false, error: 'bad_key' });
  try {
    if (p === '/status') return reply(req, res, 200, { ok: true, status: S.status, qr: S.qr, me: S.me, sent: S.sent, version: 4 });
    if (p === '/logout' && req.method === 'POST') { try { await sock.logout(); } catch (e) {} try { fs.rmSync(AUTH, { recursive: true, force: true }); } catch (e) {} S.status = 'starting'; S.me = null; setTimeout(start, 1000); return reply(req, res, 200, { ok: true }); }
    if (p === '/send' && req.method === 'POST') { const r = await send(await body(req)); return reply(req, res, 200, r); }
    return reply(req, res, 404, { ok: false, error: 'not_found' });
  } catch (e) { S.lastError = e.code || String(e.message || e); if (p === '/send') logLine('X send error: ' + S.lastError);
    return reply(req, res, e.code === 'not_connected' ? 409 : 400, { ok: false, error: e.code || String(e.message || e) }); }
}).listen(cfg.port, '127.0.0.1', () => {
  console.log('LibanApps WhatsApp connector — http://127.0.0.1:' + cfg.port);
  console.log('خلّي هالشباك مفتوح. افتح البرنامج ← الإعدادات ← ربط واتساب.');
  start();
});
