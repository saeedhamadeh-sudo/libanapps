// LibanApps — تشغيل برامج المحاسبة بلا إنترنت
// «الشبكة أولاً»: إذا في نت منجيب النسخة الجديدة دايماً (ومنخزّنها)، وإذا ما في نت منستعمل آخر نسخة مخزّنة.
// ما منلمس طلبات قاعدة البيانات (Supabase) ولا أي صفحة تانية بالموقع.
var CACHE = 'la-app-offline-v1';
var CDN = [
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
  'https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js'
];

self.addEventListener('install', function (e) { self.skipWaiting(); });
self.addEventListener('activate', function (e) {
  e.waitUntil((async function () {
    var keys = await caches.keys();
    await Promise.all(keys.filter(function (k) { return k.indexOf('la-app-offline-') === 0 && k !== CACHE; }).map(function (k) { return caches.delete(k); }));
    await self.clients.claim();
  })());
});

function handled(url, req) {
  if (req.method !== 'GET') return false;
  if (CDN.indexOf(url.href) !== -1 || /^https:\/\/cdn\.jsdelivr\.net\/npm\/@supabase\/supabase-js@2/.test(url.href)) return true;
  if (url.origin !== self.location.origin) return false;
  var p = url.pathname;
  return p === '/app-trade.html' || p === '/app-alum.html' || p.indexOf('/portal-trade/') === 0 || p.indexOf('/portal/') === 0 ||
         p === '/assets/lang-engine.js' || p === '/assets/acc-i18n.js';
}

self.addEventListener('fetch', function (e) {
  var req = e.request, url;
  try { url = new URL(req.url); } catch (x) { return; }
  if (!handled(url, req)) return;
  e.respondWith((async function () {
    var cache = await caches.open(CACHE);
    // الصفحة نفسها بتتخزّن بلا الـ query (?x=..) حتى تنفتح بلا نت مهما كان الرابط
    var key = (req.mode === 'navigate') ? new Request(url.origin + url.pathname) : req;
    try {
      var res = await fetch(req);
      if (res && (res.ok || res.type === 'opaque')) { try { await cache.put(key, res.clone()); } catch (x) {} }
      return res;
    } catch (err) {
      var hit = await cache.match(key) || await cache.match(req, { ignoreSearch: true });
      if (hit) return hit;
      throw err;
    }
  })());
});
