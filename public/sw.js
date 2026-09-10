// هالملف غرضو الوحيد: يلغي أي Service Worker قديم كان اتسجّل غلط قبل هيك
// (من محاولة تسجيل فاشلة بملف app-alum.html، انشالها بس ضلت آثارها عند بعض الزوار).
// ما منستعمل Service Worker إطلاقاً بهالموقع حالياً.
self.addEventListener('install', function () {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil((async function () {
    // امسح كل الكاش يلي كان محفوظ من قبل
    var keys = await caches.keys();
    await Promise.all(keys.map(function (k) { return caches.delete(k); }));
    // ألغِ تسجيل هالـService Worker نفسو
    await self.registration.unregister();
    // اعمل reload لأي صفحة مفتوحة حالياً حتى تاخد النسخة الحقيقية من السيرفر فوراً
    var clientsList = await self.clients.matchAll({ type: 'window' });
    clientsList.forEach(function (client) { client.navigate(client.url); });
  })());
});
