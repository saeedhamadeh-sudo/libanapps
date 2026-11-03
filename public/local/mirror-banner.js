/* LibanApps — شريط «الكمبيوتر الأساسي مطفي» بنسخة القراءة.
   بيفحص كل دقيقة: إذا رجع الكمبيوتر يشتغل، الصفحة بترجع للبرنامج الكامل لحالها. */
(function(){
  'use strict';
  var b = document.createElement('div');
  b.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:2147482500;background:#C98A12;color:#fff;text-align:center;' +
    'padding:8px 12px;font:700 13.5px Cairo,Tajawal,system-ui,sans-serif;direction:rtl;box-shadow:0 2px 10px rgba(0,0,0,.15)';
  b.textContent = '📴 الكمبيوتر الأساسي بالمحل مطفي — عم تشوف آخر نسخة محفوظة (للقراءة بس)';
  function add(){ if(!b.parentNode){ document.body.appendChild(b); document.body.style.paddingTop = '36px'; } }
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', add); else add();
  setInterval(function(){
    fetch('/local-api/status', { cache: 'no-store' }).then(function(r){ return r.json(); })
      .then(function(s){ if(s && !s.mirror) location.reload(); }).catch(function(){});
  }, 60000);
})();
