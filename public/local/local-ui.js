/* LibanApps Local — إضافات الواجهة بالنسخة المحلية:
   · زر واتساب للدعم بالزاوية (مع نبض)
   · «للدعم اتصل: 03/027797» تحت شاشة الدخول */
(function(){
  'use strict';
  var WA = 'https://wa.me/9613027797', TEL = 'tel:+9613027797', SHOW = '03/027797';

  var css = document.createElement('style');
  css.textContent =
    '.la-wa{position:fixed;left:16px;bottom:16px;z-index:2147482000;width:54px;height:54px;border-radius:50%;background:#25D366;' +
    'display:flex;align-items:center;justify-content:center;box-shadow:0 6px 18px rgba(0,0,0,.25);text-decoration:none}' +
    '.la-wa::before,.la-wa::after{content:"";position:absolute;inset:0;border-radius:50%;background:#25D366;z-index:-1;animation:laPulse 2s ease-out infinite}' +
    '.la-wa::after{animation-delay:1s}' +
    '.la-wa svg{width:30px;height:30px;fill:#fff}' +
    '.la-wa:hover{transform:scale(1.06)}' +
    '@keyframes laPulse{0%{transform:scale(1);opacity:.55}100%{transform:scale(1.9);opacity:0}}' +
    '.la-support{text-align:center;margin:14px auto 0;font:600 14px Cairo,Tajawal,system-ui,sans-serif;color:#6A7C8C;direction:rtl}' +
    '.la-support a{color:inherit;text-decoration:none;direction:ltr;unicode-bidi:embed;font-weight:800}' +
    '@media print{.la-wa,.la-support{display:none!important}}';
  document.head.appendChild(css);

  function addWa(){
    if(document.querySelector('.la-wa')) return;
    var a = document.createElement('a');
    a.className = 'la-wa'; a.href = WA; a.target = '_blank'; a.rel = 'noopener'; a.title = 'الدعم على واتساب';
    a.innerHTML = '<svg viewBox="0 0 32 32" aria-hidden="true"><path d="M16.04 3C9.4 3 4 8.33 4 14.9c0 2.1.56 4.15 1.62 5.95L4 29l8.4-1.6a12.2 12.2 0 0 0 3.64.55h.01C22.68 27.95 28 22.62 28 16.05 28 9.4 22.68 3 16.04 3Zm0 22.9c-1.13 0-2.24-.18-3.3-.53l-.24-.08-4.98.95.97-4.8-.16-.25a9.7 9.7 0 0 1-1.52-5.2c0-5.4 4.42-9.8 9.86-9.8 5.43 0 9.85 4.4 9.85 9.86 0 5.45-4.42 9.85-9.48 9.85Zm5.4-7.37c-.3-.15-1.75-.86-2.02-.96-.27-.1-.47-.15-.67.15-.2.3-.77.96-.94 1.16-.17.2-.35.22-.64.07-.3-.15-1.25-.46-2.38-1.47-.88-.78-1.47-1.75-1.64-2.05-.17-.3-.02-.46.13-.6.13-.14.3-.35.44-.52.15-.18.2-.3.3-.5.1-.2.05-.37-.02-.52-.08-.15-.67-1.6-.92-2.2-.24-.57-.48-.5-.67-.5h-.57c-.2 0-.52.07-.8.37-.27.3-1.04 1.02-1.04 2.48 0 1.47 1.07 2.88 1.21 3.08.15.2 2.1 3.2 5.08 4.48.71.31 1.27.5 1.7.63.72.23 1.37.2 1.88.12.57-.08 1.75-.71 2-1.4.25-.69.25-1.28.17-1.4-.07-.13-.27-.2-.57-.35Z"/></svg>';
    document.body.appendChild(a);
  }
  // سطر الدعم تحت كرت الدخول (بيظهر كل ما ترجع شاشة الدخول)
  function addSupport(){
    var u = document.getElementById('login_user') || document.getElementById('l_email');
    var card = u ? (u.closest('.login-card') || u.closest('.card') || u.closest('section') || u.parentElement) : null;
    // شاشات الاشتراك (أكمل بياناتك / انتهى الاشتراك...)
    if(!card){ var l = document.querySelector('a[href^="/account"]'); if(l && l.parentElement && l.parentElement.querySelector('h2')) card = l.parentElement; }
    if(!card || card.querySelector('.la-support')) return;
    var d = document.createElement('div');
    d.className = 'la-support';
    d.innerHTML = 'للدعم اتصل: <a href="' + TEL + '">' + SHOW + '</a>';
    card.appendChild(d);
  }
  function run(){ addWa(); addSupport(); }
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run); else run();
  new MutationObserver(function(){ addSupport(); if(!document.querySelector('.la-wa')) addWa(); })
    .observe(document.documentElement, { childList: true, subtree: true });
})();
