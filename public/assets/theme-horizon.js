/* ===== HORIZON JS START — مبدّل ثيم الموقع + تحسينات ثيم «أفق» (المصدر: assets/theme-horizon.js) ===== */
(function(){
  var K='la_site_theme', d=document.documentElement, t=null;
  var FONTS='https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&family=Readex+Pro:wght@500;600;700&display=swap';
  try{ t=localStorage.getItem(K); }catch(e){}
  function fonts(){
    if(document.getElementById('hzFonts')) return;
    var l=document.createElement('link'); l.id='hzFonts'; l.rel='stylesheet'; l.href=FONTS;
    document.head.appendChild(l);
  }
  function meta(v){
    var m=document.querySelector('meta[name="theme-color"]');
    if(m){ if(!m.dataset.orig) m.dataset.orig=m.content; m.content = v==='horizon' ? '#090A1C' : m.dataset.orig; }
  }
  // تطبيق الثيم: يُستدعى من كل صفحة بعد قراءة public_settings، ومن الكاش فوراً لتفادي الوميض
  window.LASiteTheme=function(v){
    v=v||'default';
    if(v==='default') d.removeAttribute('data-theme'); else d.setAttribute('data-theme',v);
    try{ localStorage.setItem(K,v); }catch(e){}
    if(v==='horizon') fonts();
    meta(v);
  };
  if(t && t!=='default'){ d.setAttribute('data-theme',t); if(t==='horizon') fonts(); }

  function ready(){
    meta(d.getAttribute('data-theme')||'default');
    var nav=document.querySelector('nav');
    if(nav){
      var onS=function(){ nav.classList.toggle('hz-scrolled', window.scrollY>8); };
      window.addEventListener('scroll',onS,{passive:true}); onS();
    }
    // إضاءة تتبع الماوس على البطاقات
    document.addEventListener('pointermove',function(e){
      var c=e.target && e.target.closest && e.target.closest('.pcard,.feat>div,.plan');
      if(!c) return;
      var r=c.getBoundingClientRect();
      c.style.setProperty('--hz-x',(e.clientX-r.left)+'px');
      c.style.setProperty('--hz-y',(e.clientY-r.top)+'px');
    },{passive:true});
    // ظهور تدريجي — فقط بصفحات التسويق (فيها hero) وبدون تقليل الحركة
    var reduce=window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if(reduce || !('IntersectionObserver' in window) || !document.querySelector('header.hero')) return;
    var els=document.querySelectorAll('section .head, .pcard, .feat>div, .grid2>*, .band');
    if(!els.length) return;
    var io=new IntersectionObserver(function(list){
      list.forEach(function(en){ if(en.isIntersecting){ en.target.classList.add('hz-in'); io.unobserve(en.target); } });
    },{rootMargin:'0px 0px -8% 0px',threshold:.08});
    Array.prototype.forEach.call(els,function(el){
      var i=Array.prototype.indexOf.call(el.parentNode.children,el);
      el.style.setProperty('--hz-d',Math.min(i,6)*0.07+'s');
      el.classList.add('hz-rv'); io.observe(el);
    });
    d.classList.add('hz-js');
    // أمان: إذا لأي سبب ما اشتغل المراقب، بيظهر كل شي بعد ٣ ثواني
    setTimeout(function(){
      Array.prototype.forEach.call(document.querySelectorAll('.hz-rv:not(.hz-in)'),function(el){
        var r=el.getBoundingClientRect(); if(r.top<window.innerHeight) el.classList.add('hz-in');
      });
    },3000);
  }
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',ready); else ready();
})();
/* ===== HORIZON JS END ===== */
