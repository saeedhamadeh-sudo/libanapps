/* ============================================================
   LibanApps — اختيار رمز الدولة لرقم واتساب
   · لبنان هو الافتراضي (وأول القائمة)
   · كل الدول مسموحة ما عدا إسرائيل (غير موجودة بالقائمة، والخادم يرفض +972)
   · أسماء الدول بلغة الصفحة (عربي / English / Français) عبر Intl.DisplayNames
   الاستعمال:
     var cc = LAPhoneCC.attach(inputEl);   // يحطّ قائمة الدول قبل الحقل
     cc.full()  ← الرقم كاملًا بصيغة +<رمز الدولة><الرقم>
   ============================================================ */
(function(){
"use strict";
var DATA='LB:961,AF:93,AL:355,DZ:213,AD:376,AO:244,AG:1268,AR:54,AM:374,AU:61,AT:43,AZ:994,BS:1242,BH:973,BD:880,BB:1246,BY:375,BE:32,BZ:501,BJ:229,BT:975,BO:591,BA:387,BW:267,BR:55,BN:673,BG:359,BF:226,BI:257,KH:855,CM:237,CA:1,CV:238,CF:236,TD:235,CL:56,CN:86,CO:57,KM:269,CG:242,CD:243,CR:506,CI:225,HR:385,CU:53,CY:357,CZ:420,DK:45,DJ:253,DM:1767,DO:1809,EC:593,EG:20,SV:503,GQ:240,ER:291,EE:372,SZ:268,ET:251,FJ:679,FI:358,FR:33,GA:241,GM:220,GE:995,DE:49,GH:233,GR:30,GD:1473,GT:502,GN:224,GW:245,GY:592,HT:509,HN:504,HK:852,HU:36,IS:354,IN:91,ID:62,IR:98,IQ:964,IE:353,IT:39,JM:1876,JP:81,JO:962,KZ:7,KE:254,KI:686,KW:965,KG:996,LA:856,LV:371,LS:266,LR:231,LY:218,LI:423,LT:370,LU:352,MO:853,MG:261,MW:265,MY:60,MV:960,ML:223,MT:356,MH:692,MR:222,MU:230,MX:52,FM:691,MD:373,MC:377,MN:976,ME:382,MA:212,MZ:258,MM:95,NA:264,NR:674,NP:977,NL:31,NZ:64,NI:505,NE:227,NG:234,KP:850,MK:389,NO:47,OM:968,PK:92,PW:680,PS:970,PA:507,PG:675,PY:595,PE:51,PH:63,PL:48,PT:351,PR:1787,QA:974,RO:40,RU:7,RW:250,KN:1869,LC:1758,VC:1784,WS:685,SM:378,ST:239,SA:966,SN:221,RS:381,SC:248,SL:232,SG:65,SK:421,SI:386,SB:677,SO:252,ZA:27,KR:82,SS:211,ES:34,LK:94,SD:249,SR:597,SE:46,CH:41,SY:963,TW:886,TJ:992,TZ:255,TH:66,TL:670,TG:228,TO:676,TT:1868,TN:216,TR:90,TM:993,TV:688,UG:256,UA:380,AE:971,GB:44,US:1,UY:598,UZ:998,VU:678,VA:379,VE:58,VN:84,YE:967,ZM:260,ZW:263';
var LIST=DATA.split(',').map(function(x){ var p=x.split(':'); return {iso:p[0],cc:p[1]}; });
var CODES=LIST.map(function(c){ return c.cc; }).sort(function(a,b){ return b.length-a.length; });

function flag(iso){ return iso.replace(/./g,function(ch){ return String.fromCodePoint(0x1F1E6+ch.charCodeAt(0)-65); }); }
function lang(){ var l=(document.documentElement.lang||'ar').slice(0,2); return (l==='en'||l==='fr')?l:'ar'; }
function names(l){
  try{ var dn=new Intl.DisplayNames([l],{type:'region'}); return function(iso){ try{ return dn.of(iso)||iso; }catch(e){ return iso; } }; }
  catch(e){ return function(iso){ return iso; }; }
}
/* رقم مكتوب كاملًا (+44… أو 0044…) — منعرف الدولة من بدايته */
function splitFull(digits){
  for(var i=0;i<CODES.length;i++) if(digits.indexOf(CODES[i])===0) return {cc:CODES[i], rest:digits.slice(CODES[i].length)};
  return null;
}

function attach(input, opts){
  opts=opts||{};
  if(!input || input.__laCC) return input && input.__laCC;
  var sel=document.createElement('select');
  sel.className='la-cc';
  sel.setAttribute('data-noi18n','');
  sel.setAttribute('aria-label','Country code');
  sel.style.cssText='direction:ltr;max-width:132px;min-width:96px;flex:0 0 auto;font-size:15px;cursor:pointer;'+(opts.style||'');

  function build(){
    var keep=sel.value||'LB', nm=names(lang());
    var rows=LIST.slice(1).map(function(c){ return {c:c,n:nm(c.iso)}; });
    rows.sort(function(a,b){ return a.n.localeCompare(b.n, lang()); });
    rows.unshift({c:LIST[0], n:nm('LB')});
    sel.innerHTML=rows.map(function(r){
      return '<option value="'+r.c.iso+'">'+flag(r.c.iso)+' +'+r.c.cc+' '+r.n.replace(/[<&]/g,'')+'</option>';
    }).join('');
    sel.value=keep;
  }
  build();
  // تتغيّر أسماء الدول مع لغة الصفحة
  if(window.MutationObserver) new MutationObserver(build).observe(document.documentElement,{attributes:true,attributeFilter:['lang']});

  var old=opts.replace || (input.parentNode && input.parentNode.querySelector('.cc'));
  if(old && old!==input){ old.parentNode.replaceChild(sel, old); if(old.className) sel.className+=' '+old.className; }
  else input.parentNode.insertBefore(sel, input);

  function ccOf(){ var iso=sel.value; for(var i=0;i<LIST.length;i++) if(LIST[i].iso===iso) return LIST[i].cc; return '961'; }
  function setPh(){ input.placeholder = sel.value==='LB' ? (opts.lbPlaceholder||input.getAttribute('data-lb-ph')||input.placeholder) : '123 456 789'; }
  if(!input.getAttribute('data-lb-ph')) input.setAttribute('data-lb-ph', input.placeholder||'');
  sel.addEventListener('change',function(){ setPh(); try{ input.focus(); }catch(e){} });

  var api={
    select:sel,
    cc:ccOf,
    /* الرقم الكامل: +<رمز><الرقم> — إذا كتب الزبون +… أو 00… منحترم يلي كتبو */
    full:function(){
      var raw=String(input.value||'').trim(), d=raw.replace(/\D/g,'');
      if(!d) return '';
      if(/^\s*\+/.test(raw)) return '+'+d;
      if(d.indexOf('00')===0) return '+'+d.slice(2);
      var cc=ccOf();
      if(d.indexOf(cc)===0 && d.length>cc.length+6) return '+'+d;   // كتب رمز الدولة بلا +
      return '+'+cc+d.replace(/^0+/,'');
    },
    /* تعبئة رقم محفوظ: منختار الدولة ومنحطّ الباقي بالحقل */
    set:function(v){
      var raw=String(v||'').trim(), d=raw.replace(/\D/g,'');
      if(!d){ input.value=''; return; }
      var intl=/^\s*\+/.test(raw)||d.indexOf('00')===0||(d.indexOf('961')===0&&d.length>=10);
      if(d.indexOf('00')===0) d=d.slice(2);
      var s=intl?splitFull(d):null;
      if(s){ for(var i=0;i<LIST.length;i++) if(LIST[i].cc===s.cc){ sel.value=(s.cc==='1'?'US':s.cc==='7'?'RU':LIST[i].iso); break; } input.value=s.rest; }
      else input.value=raw;
      setPh();
    }
  };
  input.__laCC=api;
  return api;
}
window.LAPhoneCC={ attach:attach, list:LIST };
})();
