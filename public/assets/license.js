// ============================================================
//  itech — التحقق من الترخيص
//  ملف واحد يُضاف لبرنامج الألمنيوم وبرنامج التجارة
//
//  الاستعمال:
//    <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.0/dist/umd/supabase.min.js"></script>
//    <script src="license.js"></script>
//    <script>
//      itechLicense.init({ product: 'alum' });   // أو 'trade'
//    </script>
//
//  البرنامج بيضل يشتغل على قاعدة بياناته الخاصة.
//  هذا الملف بس بيسأل السيرفر المركزي: هل الترخيص ساري؟
// ============================================================
(function (global) {
  'use strict';

  // السيرفر المركزي للتراخيص (مشروع LibanApps)
  var LICENSE_URL  = 'https://moriwmhlgugmjzddwfgv.supabase.co';

  var LICENSE_ANON = 'sb_publishable_ypfm_aulpcqBpeFpyD_7iw_mA4DNlR5';

  var KEY_STORE = 'itech_license_key';
  var DEV_STORE = 'itech_device_id';
  var CACHE     = 'itech_license_cache';

  function deviceId() {
    var d = localStorage.getItem(DEV_STORE);
    if (!d) {
      d = 'DV-' + Math.random().toString(36).slice(2, 10).toUpperCase() +
          '-' + Date.now().toString(36).toUpperCase();
      localStorage.setItem(DEV_STORE, d);
    }
    return d;
  }

  function deviceName() {
    var ua = navigator.userAgent;
    var os = /Windows/.test(ua) ? 'Windows' : /Android/.test(ua) ? 'Android'
           : /iPhone|iPad/.test(ua) ? 'iOS' : /Mac/.test(ua) ? 'Mac' : 'Other';
    return os + ' · ' + (navigator.language || '');
  }

  // نسخة محفوظة تسمح بالعمل بدون إنترنت لمدة محدودة
  function readCache() {
    try { return JSON.parse(localStorage.getItem(CACHE) || 'null'); } catch (e) { return null; }
  }
  function writeCache(o) {
    try { localStorage.setItem(CACHE, JSON.stringify(o)); } catch (e) {}
  }

  var OFFLINE_GRACE_DAYS = 5;

  async function verify(key, product) {
    var sb = global.supabase.createClient(LICENSE_URL, LICENSE_ANON);
    var res = await sb.rpc('activate_license', {
      p_key: key,
      p_device: deviceId(),
      p_device_name: deviceName(),
      p_product: product
    });
    if (res.error) throw res.error;
    return res.data;
  }

  var MSG = {
    not_found:       'المفتاح غير صحيح',
    wrong_product:   'هذا المفتاح لبرنامج آخر',
    suspended:       'الاشتراك موقوف — تواصل مع الدعم',
    device_mismatch: 'هذا المفتاح مفعّل على جهاز آخر. تواصل معنا لفك الربط.',
    expired:         'انتهت مدة الاشتراك'
  };

  function screen(html) {
    document.body.innerHTML =
      '<div style="font-family:system-ui;max-width:380px;margin:14vh auto;padding:24px;' +
      'background:#fff;border-radius:16px;box-shadow:0 10px 40px rgba(0,0,0,.12);text-align:center">' +
      html + '</div>';
    document.body.style.background = '#F3F4F6';
  }

  function askForKey(product, note) {
    screen(
      '<h2 style="margin:0 0 6px">تفعيل البرنامج</h2>' +
      '<p style="color:#6B7280;font-size:14px;margin:0 0 16px">' + (note || 'أدخل مفتاح التفعيل') + '</p>' +
      '<input id="lk" placeholder="XXXX-XXXX-XXXX-XXXX" style="width:100%;padding:12px;' +
      'border:1px solid #D1D5DB;border-radius:10px;text-align:center;font-size:16px;' +
      'letter-spacing:1px;direction:ltr;text-transform:uppercase">' +
      '<button id="lb" style="width:100%;margin-top:12px;padding:12px;border:0;border-radius:10px;' +
      'background:#111827;color:#fff;font-weight:700;font-size:15px;cursor:pointer">تفعيل</button>' +
      '<div id="lm" style="color:#DC2626;font-size:13px;margin-top:10px"></div>' +
      '<div style="color:#9CA3AF;font-size:12px;margin-top:14px">itech Est. · 03044010</div>'
    );
    document.getElementById('lb').onclick = async function () {
      var k = document.getElementById('lk').value.trim().toUpperCase();
      var m = document.getElementById('lm');
      if (!k) { m.textContent = 'أدخل المفتاح'; return; }
      m.style.color = '#6B7280'; m.textContent = 'عم نتحقق…';
      try {
        var r = await verify(k, product);
        if (r.ok) {
          localStorage.setItem(KEY_STORE, k);
          writeCache({ at: Date.now(), data: r });
          location.reload();
        } else {
          m.style.color = '#DC2626';
          m.textContent = MSG[r.reason] || 'تعذّر التفعيل';
        }
      } catch (e) {
        m.style.color = '#DC2626';
        m.textContent = 'ما في اتصال بالإنترنت';
      }
    };
    document.getElementById('lk').onkeydown = function (e) {
      if (e.key === 'Enter') document.getElementById('lb').click();
    };
  }

  function banner(days) {
    if (days > 15) return;
    var b = document.createElement('div');
    b.style.cssText = 'position:fixed;inset-inline:0;bottom:0;z-index:9999;padding:9px;' +
      'text-align:center;font-family:system-ui;font-size:13.5px;font-weight:700;' +
      'background:' + (days <= 5 ? '#DC2626' : '#F59E0B') + ';color:#fff';
    b.textContent = 'اشتراكك ينتهي بعد ' + days + ' يوم — للتجديد: 03044010';
    document.body.appendChild(b);
  }

  async function init(opts) {
    opts = opts || {};
    var product = opts.product || 'alum';

    if (!LICENSE_URL || !LICENSE_ANON) {
      console.warn('license.js: LICENSE_URL / LICENSE_ANON not set');
      return;
    }

    var key = localStorage.getItem(KEY_STORE);
    if (!key) { askForKey(product); return; }

    try {
      var r = await verify(key, product);
      if (r.ok) {
        writeCache({ at: Date.now(), data: r });
        if (typeof opts.onValid === 'function') opts.onValid(r);
        banner(r.days_left);
        return;
      }
      if (r.reason === 'expired') {
        localStorage.removeItem(CACHE);
        askForKey(product, 'انتهت مدة الاشتراك. للتجديد: 03044010');
        return;
      }
      askForKey(product, MSG[r.reason] || 'تعذّر التحقق');

    } catch (e) {
      // ما في إنترنت: نسمح بالعمل مدة محدودة بالاعتماد على آخر تحقق ناجح
      var c = readCache();
      var okOffline = c && (Date.now() - c.at) < OFFLINE_GRACE_DAYS * 86400000
                        && new Date(c.data.expires_at) > new Date();
      if (okOffline) {
        if (typeof opts.onValid === 'function') opts.onValid(c.data);
        banner(Math.ceil((new Date(c.data.expires_at) - new Date()) / 86400000));
      } else {
        screen('<h2>ما في اتصال</h2><p style="color:#6B7280;font-size:14px">' +
               'البرنامج بحاجة لاتصال بالإنترنت للتحقق من الاشتراك.</p>' +
               '<button onclick="location.reload()" style="margin-top:10px;padding:10px 20px;' +
               'border:0;border-radius:10px;background:#111827;color:#fff;cursor:pointer">إعادة المحاولة</button>');
      }
    }
  }

  global.itechLicense = {
    init: init,
    deviceId: deviceId,
    clear: function () { localStorage.removeItem(KEY_STORE); localStorage.removeItem(CACHE); }
  };

})(window);
