// يدمج ثيم «أفق» (CSS + JS) داخل صفحات الموقع العامة — قابل للتكرار بأمان
// التشغيل:  node tools/inline-horizon.js
const fs=require('fs'), path=require('path');
const PUB=path.join(__dirname,'..','public');
const PAGES=['index','product-menus','product-industrial','product-trade','product-store','login','signup','account'];
const css=fs.readFileSync(path.join(PUB,'assets/theme-horizon.css'),'utf8').trim();
const js =fs.readFileSync(path.join(PUB,'assets/theme-horizon.js'),'utf8').trim();
const HOOK='if(window.LASiteTheme) LASiteTheme(s.theme); /*HZ*/';
let fail=0;
for(const p of PAGES){
  const f=path.join(PUB,p+'.html'); let h=fs.readFileSync(f,'utf8');
  h=h.replace(/\n?\/\* ===== HORIZON THEME START[\s\S]*?HORIZON THEME END ===== \*\/\n?/,'\n');
  h=h.replace(/\n?<script>\/\* ===== HORIZON JS START[\s\S]*?HORIZON JS END ===== \*\/<\/script>\n?/,'\n');
  const i=h.indexOf('</style>');
  if(i<0){ console.error('✗ '+p+': ما لقينا </style>'); fail++; continue; }
  h=h.slice(0,i)+css+'\n'+'</style>\n<script>'+js+'</script>'+h.slice(i+'</style>'.length);
  if(!h.includes(HOOK)){
    if(p==='index'){
      const old="if(s.theme) document.documentElement.setAttribute('data-theme', s.theme);";
      if(!h.includes(old)){ console.error('✗ index: سطر الثيم القديم مش موجود'); fail++; continue; }
      h=h.replace(old,HOOK);
    }else{
      const a="var s=r.data; if(!s) return;";
      if(!h.includes(a)){ console.error('✗ '+p+': ما لقينا معالج public_settings'); fail++; continue; }
      h=h.replace(a,a+'\n  '+HOOK);
    }
  }
  fs.writeFileSync(f,h); console.log('✓ '+p);
}
// خيار الثيم بلوحة /super
const sf=path.join(PUB,'super.html'); let s=fs.readFileSync(sf,'utf8');
if(!s.includes('value="horizon"')){
  const a='<option value="green">أخضر</option>';
  if(!s.includes(a)){ console.error('✗ super: ما لقينا قائمة الثيمات'); fail++; }
  else{ s=s.replace(a,a+'\n          <option value="horizon">أفق — عصري (جديد)</option>'); fs.writeFileSync(sf,s); console.log('✓ super'); }
} else console.log('✓ super (موجود)');
process.exit(fail?1:0);
