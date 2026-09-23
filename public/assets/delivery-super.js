/* ============================================================
   LibanApps — تبويب «التوصيل» بلوحة المشرف (super)
   · تعديل الأسعار العامة (175$ / 25$)
   · تفعيل أو تمديد كاش لأي مطعم · مقاعد موظفين كاش أو هدية
   · سعر خاص لمطعم معيّن · إيقاف الاشتراك
   ============================================================ */
(function(){
"use strict";
var CFG=window.LIBANAPPS||{}, sb=null, LIST=[], OPEN={}, PRICES={};
var $=function(s){return document.querySelector(s)};
function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){
  return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})}
function dt(t){ return t?new Date(t).toLocaleDateString('en-GB'):'—'; }
function days(t){ return Math.ceil((new Date(t)-Date.now())/86400000); }
function money(v){ return v==null||v===''?'':('$'+Number(v)); }
function toast(t,ok){ var e=document.createElement('div');
  e.style.cssText='position:fixed;left:50%;bottom:24px;transform:translateX(-50%);z-index:999;padding:10px 16px;'+
    'border-radius:12px;font-weight:700;font-size:14px;color:#fff;background:'+(ok===false?'#B91C1C':'#111');
  e.textContent=t; document.body.appendChild(e); setTimeout(function(){e.remove()},2600); }

function shell(){
  var root=$('#dsRoot'); if(root.dataset.ready) return; root.dataset.ready=1;
  var st=document.createElement('style');
  st.textContent='.ds-chip{display:inline-block;font-size:11.5px;font-weight:800;border-radius:999px;padding:2px 9px}'+
    '.ds-on{background:rgba(74,222,128,.15);color:#4ADE80}.ds-off{background:rgba(255,122,126,.15);color:#FF7A7E}'+
    '.ds-no{background:rgba(255,255,255,.07);color:var(--muted)}.ds-warn{background:rgba(255,212,0,.15);color:var(--accent)}'+
    '.ds-box{background:var(--bg-2);border:1px solid var(--line);border-radius:12px;padding:12px;margin:6px 0 4px}'+
    '.ds-row{display:flex;gap:8px;flex-wrap:wrap;align-items:flex-end;margin-top:8px}'+
    '.ds-row>div{flex:1;min-width:120px}.ds-row label{display:block;font-size:12px;color:var(--muted);margin-bottom:3px}'+
    '.ds-seat{display:flex;gap:8px;align-items:center;padding:6px 0;border-bottom:1px dashed var(--line);font-size:13px}'+
    '.ds-seat:last-child{border:0}.ds-seat span{flex:1}';
  document.head.appendChild(st);
  root.innerHTML=
  '<div class="panel"><h3>أسعار نظام التوصيل (لكل المطاعم)</h3>'+
    '<div class="ds-row">'+
      '<div><label>الاشتراك السنوي ($) — بيشمل موظف</label><input type="number" id="dsBase" min="0" step="1"></div>'+
      '<div><label>كل موظف إضافي ($/سنة)</label><input type="number" id="dsSeat" min="0" step="1"></div>'+
      '<div><label>المدة (يوم)</label><input type="number" id="dsDays" min="1" step="1"></div>'+
      '<div style="flex:none"><button class="btn" id="dsSavePrices">حفظ الأسعار</button></div>'+
    '</div>'+
    '<p class="muted" style="margin-top:8px">السعر الخاص لمطعم معيّن (تحت) بيغلب على السعر العام. الأسعار الجديدة بتنطبق على الدفعات الجاية بس.</p>'+
  '</div>'+
  '<div class="panel"><h3>المطاعم ونظام التوصيل</h3>'+
    '<div class="ds-row" style="margin-top:0"><div><input type="text" id="dsQ" placeholder="بحث بالاسم أو الرابط"></div>'+
      '<div style="flex:none"><select id="dsF"><option value="">الكل</option><option value="on">مفعّل</option>'+
      '<option value="off">منتهي</option><option value="never">ما اشترك</option></select></div>'+
      '<div style="flex:none"><button class="btn alt" id="dsRef">تحديث</button></div></div>'+
    '<div style="overflow-x:auto;margin-top:10px"><table><thead><tr><th>المطعم</th><th>الحالة</th><th>الموظفين</th>'+
      '<th>مدفوع Whish</th><th></th></tr></thead><tbody id="dsBody"></tbody></table></div>'+
  '</div>';
  $('#dsSavePrices').onclick=savePrices;
  $('#dsQ').oninput=paint; $('#dsF').onchange=paint; $('#dsRef').onclick=load;
  root.addEventListener('click',onClick);
}

async function load(){
  var pr=await sb.from('addon_prices').select('*');
  (pr.data||[]).forEach(function(x){ PRICES[x.code]=x; });
  if(PRICES.delivery){ $('#dsBase').value=PRICES.delivery.price_usd; $('#dsDays').value=PRICES.delivery.days; }
  if(PRICES.driver_seat) $('#dsSeat').value=PRICES.driver_seat.price_usd;
  var r=await sb.rpc('super_delivery_list');
  if(r.error){ $('#dsBody').innerHTML='<tr><td colspan="5" class="muted">'+esc(r.error.message)+
    ' — تأكد إنك شغّلت db/upgrade-delivery.sql</td></tr>'; return; }
  LIST=r.data||[]; paint();
}

function status(x){
  if(!x.expires_at) return '<span class="ds-chip ds-no">ما اشترك</span>';
  if(!x.active) return '<span class="ds-chip ds-off">منتهي '+dt(x.expires_at)+'</span>';
  var d=days(x.expires_at);
  return '<span class="ds-chip '+(d<=15?'ds-warn':'ds-on')+'">لحد '+dt(x.expires_at)+' · '+d+' يوم</span>';
}
function paint(){
  var q=($('#dsQ').value||'').trim().toLowerCase(), f=$('#dsF').value;
  var rows=LIST.filter(function(x){
    if(q && (x.name+' '+x.slug).toLowerCase().indexOf(q)<0) return false;
    if(f==='on') return x.active; if(f==='off') return x.expires_at&&!x.active; if(f==='never') return !x.expires_at;
    return true;
  });
  $('#dsBody').innerHTML=rows.length?rows.map(function(x){
    var h='<tr><td><b>'+esc(x.name)+'</b><div class="muted" style="direction:ltr;text-align:right">/'+esc(x.slug)+'</div></td>'+
      '<td>'+status(x)+(x.base_price!=null||x.seat_price!=null?'<div class="muted">سعر خاص: '+
        (x.base_price!=null?money(x.base_price):'عام')+' / '+(x.seat_price!=null?money(x.seat_price):'عام')+'</div>':'')+'</td>'+
      '<td>'+x.drivers+' / '+x.capacity+'</td><td>'+money(x.paid)+'</td>'+
      '<td><button class="btn alt sm" data-ds="toggle" data-id="'+x.id+'">'+(OPEN[x.id]?'إخفاء':'إدارة')+'</button></td></tr>';
    if(OPEN[x.id]) h+='<tr><td colspan="5">'+detail(x)+'</td></tr>';
    return h;
  }).join(''):'<tr><td colspan="5" class="muted">ما في نتائج</td></tr>';
}
function detail(x){
  var seats=(x.seats||[]);
  return '<div class="ds-box">'+
    '<b>الاشتراك الأساسي</b>'+
    '<div class="ds-row">'+
      '<div><label>تمديد (يوم) — سالب للتقصير</label><input type="number" id="dsExt-'+x.id+'" value="365"></div>'+
      '<div><label>ملاحظة (مثلاً: كاش 175$)</label><input type="text" id="dsNote-'+x.id+'" value="'+esc(x.notes||'')+'"></div>'+
      '<div style="flex:none"><button class="btn y" data-ds="extend" data-id="'+x.id+'">'+(x.active?'تمديد':'تفعيل كاش')+'</button></div>'+
      (x.active?'<div style="flex:none"><button class="btn dg" data-ds="stop" data-id="'+x.id+'">إيقاف</button></div>':'')+
    '</div>'+
    '<b style="display:block;margin-top:14px">مقاعد موظفين إضافية ('+seats.length+')</b>'+
    (seats.length?seats.map(function(s,i){
      var on=new Date(s.expires_at)>Date.now();
      return '<div class="ds-seat"><span>مقعد '+(i+1)+' · '+(s.source==='whish'?'Whish':s.source==='gift'?'هدية':'كاش')+'</span>'+
        '<span class="muted" style="flex:none">'+(on?'لحد ':'منتهي ')+dt(s.expires_at)+'</span>'+
        '<button class="btn alt sm" data-ds="seatext" data-seat="'+s.id+'" data-d="365">+سنة</button>'+
        '<button class="btn dg sm" data-ds="seatdel" data-seat="'+s.id+'">حذف</button></div>';
    }).join(''):'<div class="muted">ما في مقاعد إضافية — الاشتراك بيشمل '+x.included+' موظف</div>')+
    '<div class="ds-row">'+
      '<div><label>عدد المقاعد</label><input type="number" id="dsCnt-'+x.id+'" value="1" min="1" max="50"></div>'+
      '<div><label>المدة (يوم)</label><input type="number" id="dsSd-'+x.id+'" value="365" min="1"></div>'+
      '<div><label>المصدر</label><select id="dsSrc-'+x.id+'"><option value="cash">كاش</option><option value="gift">هدية</option></select></div>'+
      '<div style="flex:none"><button class="btn" data-ds="seats" data-id="'+x.id+'">إضافة مقاعد</button></div>'+
    '</div>'+
    '<b style="display:block;margin-top:14px">سعر خاص لهالمطعم (فاضي = السعر العام)</b>'+
    '<div class="ds-row">'+
      '<div><label>الاشتراك ($)</label><input type="number" id="dsPb-'+x.id+'" value="'+(x.base_price==null?'':x.base_price)+'" placeholder="'+(PRICES.delivery?PRICES.delivery.price_usd:'')+'"></div>'+
      '<div><label>الموظف الإضافي ($)</label><input type="number" id="dsPs-'+x.id+'" value="'+(x.seat_price==null?'':x.seat_price)+'" placeholder="'+(PRICES.driver_seat?PRICES.driver_seat.price_usd:'')+'"></div>'+
      '<div><label>موظفين ضمن الاشتراك</label><input type="number" id="dsInc-'+x.id+'" value="'+x.included+'" min="0" max="50"></div>'+
      '<div style="flex:none"><button class="btn alt" data-ds="price" data-id="'+x.id+'">حفظ</button></div>'+
    '</div>'+
  '</div>';
}

async function savePrices(){
  var b=Number($('#dsBase').value), s=Number($('#dsSeat').value), d=Number($('#dsDays').value)||365;
  if(!(b>0)||!(s>=0)) return toast('أسعار غير صحيحة',false);
  var r1=await sb.from('addon_prices').upsert([{code:'delivery',price_usd:b,days:d,updated_at:new Date().toISOString()},
                                            {code:'driver_seat',price_usd:s,days:d,updated_at:new Date().toISOString()}]);
  if(r1.error) return toast('ما انحفظ: '+r1.error.message,false);
  toast('انحفظت الأسعار ✓'); load();
}
function num(id){ var v=$(id).value; return v===''?null:Number(v); }
async function onClick(e){
  var b=e.target.closest('[data-ds]'); if(!b) return;
  var id=b.dataset.id, a=b.dataset.ds, r;
  if(a==='toggle'){ OPEN[id]=!OPEN[id]; return paint(); }
  b.disabled=true;
  if(a==='extend'){
    var d=Number($('#dsExt-'+id).value);
    if(!d) { b.disabled=false; return toast('اكتب عدد الأيام',false); }
    r=await sb.rpc('super_delivery_extend',{rid:id,p_days:d,p_note:$('#dsNote-'+id).value.trim()});
  }
  if(a==='stop'){ if(!confirm('إيقاف نظام التوصيل لهالمطعم هلق؟')){ b.disabled=false; return; }
    r=await sb.rpc('super_delivery_stop',{rid:id}); }
  if(a==='seats') r=await sb.rpc('super_delivery_add_seats',{rid:id,p_count:Number($('#dsCnt-'+id).value)||1,
    p_days:Number($('#dsSd-'+id).value)||365,p_source:$('#dsSrc-'+id).value});
  if(a==='seatext') r=await sb.rpc('super_delivery_seat',{p_seat:b.dataset.seat,p_days:Number(b.dataset.d)});
  if(a==='seatdel'){ if(!confirm('حذف المقعد؟ إذا عدد الموظفين صار أكتر من المقاعد، آخر موظف انضاف بيوقف.')){ b.disabled=false; return; }
    r=await sb.rpc('super_delivery_seat',{p_seat:b.dataset.seat,p_days:0}); }
  if(a==='price') r=await sb.rpc('super_delivery_prices',{rid:id,p_base:num('#dsPb-'+id),p_seat:num('#dsPs-'+id),
    p_included:num('#dsInc-'+id)});
  b.disabled=false;
  if(r&&r.error) return toast('ما زبط: '+r.error.message,false);
  toast('تم ✓'); load();
}

document.addEventListener('DOMContentLoaded',function(){
  var t=document.querySelector('.tab[data-t="delivery"]'); if(!t) return;
  t.addEventListener('click',function(){
    if(!sb) sb=window.supabase.createClient(CFG.SUPABASE_URL,CFG.SUPABASE_ANON_KEY);
    shell(); load();
  });
});
})();
