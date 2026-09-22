/* ============================================================
   LibanApps — تبويب «التوصيل» بلوحة المطعم
   موظفين + أجهزة تتبع + خريطة مباشرة لكل الموتوسيكلات
   بيعتمد على window.LA_ADMIN = { sb, R, esc } من admin.html
   ============================================================ */
(function(){
"use strict";
var A=null, F=null, MAP=null, MK={drv:{},ord:{}}, timer=null, fitted=false, openFlag=false;
var $=function(s){return document.querySelector(s)};
function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){
  return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})}
function ago(t){ if(!t) return '—'; var m=Math.max(0,Math.round((Date.now()-new Date(t))/60000));
  return m<1?'هلق':m<60?'من '+m+' د':m<1440?'من '+Math.floor(m/60)+' س':'من '+Math.floor(m/1440)+' يوم'; }
function fresh(p,ms){ return p&&p.pos_at&&(Date.now()-new Date(p.pos_at))<(ms||180000); }
function waNum(p){ var d=String(p||'').replace(/\D/g,''); if(d.indexOf('00')===0) d=d.slice(2);
  if(d.indexOf('961')===0) return d; if(d.charAt(0)==='0') d=d.slice(1); return d.length<=8?'961'+d:d; }
function toast(t,ok){ var e=document.createElement('div');
  e.style.cssText='position:fixed;left:50%;bottom:24px;transform:translateX(-50%);z-index:999;padding:10px 16px;'+
    'border-radius:12px;font-weight:700;font-size:14px;color:#fff;background:'+(ok===false?'#B91C1C':'#111');
  e.textContent=t; document.body.appendChild(e); setTimeout(function(){e.remove()},2600); }
function copy(t){ (navigator.clipboard?navigator.clipboard.writeText(t):Promise.reject())
  .then(function(){toast('انتسخ ✓')},function(){prompt('انسخ:',t)}); }
var ST={waiting:['بانتظار موتوسيكل','w'],claimed:['مع الموظف','b'],on_the_way:['بالطريق','b'],
        delivered:['وصل ✓','p'],cancelled:['ملغى','x']};
var KIND={traccar_app:'تطبيق Traccar',gps_tracker:'جهاز GPS',other:'جهاز آخر',phone:'GPS الهاتف'};

/* ---------- Leaflet عند الحاجة ---------- */
function needLeaflet(){
  if(window.L) return Promise.resolve();
  return new Promise(function(res,rej){
    var l=document.createElement('link'); l.rel='stylesheet'; l.href='https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
    document.head.appendChild(l);
    var s=document.createElement('script'); s.src='https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
    s.onload=res; s.onerror=rej; document.head.appendChild(s);
  });
}

/* ---------- الواجهة ---------- */
function shell(){
  var root=$('#dlvRoot'); if(root.dataset.ready) return; root.dataset.ready=1;
  var st=document.createElement('style');
  st.textContent='#dlvMap{height:420px;border-radius:14px;border:1px solid var(--line);background:var(--bg-2)}'+
    '.dlv-moto{font-size:26px;line-height:1;filter:drop-shadow(0 2px 3px rgba(0,0,0,.5))}'+
    '.dlv-lbl{background:#111;color:#fff;font:700 11px Cairo,sans-serif;padding:1px 6px;border-radius:6px;white-space:nowrap;'+
      'position:absolute;top:28px;left:50%;transform:translateX(-50%)}'+
    '.dlv-off{opacity:.45;filter:grayscale(1)}'+
    '.dlv-pin{font-size:24px;line-height:1}'+
    '.chip.b{background:rgba(96,165,250,.16);color:#93C5FD}.chip.x{background:rgba(255,255,255,.08);color:var(--muted)}'+
    '.dlv-acts{display:flex;gap:6px;flex-wrap:wrap;align-items:center}'+
    '.dlv-acts select{width:auto;padding:6px 8px;font-size:13px}'+
    '.dlv-kv{direction:ltr;text-align:left;font-size:12.5px;background:var(--bg-2);border:1px solid var(--line);'+
      'border-radius:9px;padding:8px 10px;word-break:break-all;margin-top:6px}'+
    '.dlv-stats{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-bottom:10px}'+
    '.dlv-stats div{background:var(--bg-2);border:1px solid var(--line);border-radius:12px;padding:10px;text-align:center}'+
    '.dlv-stats b{display:block;font-size:22px;color:var(--accent)}.dlv-stats span{font-size:12px;color:var(--muted)}'+
    '@media(max-width:640px){.dlv-stats{grid-template-columns:repeat(2,1fr)}#dlvMap{height:320px}}';
  document.head.appendChild(st);

  root.innerHTML=
  '<div class="panel">'+
    '<h3>الخريطة المباشرة</h3>'+
    '<div class="dlv-stats" id="dlvStats"></div>'+
    '<div id="dlvMap"></div>'+
    '<div class="muted" style="font-size:12px;margin-top:6px">بتتحدث كل 5 ثواني · 🏍️ ملوّن = شغّال · باهت = موقعو قديم</div>'+
  '</div>'+
  '<div class="panel"><h3>طلبات التوصيل المفتوحة</h3><div id="dlvOrders"></div></div>'+
  '<div class="panel">'+
    '<h3>موظفين التوصيل</h3>'+
    '<div class="g3">'+
      '<div><label>الاسم</label><input type="text" id="dlvDName"></div>'+
      '<div><label>الهاتف</label><input type="tel" id="dlvDPhone" placeholder="03xxxxxx"></div>'+
      '<div style="display:flex;align-items:flex-end"><button class="btn" id="dlvAddDrv" style="width:100%">إضافة موظف</button></div>'+
    '</div>'+
    '<div class="muted" style="font-size:12.5px;margin-top:6px">كل موظف إلو رابط خاص — بيفتحو على تلفونو وبيستلم الطلبات منو. ما بيحتاج إيميل ولا كلمة سر.</div>'+
    '<div id="dlvDrivers" style="margin-top:10px"></div>'+
  '</div>'+
  '<div class="panel">'+
    '<h3>أجهزة التتبع</h3>'+
    '<div class="g3">'+
      '<div><label>النوع</label><select id="dlvKKind"><option value="gps_tracker">جهاز GPS للموتوسيكل</option>'+
        '<option value="traccar_app">تطبيق Traccar على هاتف</option><option value="other">جهاز آخر (HTTP)</option></select></div>'+
      '<div><label>اسم / رقم الموتوسيكل</label><input type="text" id="dlvKLabel" placeholder="موتو 1"></div>'+
      '<div><label>رقم الجهاز (IMEI / ID)</label><input type="text" id="dlvKId" dir="ltr" placeholder="اتركه فاضي لتطبيق Traccar"></div>'+
    '</div>'+
    '<div class="acts"><button class="btn" id="dlvAddDev">إضافة جهاز</button></div>'+
    '<div id="dlvDevices" style="margin-top:10px"></div>'+
  '</div>'+
  '<div class="panel">'+
    '<h3>الإعدادات والربط</h3>'+
    '<label>إرسال الطلبات للموظفين</label>'+
    '<select id="dlvMode"><option value="auto">تلقائي — كل طلب توصيل بيوصل فوراً (Whish: بعد الدفع)</option>'+
      '<option value="manual">يدوي — أنا بكبس «أرسل للتوصيل» على كل طلب</option></select>'+
    '<div class="msg" id="dlvSetMsg"></div>'+
    '<label style="margin-top:14px">رابط استقبال المواقع (لتطبيق Traccar وأجهزة الـGPS)</label>'+
    '<div class="dlv-kv" id="dlvSrv"></div>'+
    '<label style="margin-top:10px">رابط التحويل من سيرفر Traccar (forward.url) — لأجهزة GPS القديمة</label>'+
    '<div class="dlv-kv" id="dlvFwd">—</div>'+
    '<div class="acts"><button class="btn alt sm" id="dlvCopyFwd">نسخ</button><button class="btn dg sm" id="dlvNewKey">تغيير المفتاح</button></div>'+
    '<div class="muted" style="font-size:12.5px;line-height:1.8;margin-top:8px">'+
      '• <b>Apple AirTag:</b> Apple ما بتسمح لأي برنامج يقرأ موقعو (بس تطبيق Find My) — فما فينا نستعملو هون.<br>'+
      '• <b>أسهل حل:</b> تطبيق Traccar Client المجاني على تلفون الموظف — الموظف بيجهّزو من صفحتو بكبسة.<br>'+
      '• <b>جهاز GPS على الموتوسيكل:</b> إذا الجهاز بيدعم إرسال HTTP (OsmAnd) بتحط الرابط فوق مباشرة. '+
        'أغلب الأجهزة الصينية (GT06 / Sinotrack / Concox) بتحكي بس مع سيرفر Traccar، وهو بيحوّل لعنّا عبر رابط التحويل.'+
    '</div>'+
  '</div>';

  $('#dlvAddDrv').onclick=addDriver;
  $('#dlvAddDev').onclick=addDevice;
  $('#dlvMode').onchange=function(){ saveSettings(this.value,false); };
  $('#dlvNewKey').onclick=function(){ if(confirm('تغيير المفتاح بيوقف أي سيرفر Traccar مربوط لحد ما تحط الرابط الجديد. متأكد؟')) saveSettings(null,true); };
  $('#dlvCopyFwd').onclick=function(){ copy($('#dlvFwd').textContent); };
  $('#dlvSrv').textContent=location.origin+'/api/track/osmand';
  root.addEventListener('click',onClick);
  root.addEventListener('change',onChange);
}

/* ---------- البيانات ---------- */
async function load(){
  var r=await A.sb.rpc('admin_fleet',{rid:A.R.id});
  if(r.error){ console.error(r.error); return; }
  F=r.data;
  if(!F.settings){ var s=await A.sb.rpc('admin_delivery_settings',{rid:A.R.id,p_mode:null,p_new_key:false});
    if(!s.error) F.settings=s.data; }
  var dv=await A.sb.from('tracker_devices').select('*').eq('restaurant_id',A.R.id).order('created_at');
  F.devices=dv.data||[];
  paint();
}
function drvById(id){ return (F.drivers||[]).filter(function(d){return d.id===id})[0]; }

function paint(){
  var D=F.drivers||[], O=F.orders||[];
  var live=D.filter(function(d){return d.on_duty && fresh(d.pos)}).length;
  var cnt=function(s){return O.filter(function(o){return o.dispatch===s}).length};
  $('#dlvStats').innerHTML=
    '<div><b>'+live+'</b><span>موتوسيكل شغّال</span></div>'+
    '<div><b>'+cnt('waiting')+'</b><span>بانتظار موظف</span></div>'+
    '<div><b>'+(cnt('claimed')+cnt('on_the_way'))+'</b><span>عالطريق</span></div>'+
    '<div><b>'+D.reduce(function(a,d){return a+Number(d.done_today||0)},0)+'</b><span>وصل اليوم</span></div>';

  // الطلبات
  var opts=function(sel){ return '<option value="">— اختار موظف —</option>'+D.filter(function(d){return d.is_active})
    .map(function(d){return '<option value="'+d.id+'"'+(d.id===sel?' selected':'')+'>'+esc(d.name)+(d.on_duty?' 🟢':'')+'</option>'}).join(''); };
  $('#dlvOrders').innerHTML=O.length?O.map(function(o){
    var s=ST[o.dispatch]||['لسا ما انبعت','x'], d=drvById(o.driver_id);
    var trk=location.origin+'/t/'+encodeURIComponent(o.token);
    var open=['waiting','claimed','on_the_way'].indexOf(o.dispatch)>=0;
    return '<div class="row"><div class="t"><b>'+esc(o.order_no)+' · '+esc(o.customer_name)+'</b>'+
      '<span>'+esc(o.address_text||'')+' · '+o.total_usd+' $ · '+ago(o.created_at)+
      (d?' · 🏍️ '+esc(d.name):'')+'</span></div>'+
      '<div class="dlv-acts"><span class="chip '+s[1]+'">'+s[0]+'</span>'+
      (!o.dispatch||o.dispatch==='cancelled'?'<button class="btn sm" data-oa="send" data-id="'+o.id+'">أرسل للتوصيل</button>':'')+
      (open?'<select data-assign="'+o.id+'">'+opts(o.driver_id)+'</select>':'')+
      (o.dispatch==='claimed'||o.dispatch==='on_the_way'?'<button class="btn alt sm" data-oa="unassign" data-id="'+o.id+'">سحب</button>'+
        '<button class="btn alt sm" data-oa="delivered" data-id="'+o.id+'">وصل</button>':'')+
      (o.dispatch==='waiting'?'<button class="btn dg sm" data-oa="cancel" data-id="'+o.id+'">إلغاء</button>':'')+
      '<button class="btn alt sm" data-copy="'+esc(trk)+'">رابط التتبع</button>'+
      (o.lat!=null?'<button class="btn alt sm" data-focus="'+o.lat+','+o.lng+'">📍</button>':'')+
      '</div></div>';
  }).join(''):'<p class="muted">ما في طلبات توصيل مفتوحة</p>';

  // الموظفين
  $('#dlvDrivers').innerHTML=D.length?D.map(function(d){
    var link=location.origin+'/d/'+d.token, p=d.pos;
    var src=p?(KIND[p.src]||p.src)+' · '+ago(p.pos_at):'ما في موقع بعد';
    var dot=!d.is_active?'⚫':d.on_duty&&fresh(p)?'🟢':d.on_duty?'🟡':'⚪';
    var msg='مرحبا '+d.name+'، هيدا رابط صفحة التوصيل تبعك عند '+A.R.name_ar+
      '. افتحو على تلفونك وكبس «بدء الدوام»:\n'+link;
    return '<div class="row"><div class="t"><b>'+dot+' '+esc(d.name)+(d.phone?' · <span style="direction:ltr;display:inline">'+esc(d.phone)+'</span>':'')+'</b>'+
      '<span>'+(d.on_duty?'بالدوام':'خارج الدوام')+' · '+src+
        (d.device?' · '+esc(KIND[d.device.kind])+': '+esc(d.device.label||d.device.identifier)+(d.device.battery!=null?' 🔋'+Math.round(d.device.battery)+'%':''):'')+
        ' · معو '+d.active+' · اليوم '+d.done_today+'</span></div>'+
      '<div class="dlv-acts">'+
        (d.phone?'<a class="btn sm" target="_blank" rel="noopener" style="text-decoration:none" href="https://wa.me/'+waNum(d.phone)+'?text='+encodeURIComponent(msg)+'">ابعت الرابط</a>':'')+
        '<button class="btn alt sm" data-copy="'+esc(link)+'">نسخ الرابط</button>'+
        (p&&p.lat!=null?'<button class="btn alt sm" data-focus="'+p.lat+','+p.lng+'">📍</button>':'')+
        '<button class="btn alt sm" data-da="toggle" data-id="'+d.id+'" data-on="'+d.is_active+'">'+(d.is_active?'إيقاف':'تفعيل')+'</button>'+
        '<button class="btn alt sm" data-da="token" data-id="'+d.id+'">رابط جديد</button>'+
        '<button class="btn dg sm" data-da="del" data-id="'+d.id+'">حذف</button>'+
      '</div></div>';
  }).join(''):'<p class="muted">ضيف أول موظف توصيل</p>';

  // الأجهزة
  var dopt=function(sel){ return '<option value="">— مش مربوط —</option>'+D.map(function(d){
    return '<option value="'+d.id+'"'+(d.id===sel?' selected':'')+'>'+esc(d.name)+'</option>'}).join(''); };
  $('#dlvDevices').innerHTML=F.devices.length?F.devices.map(function(t){
    return '<div class="row"><div class="t"><b>'+esc(t.label||'—')+' <span class="chip x">'+esc(KIND[t.kind])+'</span></b>'+
      '<span style="direction:ltr;display:inline-block">ID: '+esc(t.identifier)+'</span>'+
      '<span> · '+(t.pos_at?'آخر موقع '+ago(t.pos_at):'ما وصل منو موقع بعد')+(t.battery!=null?' · 🔋'+Math.round(t.battery)+'%':'')+'</span></div>'+
      '<div class="dlv-acts"><select data-devdrv="'+t.id+'">'+dopt(t.driver_id)+'</select>'+
      '<button class="btn alt sm" data-copy="'+esc(t.identifier)+'">نسخ ID</button>'+
      (t.kind!=='traccar_app'?'<button class="btn alt sm" data-copy="'+esc(location.origin+'/api/track/osmand?id='+t.identifier+'&key='+t.secret)+'" title="للأجهزة اللي بتبعت HTTP مباشرة">رابط الجهاز</button>':'')+
      '<button class="btn dg sm" data-ka="del" data-id="'+t.id+'">حذف</button></div></div>';
  }).join(''):'<p class="muted">ما في أجهزة بعد — الموظفين بيقدروا يستعملوا GPS هاتفهم بدون أي جهاز</p>';

  // الإعدادات
  if(F.settings){
    $('#dlvMode').value=F.settings.dispatch_mode;
    $('#dlvFwd').textContent=location.origin+'/api/track/osmand?id={uniqueId}&lat={latitude}&lon={longitude}'+
      '&speed={speed}&bearing={course}&timestamp={fixTime}&key='+F.settings.track_key;
  }
  paintMap();
}

/* ---------- الخريطة ---------- */
function paintMap(){
  if(!window.L||!$('#dlvMap')) return;
  var L=window.L;
  if(!MAP){
    MAP=L.map('dlvMap').setView([33.89,35.5],11);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'© OpenStreetMap'}).addTo(MAP);
  }
  var pts=[], keep={drv:{},ord:{}};
  (F.drivers||[]).forEach(function(d){
    var p=d.pos; if(!p||p.lat==null||!d.is_active) return;
    var old=!fresh(p,600000);
    keep.drv[d.id]=1; pts.push([p.lat,p.lng]);
    var html='<div style="position:relative"><div class="dlv-moto'+(old?' dlv-off':'')+'">🏍️</div><div class="dlv-lbl">'+esc(d.name)+(d.active?' · '+d.active:'')+'</div></div>';
    var ic=L.divIcon({html:html,className:'',iconSize:[30,30],iconAnchor:[15,15]});
    var pop='<b>'+esc(d.name)+'</b><br>'+(KIND[p.src]||p.src)+' · '+ago(p.pos_at)+
      (p.speed_kmh!=null?'<br>'+Math.round(p.speed_kmh)+' كم/س':'')+'<br>معو '+d.active+' طلب';
    if(MK.drv[d.id]){ MK.drv[d.id].setLatLng([p.lat,p.lng]).setIcon(ic).setPopupContent(pop); }
    else MK.drv[d.id]=L.marker([p.lat,p.lng],{icon:ic,zIndexOffset:1000}).bindPopup(pop).addTo(MAP);
  });
  (F.orders||[]).forEach(function(o){
    if(o.lat==null||['waiting','claimed','on_the_way'].indexOf(o.dispatch)<0) return;
    keep.ord[o.id]=1; pts.push([o.lat,o.lng]);
    var pop='<b>'+esc(o.order_no)+'</b> · '+esc(o.customer_name)+'<br>'+esc((ST[o.dispatch]||[''])[0]);
    if(!MK.ord[o.id]) MK.ord[o.id]=L.marker([o.lat,o.lng],{icon:L.divIcon({html:'<div class="dlv-pin">📍</div>',className:'',iconSize:[24,24],iconAnchor:[12,24]})}).bindPopup(pop).addTo(MAP);
    else MK.ord[o.id].setPopupContent(pop);
  });
  ['drv','ord'].forEach(function(k){ Object.keys(MK[k]).forEach(function(id){
    if(!keep[k][id]){ MAP.removeLayer(MK[k][id]); delete MK[k][id]; } }); });
  if(!fitted&&pts.length){ MAP.fitBounds(L.latLngBounds(pts).pad(0.3),{maxZoom:15}); fitted=true; }
  setTimeout(function(){ MAP.invalidateSize(); },50);
}

/* ---------- الأوامر ---------- */
async function addDriver(){
  var n=$('#dlvDName').value.trim(), ph=$('#dlvDPhone').value.trim();
  if(n.length<2) return toast('اكتب اسم الموظف',false);
  var r=await A.sb.from('drivers').insert({restaurant_id:A.R.id,name:n,phone:ph});
  if(r.error) return toast('ما انحفظ: '+r.error.message,false);
  $('#dlvDName').value=''; $('#dlvDPhone').value=''; toast('تمت إضافة الموظف ✓'); load();
}
function rndId(){ var a=new Uint8Array(7); crypto.getRandomValues(a);
  return 'la'+Array.prototype.map.call(a,function(b){return ('0'+b.toString(16)).slice(-2)}).join(''); }
async function addDevice(){
  var k=$('#dlvKKind').value, lb=$('#dlvKLabel').value.trim(), id=$('#dlvKId').value.trim();
  if(k==='traccar_app') id=id||rndId();
  if(!id) return toast('اكتب رقم الجهاز (IMEI / ID)',false);
  var r=await A.sb.from('tracker_devices').insert({restaurant_id:A.R.id,kind:k,label:lb,identifier:id});
  if(r.error) return toast(/duplicate|unique/i.test(r.error.message)?'هالرقم مسجّل من قبل':'ما انحفظ: '+r.error.message,false);
  $('#dlvKLabel').value=''; $('#dlvKId').value=''; toast('تمت إضافة الجهاز ✓'); load();
}
async function saveSettings(mode,newKey){
  var r=await A.sb.rpc('admin_delivery_settings',{rid:A.R.id,p_mode:mode,p_new_key:!!newKey});
  var m=$('#dlvSetMsg');
  if(r.error){ m.className='msg e'; m.textContent='ما انحفظ'; return; }
  F.settings=r.data; m.className='msg s'; m.textContent='انحفظ ✓'; paint();
}
async function onClick(e){
  var b;
  if((b=e.target.closest('[data-copy]'))) return copy(b.dataset.copy);
  if((b=e.target.closest('[data-focus]'))&&MAP){ var c=b.dataset.focus.split(',').map(Number);
    MAP.setView(c,16); $('#dlvMap').scrollIntoView({behavior:'smooth',block:'center'}); return; }
  if((b=e.target.closest('[data-oa]'))){
    if(b.dataset.oa==='cancel'&&!confirm('إلغاء توصيل هالطلب؟')) return;
    var r=await A.sb.rpc('admin_dispatch',{p_order:Number(b.dataset.id),p_action:b.dataset.oa,p_driver:null});
    if(r.error) toast('ما زبط: '+r.error.message,false); return load();
  }
  if((b=e.target.closest('[data-da]'))){
    var id=b.dataset.id, a=b.dataset.da, q;
    if(a==='del'){ if(!confirm('حذف الموظف؟ طلباتو القديمة بتضل محفوظة.')) return;
      q=A.sb.from('drivers').delete().eq('id',id); }
    if(a==='toggle') q=A.sb.from('drivers').update({is_active:b.dataset.on!=='true',on_duty:false}).eq('id',id);
    if(a==='token'){ if(!confirm('الرابط القديم رح يوقف يشتغل. متأكد؟')) return;
      var t=new Uint8Array(16); crypto.getRandomValues(t);
      q=A.sb.from('drivers').update({token:Array.prototype.map.call(t,function(x){return ('0'+x.toString(16)).slice(-2)}).join('')}).eq('id',id); }
    var r2=await q; if(r2.error) toast('ما زبط: '+r2.error.message,false); return load();
  }
  if((b=e.target.closest('[data-ka]'))){
    if(!confirm('حذف الجهاز؟')) return;
    var r3=await A.sb.from('tracker_devices').delete().eq('id',b.dataset.id);
    if(r3.error) toast('ما زبط',false); return load();
  }
}
async function onChange(e){
  var s=e.target, r;
  if(s.dataset.assign){
    if(!s.value) return;
    r=await A.sb.rpc('admin_dispatch',{p_order:Number(s.dataset.assign),p_action:'assign',p_driver:s.value});
  } else if(s.dataset.devdrv){
    // جهاز واحد لكل موظف
    if(s.value) await A.sb.from('tracker_devices').update({driver_id:null}).eq('driver_id',s.value).neq('id',s.dataset.devdrv);
    r=await A.sb.from('tracker_devices').update({driver_id:s.value||null}).eq('id',s.dataset.devdrv);
  } else return;
  if(r&&r.error) toast('ما زبط: '+r.error.message,false); else toast('تم ✓');
  load();
}

window.DLV={
  open:async function(){
    A=window.LA_ADMIN; if(!A||!A.R) return;
    openFlag=true; shell();
    try{ await needLeaflet(); }catch(e){ console.warn('leaflet failed'); }
    await load();
    clearInterval(timer);
    timer=setInterval(function(){
      // ما منحدّث وقت عم يختار من قائمة لحتى ما تسكّر بوجهو
      var ae=document.activeElement;
      if(openFlag&&document.visibilityState==='visible'&&!(ae&&ae.tagName==='SELECT'&&$('#dlvRoot').contains(ae))) load();
    },5000);
  },
  close:function(){ openFlag=false; clearInterval(timer); timer=null; }
};
})();
