/* ============================================================
   LibanApps — محرّك الترجمة المشترك
   بيترجم كل نص عربي بالصفحة حسب القاموس، حتى النصوص اللي
   بتنرسم بعدين (مراقب DOM)، مع:
   · الأرقام:   "باقي 12 يوم"  ← قاموس: "باقي {n} يوم"
   · المقاطع:   "توصيل · 12 $ · نقداً" ← كل مقطع لحالو
   · الرموز:    "✅ تم التوصيل" ← بيترجم "تم التوصيل"
   · الخصائص:   placeholder / title / aria-label / alt / value
   · الرسائل:   alert / confirm / prompt
   · عنوان الصفحة
   ============================================================ */
(function(){
"use strict";
var AR=/[\u0600-\u06FF]/;
var NUM=/[0-9\u0660-\u0669]+(?:[.,][0-9\u0660-\u0669]+)*/g;
var SKIP={SCRIPT:1,STYLE:1,TEXTAREA:1,CODE:1,NOSCRIPT:1};
var ATTRS=['placeholder','title','aria-label','alt'];

function norm(s){ return String(s).replace(/\s+/g,' ').trim(); }
function latin(s){ return s.replace(/[\u0660-\u0669]/g,function(c){return String(c.charCodeAt(0)-0x660)}); }

window.LAEngine=function(opts){
  opts=opts||{};
  var IDX={};                       // lang -> { normalizedArabic: text }
  var cur='ar', ORIG=new WeakMap(), WROTE=new WeakMap(), obs=null, titleAr=null;

  function add(lang,dict){
    IDX[lang]=IDX[lang]||{};
    for(var k in dict){ if(Object.prototype.hasOwnProperty.call(dict,k) && dict[k]!=null && dict[k]!=='')
      IDX[lang][norm(k)]=dict[k]; }
  }
  var d=opts.dicts||{}; for(var l in d) add(l,d[l]);

  function get(k,l){
    var t=IDX[l]&&IDX[l][k];
    if(t==null && l!=='en' && opts.fallback!==false) t=IDX.en&&IDX.en[k];
    return t==null?null:t;
  }
  function fill(hit,nums,strs){
    var i=0,j=0;
    return hit.replace(/\{n\}/g,function(){ return nums[i++]||''; })
              .replace(/\{s\}/g,function(){ return strs[j++]||''; });
  }
  function tNums(k,l){
    var hit=get(k,l); if(hit!=null) return hit;
    // 1) الأرقام بس
    var nums=[]; var tpl=k.replace(NUM,function(m){ nums.push(latin(m)); return '{n}'; });
    if(nums.length){ hit=get(tpl,l); if(hit!=null) return fill(hit,nums,[]); }
    // 2) الأرقام + الكلمات اللاتينية/الروابط
    var n2=[], s2=[];
    var tpl2=k.replace(/([A-Za-z][A-Za-z0-9._\-\/@:?=&%+#]*)|([0-9\u0660-\u0669]+(?:[.,][0-9\u0660-\u0669]+)*)/g,
      function(m,a){ if(a){ s2.push(m); return '{s}'; } n2.push(latin(m)); return '{n}'; });
    if(s2.length){ hit=get(tpl2,l); if(hit!=null) return fill(hit,n2,s2); }
    return null;
  }
  function tCore(k,l){
    var hit=tNums(k,l); if(hit!=null) return hit;
    // رموز وعلامات بأول وآخر النص (✓ 🏍️ … : ؟ «»)
    var m=k.match(/^([^\u0600-\u06FFA-Za-z0-9]*)([\s\S]*?)([^\u0600-\u06FFA-Za-z0-9]*)$/);
    if(m && (m[1]||m[3]) && m[2]){
      hit=tNums(m[2],l);
      if(hit!=null) return m[1]+hit+m[3].replace(/؟/g,'?').replace(/،/g,',');
    }
    return null;
  }
  function tr(text,l){
    if(!text||!AR.test(text)) return null;
    var k=norm(text), hit=tCore(k,l);
    if(hit!=null) return hit;
    // نص متعدد الأسطر (رسائل prompt/alert): كل سطر لحالو مع الحفاظ على الأسطر
    if(/\n/.test(text)){
      var ls=String(text).split('\n');
      if(ls.filter(function(x){return AR.test(x)}).length>1 || ls.filter(function(x){return x.trim()}).length>1){
        var anyL=false;
        var oL=ls.map(function(x){
          if(!AR.test(x)) return x;
          var h=tr(x,l); if(h!=null){ anyL=true; return x.replace(x.trim(),h); }
          return x;
        });
        if(anyL) return oL.join('\n');
      }
    }
    // مقاطع: · | — – : ، أسطر
    var parts=k.split(/(\s[·|—–-]\s|\s*\n\s*|،\s*|:\s+|\s\/\s)/);
    if(parts.length>1){
      var any=false;
      var out=parts.map(function(p,i){
        if(i%2===1) return p.replace(/،/g,',');
        var h=p&&AR.test(p)?(tCore(p.trim(),l)):null;
        if(h!=null){ any=true; return h; }
        return p;
      });
      if(any) return out.join('');
    }
    // مزيج عربي + لاتيني: منترجم القطع العربية لحالها
    var ch=k.split(/((?:[A-Za-z0-9@#$%&*+=\/\\._:\-]+\s*)+)/);
    if(ch.length>1){
      var any2=false;
      var o2=ch.map(function(p,i){
        if(i%2===1||!AR.test(p)) return p;
        var h=tCore(p.trim(),l); if(h!=null){ any2=true; return p.replace(p.trim(),h); }
        return p;
      });
      if(any2) return o2.join('');
    }
    return null;
  }
  function trKeepSpace(orig,l){
    var t=tr(orig,l); if(t==null) return orig;
    var lead=orig.match(/^\s*/)[0], tail=orig.match(/\s*$/)[0];
    return lead+t+tail;
  }

  /* ---------- النصوص ---------- */
  function skipNode(n){
    for(var p=n.parentNode;p&&p.nodeType===1;p=p.parentNode){
      if(SKIP[p.nodeName]) return true;
      if(p.hasAttribute&&p.hasAttribute('data-noi18n')) return true;
    }
    return false;
  }
  function doText(n){
    if(!ORIG.has(n)){ if(!AR.test(n.nodeValue||'')) return; ORIG.set(n,n.nodeValue); }
    var ar=ORIG.get(n), want=cur==='ar'?ar:trKeepSpace(ar,cur);
    if(n.nodeValue!==want){ WROTE.set(n,want); n.nodeValue=want; }
  }
  function doAttrs(el){
    ATTRS.forEach(function(a){
      if(!el.hasAttribute(a)) return;
      var key='i18n'+a.replace(/-/g,''), v=el.getAttribute(a);
      if(el.dataset[key]===undefined){ if(!AR.test(v)) return; el.dataset[key]=v; }
      else if(v!==el.dataset[key] && v!==el.dataset[key+'W']){ el.dataset[key]=v; } // التطبيق غيّرها
      var ar=el.dataset[key], want=cur==='ar'?ar:(tr(ar,cur)||ar);
      if(v!==want){ el.dataset[key+'W']=want; el.setAttribute(a,want); }
    });
    if(el.nodeName==='INPUT' && /^(button|submit|reset)$/i.test(el.type)){
      if(el.dataset.i18nval===undefined){ if(!AR.test(el.value)) return; el.dataset.i18nval=el.value; }
      var wv=cur==='ar'?el.dataset.i18nval:(tr(el.dataset.i18nval,cur)||el.dataset.i18nval);
      if(el.value!==wv) el.value=wv;
    }
  }
  function walk(root){
    if(!root) return;
    if(root.nodeType===3){ if(!skipNode(root)) doText(root); return; }
    if(root.nodeType!==1 || SKIP[root.nodeName]) return;
    if(root.closest && root.closest('[data-noi18n]')) return;
    doAttrs(root);
    var w=document.createTreeWalker(root,NodeFilter.SHOW_TEXT|NodeFilter.SHOW_ELEMENT,{
      acceptNode:function(n){
        if(n.nodeType===1) return (SKIP[n.nodeName]||n.hasAttribute('data-noi18n'))?NodeFilter.FILTER_REJECT:NodeFilter.FILTER_SKIP;
        return (n.nodeValue&&n.nodeValue.trim())?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_REJECT;
      }});
    var n; while((n=w.nextNode())) doText(n);
    Array.prototype.forEach.call(root.querySelectorAll('[placeholder],[title],[aria-label],[alt],input[type=button],input[type=submit]'),doAttrs);
  }
  function doTitle(){
    if(titleAr===null||(AR.test(document.title)&&document.title!==titleAr&&document.title!==WROTE.get(document))) titleAr=document.title;
    var want=cur==='ar'?titleAr:(tr(titleAr,cur)||titleAr);
    if(document.title!==want){ WROTE.set(document,want); document.title=want; }
  }

  /* ---------- المراقب ---------- */
  function observe(){
    if(obs||!window.MutationObserver) return;
    obs=new MutationObserver(function(recs){
      recs.forEach(function(r){
        if(r.type==='characterData'){
          var n=r.target;
          if(WROTE.get(n)===n.nodeValue) return;
          if(skipNode(n)) return;
          if(AR.test(n.nodeValue||'')) ORIG.set(n,n.nodeValue); else ORIG.delete(n);
          if(ORIG.has(n)) doText(n);
        } else if(r.type==='childList'){
          for(var i=0;i<r.addedNodes.length;i++){ var a=r.addedNodes[i];
            if(a.nodeType===3){ if(!skipNode(a)) doText(a); } else walk(a); }
          if(r.target&&r.target.nodeName==='TITLE') doTitle();
        } else if(r.type==='attributes'){ doAttrs(r.target); }
      });
    });
    obs.observe(document.documentElement,{childList:true,subtree:true,characterData:true,
      attributes:true,attributeFilter:ATTRS});
  }

  /* ---------- الرسائل ---------- */
  ['alert','confirm','prompt'].forEach(function(fn){
    var orig=window[fn]; if(!orig||orig.__la) return;
    var wrapped=function(msg,def){
      var m=(cur!=='ar'&&typeof msg==='string')?(tr(msg,cur)||msg):msg;
      return fn==='prompt'?orig.call(window,m,def):orig.call(window,m);
    };
    wrapped.__la=1; window[fn]=wrapped;
  });

  var api={
    apply:function(l){
      cur=l||'ar';
      document.documentElement.lang=cur;
      document.documentElement.dir=cur==='ar'?'rtl':'ltr';
      walk(document.body); doTitle();
      if(cur!=='ar') observe();
      else if(obs){ obs.disconnect(); obs=null; }   // بالعربي ما في شي نترجمو
    },
    relang:function(){ if(cur!=='ar') walk(document.body); },
    t:function(ar,l){ l=l||cur; if(l==='ar') return ar; return tr(ar,l)||ar; },
    add:add,
    learn:function(ar,map){ if(!ar) return; for(var l in map){ if(map[l]){ var o={}; o[ar]=map[l]; add(l,o); } } },
    lang:function(){ return cur; }
  };
  return api;
};
})();
