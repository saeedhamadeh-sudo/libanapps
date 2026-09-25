/* ===== HORIZON JS START — مبدّل ثيم الموقع + تحسينات ثيم «أفق» (المصدر: assets/theme-horizon.js) ===== */
(function(){
  var K='la_site_theme', d=document.documentElement, t=null, isReady=false;
  var FONTS='https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&family=Readex+Pro:wght@500;600;700&display=swap';
  try{ t=localStorage.getItem(K); }catch(e){}
  function on(){ return d.getAttribute('data-theme')==='horizon'; }
  function reduce(){ return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches); }
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
    if(isReady){ if(v==='horizon') enhance(); else teardown(); }
  };
  if(t && t!=='default'){ d.setAttribute('data-theme',t); if(t==='horizon') fonts(); }

  function el(tag,cls,html){ var e=document.createElement(tag); if(cls) e.className=cls; if(html!=null) e.innerHTML=html; e.setAttribute('data-hz',''); return e; }
  var ICON={
    check:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
    bag:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 8h12l-1 12H7L6 8z"/><path d="M9 8V6a3 3 0 016 0v2"/></svg>',
    bill:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 3h12v18l-3-2-3 2-3-2-3 2z"/><path d="M9 8h6M9 12h6"/></svg>',
    box:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7l9-4 9 4-9 4-9-4z"/><path d="M3 7v10l9 4 9-4V7"/></svg>',
    eye:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>',
    eyeOff:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3l18 18"/><path d="M10.6 5.1A10 10 0 0112 5c6.4 0 10 7 10 7a17 17 0 01-3.2 4.1M6.6 6.6A17 17 0 002 12s3.6 7 10 7a9.6 9.6 0 005.4-1.6"/><path d="M9.9 9.9a3 3 0 004.2 4.2"/></svg>',
    menu:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h10"/></svg>'
  };

  /* ---------- تحسينات تشتغل مرة وحدة (تحقق من الثيم وقت الحدث) ---------- */
  function once(){
    var nav=document.querySelector('nav');
    if(nav){
      var onS=function(){ nav.classList.toggle('hz-scrolled', window.scrollY>8); };
      window.addEventListener('scroll',onS,{passive:true}); onS();
    }
    // شريط تقدّم القراءة
    window.addEventListener('scroll',function(){
      var p=document.getElementById('hzProg'); if(!p) return;
      var h=document.documentElement.scrollHeight-window.innerHeight;
      p.style.transform='scaleX('+(h>0?Math.min(1,window.scrollY/h):0)+')';
    },{passive:true});
    // إضاءة وميلان البطاقات مع الماوس
    document.addEventListener('pointermove',function(e){
      if(!on()||e.pointerType==='touch') return;
      var c=e.target && e.target.closest && e.target.closest('.pcard,.feat>div,.plan');
      if(c){
        var r=c.getBoundingClientRect(), x=e.clientX-r.left, y=e.clientY-r.top;
        c.style.setProperty('--hz-x',x+'px'); c.style.setProperty('--hz-y',y+'px');
        if(!reduce() && c.classList.contains('pcard')){
          c.style.setProperty('--hz-ry',((x/r.width)-.5)*8+'deg');
          c.style.setProperty('--hz-rx',(.5-(y/r.height))*8+'deg');
        }
      }
      var hero=e.target && e.target.closest && e.target.closest('header.hero,.hz-aside');
      if(hero && !reduce()){
        var hr=hero.getBoundingClientRect();
        hero.style.setProperty('--hz-px',((e.clientX-hr.left)/hr.width-.5).toFixed(3));
        hero.style.setProperty('--hz-py',((e.clientY-hr.top)/hr.height-.5).toFixed(3));
      }
    },{passive:true});
    document.addEventListener('pointerout',function(e){
      var c=e.target && e.target.closest && e.target.closest('.pcard');
      if(c && !c.contains(e.relatedTarget)){ c.style.removeProperty('--hz-rx'); c.style.removeProperty('--hz-ry'); }
    },{passive:true});
    // انتقال ناعم لما تتغيّر اللغة
    var orig=window.setSiteLang, first=true;
    if(typeof orig==='function' && !orig.__hz){
      var wrapped=function(l){
        if(first || !on() || reduce() || !document.startViewTransition){ first=false; return orig(l); }
        document.startViewTransition(function(){ orig(l); });
      };
      wrapped.__hz=1; window.setSiteLang=wrapped;
    }
  }

  /* ---------- تحسينات خاصة بثيم «أفق» (تنضاف وتنشال مع الثيم) ---------- */
  function enhance(){
    if(!on() || d.classList.contains('hz-on')) return;
    d.classList.add('hz-on');
    var page=(location.pathname.split('/').pop()||'index').replace('.html','');

    // شريط التقدّم
    document.body.appendChild(el('div','hz-prog')).id='hzProg';

    // قائمة الموبايل
    var row=document.querySelector('nav .row'), links=document.querySelector('nav .links');
    if(row && links){
      var bt=el('button','hz-burger',ICON.menu); bt.type='button'; bt.setAttribute('aria-label','القائمة'); bt.setAttribute('aria-expanded','false');
      bt.addEventListener('click',function(){
        var n=document.querySelector('nav'), o=n.classList.toggle('hz-open'); bt.setAttribute('aria-expanded',o?'true':'false');
      });
      links.addEventListener('click',function(){ var n=document.querySelector('nav'); n.classList.remove('hz-open'); bt.setAttribute('aria-expanded','false'); });
      row.insertBefore(bt,row.firstChild);
    }

    // صفحات الدخول والتسجيل: لوحة جانبية + حركة فتح البطاقة
    var form=document.querySelector('section > .wrap.form');
    if(form){
      var sec=form.parentNode; sec.classList.add('hz-auth'); sec.setAttribute('data-hz-auth','');
      var isUp=/signup/.test(page);
      var aside=el('aside','hz-aside',
        '<div class="hz-orb a"></div><div class="hz-orb b"></div><div class="hz-orb c"></div>'+
        '<div class="hz-aside-top"><span class="hz-logo">Liban<b>Apps</b></span></div>'+
        '<div class="hz-aside-mid">'+
          '<h3>'+(isUp?'ابدأ خلال دقيقة':'أهلاً فيك من جديد')+'</h3>'+
          '<p>منيو المطاعم، محاسبة الصناعيين والتجّار، والمتجر الإلكتروني — بحساب واحد.</p>'+
          '<ul>'+
            '<li><i>'+ICON.check+'</i><span>تفعيل فوري بعد الدفع</span></li>'+
            '<li><i>'+ICON.check+'</i><span>الدولار والليرة بكل البرامج</span></li>'+
            '<li><i>'+ICON.check+'</i><span>بيشتغل على الموبايل والكمبيوتر</span></li>'+
            '<li><i>'+ICON.check+'</i><span>دعم محلي بالعربي</span></li>'+
          '</ul>'+
        '</div>'+
        '<div class="hz-chips">'+
          '<div class="hz-chip c1"><i class="o">'+ICON.bag+'</i><div><b>طلب جديد</b><small>طاولة 4 · 3 أصناف</small></div></div>'+
          '<div class="hz-chip c2"><i class="g">'+ICON.bill+'</i><div><b>فاتورة مدفوعة</b><small dir="ltr">#1024 · 250 $</small></div></div>'+
          '<div class="hz-chip c3"><i class="b">'+ICON.box+'</i><div><b>المخزون محدّث</b><small>الآن</small></div></div>'+
        '</div>'+
        '<div class="hz-aside-foot">مبني بلبنان · مدعوم محلياً</div>');
      sec.appendChild(aside);

      // ترتيب ظهور الحقول
      Array.prototype.forEach.call(form.querySelectorAll('.card > div > *, .card > .msg, .card > p'),function(x,i){
        x.style.setProperty('--hz-i',i); x.classList.add('hz-stag');
      });

      // زر إظهار/إخفاء كلمة المرور
      Array.prototype.forEach.call(form.querySelectorAll('input[type=password]'),function(inp){
        if(inp.parentNode.classList.contains('hz-pw')) return;
        var w=document.createElement('div'); w.className='hz-pw hz-stag';
        w.style.setProperty('--hz-i',inp.style.getPropertyValue('--hz-i')||0);
        inp.parentNode.insertBefore(w,inp); w.appendChild(inp); inp.classList.remove('hz-stag');
        var b=el('button','hz-eye',ICON.eye); b.type='button'; b.setAttribute('aria-label','إظهار كلمة المرور');
        b.addEventListener('click',function(){
          var show=inp.type==='password'; inp.type=show?'text':'password';
          b.innerHTML=show?ICON.eyeOff:ICON.eye; b.setAttribute('aria-label',show?'إخفاء كلمة المرور':'إظهار كلمة المرور');
          inp.focus();
        });
        w.appendChild(b);
      });

      // هزّة البطاقة عند الخطأ، وتوهّج عند النجاح
      var card=form.querySelector('.card'), msg=form.querySelector('.msg');
      if(card) card.addEventListener('animationend',function(ev){ if(ev.target===card && ev.animationName==='hzCardOpen') card.classList.add('hz-opened'); });
      if(card && msg && window.MutationObserver){
        new MutationObserver(function(){
          if(!on()) return;
          var txt=(msg.textContent||'').trim();
          if(msg.classList.contains('e') && txt){ card.classList.remove('hz-shake'); void card.offsetWidth; card.classList.add('hz-shake'); }
          card.classList.toggle('hz-ok', msg.classList.contains('s') && !!txt);
        }).observe(msg,{attributes:true,attributeFilter:['class'],childList:true,characterData:true,subtree:true});
      }
    }

    // ظهور تدريجي — بصفحات التسويق فقط
    if(!reduce() && ('IntersectionObserver' in window) && document.querySelector('header.hero')){
      var els=document.querySelectorAll('section .head, .pcard, .feat>div, .grid2>*, .band');
      var io=new IntersectionObserver(function(list){
        list.forEach(function(en){ if(en.isIntersecting){ en.target.classList.add('hz-in'); io.unobserve(en.target); } });
      },{rootMargin:'0px 0px -8% 0px',threshold:.08});
      Array.prototype.forEach.call(els,function(x){
        var i=Array.prototype.indexOf.call(x.parentNode.children,x);
        x.style.setProperty('--hz-d',Math.min(i,6)*0.08+'s');
        x.classList.add('hz-rv'); io.observe(x);
      });
      d.classList.add('hz-js');
      // أمان: إذا المراقب ما اشتغل لأي سبب، بيظهر كل شي بالشاشة بعد ٣ ثواني
      setTimeout(function(){
        Array.prototype.forEach.call(document.querySelectorAll('.hz-rv:not(.hz-in)'),function(x){
          if(x.getBoundingClientRect().top<window.innerHeight) x.classList.add('hz-in');
        });
      },3000);
    }
  }
  function teardown(){
    if(!d.classList.contains('hz-on')) return;
    d.classList.remove('hz-on','hz-js');
    Array.prototype.forEach.call(document.querySelectorAll('[data-hz]'),function(x){ x.parentNode && x.parentNode.removeChild(x); });
    Array.prototype.forEach.call(document.querySelectorAll('.hz-rv'),function(x){ x.classList.remove('hz-rv','hz-in'); });
    Array.prototype.forEach.call(document.querySelectorAll('[data-hz-auth]'),function(x){ x.classList.remove('hz-auth'); });
    var n=document.querySelector('nav'); if(n) n.classList.remove('hz-open');
  }

  function ready(){
    isReady=true;
    meta(d.getAttribute('data-theme')||'default');
    try{ once(); }catch(e){ console.error('Horizon theme:',e); }
    try{ if(on()) enhance(); }catch(e){ console.error('Horizon theme:',e); }
  }
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',ready); else ready();
})();
/* ===== HORIZON JS END ===== */
