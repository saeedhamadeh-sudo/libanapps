# النشر على Cloudflare Pages — خطوة بخطوة

## قبل ما تبلّش

ارفع على GitHub الملفين الجداد:
- `functions/api/store-invoice.js` ← مجلد **جديد** بجذر المشروع، اسمه `functions` (مش `netlify/functions`)
- `public/_redirects`

الشكل صار هيك:

```
libanapps/
├── functions/            ← جديد (لـCloudflare)
│   └── api/
│       └── store-invoice.js
├── netlify/              ← بيضل موجود، Cloudflare بيتجاهله
├── public/
│   ├── _redirects        ← جديد
│   ├── menu.html
│   └── …
├── db/
├── netlify.toml
└── package.json
```

---

## الخطوة ١ — الحساب

اذهب إلى `dash.cloudflare.com` واعمل حساب مجاني (إيميل وكلمة مرور، بدون بطاقة).

## الخطوة ٢ — ربط المشروع

1. من القائمة اليسار: **Workers & Pages**
2. اضغط **Create** ← تبويب **Pages** ← **Connect to Git**
3. اربط حساب GitHub واسمح لـCloudflare يشوف الريبو `libanapps`
4. اختار الريبو ← **Begin setup**

## الخطوة ٣ — إعدادات البناء

| الحقل | القيمة |
|---|---|
| Project name | `libanapps` |
| Production branch | `main` |
| Framework preset | **None** |
| Build command | **اتركه فاضي** |
| Build output directory | `public` |
| Root directory | **اتركه فاضي** |

> مهم: `Build output directory` لازم يكون `public` بالضبط. ومجلد `functions` بيتلقّط تلقائياً من جذر المشروع.

اضغط **Save and Deploy**. أول نشر بياخد أقل من دقيقة.

## الخطوة ٤ — متغيرات البيئة

بعد أول نشر: **Settings** ← **Environment variables** ← **Add variable**

اختار **Production** وضيف:

| Variable name | Value |
|---|---|
| `SUPABASE_URL` | `https://moriwmhlgugmjzddwfgv.supabase.co` |
| `SUPABASE_SERVICE_KEY` | المفتاح السرّي `sb_secret_…` |
| `WEBSITE_URL` | رابط مشروعك على Cloudflare |

للمفتاح السرّي، اضغط **Encrypt** جنبه — هيك ما بيرجع يظهر لحدا.

بعدها: **Deployments** ← آخر نشر ← **Retry deployment**. المتغيرات ما بتوصل للنشر القديم.

## الخطوة ٥ — جرّب

الرابط بيكون `libanapps.pages.dev` (أو الاسم اللي اخترته).

| افتح | المتوقع |
|---|---|
| `/super` | شاشة دخول لوحتك |
| `/snackattack` | منيو المطعم |
| `/test-map.html` | صفحة الفحص السبعة |
| `/admin` | لوحة صاحب المطعم |

## الخطوة ٦ — الدومين

**Custom domains** ← **Set up a domain** ← اكتب `libanapps.com`

إذا الدومين مسجّل عندك بمكان تاني، Cloudflare بيعطيك اثنين nameservers بتحطهن عند الشركة اللي شاريه منها. بياخد من ساعة لـ٢٤ ساعة.

الأسهل: انقل الدومين لـCloudflare نفسها — الأسعار عندهم بسعر التكلفة بدون هامش ربح، وبيصير كل شي بمكان واحد.

بعد ما يزبط الدومين، رجاع على **Environment variables** وبدّل `WEBSITE_URL` لـ`https://libanapps.com`، وأعد النشر.

---

## شو بيشتغل وشو لأ

| الميزة | الحالة |
|---|---|
| المنيو والسلة والطلبات | ✅ شغّالة |
| لوحة المطعم ولوحتك | ✅ شغّالة |
| صفحة الفاتورة | ✅ شغّالة |
| حفظ ملف PDF | ✅ شغّال (الملف الجديد) |
| الدفع عبر Whish | ⏳ بدّو تحويل لصيغة Cloudflare |

دوال Whish لسا بصيغة Netlify. ما بتوقف شي هلق لأنك ما فعّلت Whish بعد — ولما توصلك بياناتهم منحوّلها، شغل ساعة.

## ملاحظة على GitHub

ما في داعي تحذف مجلد `netlify` أو ملف `netlify.toml`. Cloudflare بيتجاهلهن، وبتضل عندك النسخة الجاهزة إذا رجع حساب Netlify اشتغل وحبيت تنشر على الاثنين.
