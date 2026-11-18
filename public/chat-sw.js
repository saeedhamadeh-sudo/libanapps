// LibanApps Chat — service worker بسيط (لتثبيت التطبيق كـPWA). الشبكة دائماً، بلا كاش للبيانات.
self.addEventListener('install', (e) => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});
