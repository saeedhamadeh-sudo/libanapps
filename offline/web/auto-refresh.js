/* LibanApps Local — لما ينزل تحديث للبرنامج، الصفحة المفتوحة (عالكمبيوتر أو عالتلفون) بتعرف لحالها:
   · إذا ما حدا عم يستعمل البرنامج (دقيقتين بلا لمس) وما في نافذة مفتوحة → بتتحدّث لحالها
   · وإلا بيطلع شريط صغير «في نسخة جديدة» مع زر تحديث — حتى ما يضيع شي عم ينكتب */
(function(){
  'use strict';
  var cur = null, shown = false, lastActive = Date.now();
  ['mousedown', 'keydown', 'touchstart', 'wheel'].forEach(function(ev){
    window.addEventListener(ev, function(){ lastActive = Date.now(); }, { passive: true, capture: true });
  });
  function busyNow(){
    if(document.querySelector('.modal-bg, .modal.show, dialog[open]')) return true;
    var a = document.activeElement;
    return !!(a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' || a.tagName === 'SELECT') && a.value);
  }
  function banner(){
    if(shown) return; shown = true;
    var b = document.createElement('div');
    b.style.cssText = 'position:fixed;left:12px;right:12px;bottom:12px;z-index:2147483000;max-width:520px;margin:0 auto;' +
      'background:#12324F;color:#fff;border-radius:14px;padding:12px 14px;display:flex;gap:10px;align-items:center;' +
      'font:600 14px Cairo,Tajawal,system-ui,sans-serif;box-shadow:0 10px 30px rgba(0,0,0,.25);direction:rtl';
    b.innerHTML = '<span style="flex:1">✨ نزلت نسخة جديدة من البرنامج</span>' +
      '<button style="border:0;border-radius:10px;padding:8px 14px;background:#E08A2B;color:#fff;font:inherit;cursor:pointer">حدّث هلق</button>';
    b.querySelector('button').onclick = function(){ location.reload(); };
    document.body.appendChild(b);
  }
  function check(){
    fetch('/local-api/status', { cache: 'no-store' }).then(function(r){ return r.json(); }).then(function(s){
      var v = s.webVersion || '';
      if(cur === null){ cur = v; return; }
      if(v === cur) return;
      if(Date.now() - lastActive > 120000 && !busyNow()) location.reload();
      else banner();
    }).catch(function(){});
  }
  check();
  setInterval(check, 60000);
})();
