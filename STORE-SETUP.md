# برنامج المتجر الإلكتروني (Ecommerce Website) — خطوات التشغيل

> **v2:** بعد `db/upgrade-store.sql` شغّل كمان `db/upgrade-store-v2.sql` (نوع المتجر، مقاسات/ألوان/مواصفات، تقييمات، صفحات، مشتركين، مناطق شحن، بوابات الدفع). آمن للتشغيل أكثر من مرة، وآخر استعلام بيرجّع 4 صفوف كلها `true`.
> **v3:** شغّل كمان `db/upgrade-store-v3.sql` (تصنيفات فرعية + أيقونات، صورة سلايدر تنقل لتصنيف، 3 بنرات تحت السلايدر). آخر استعلام 3 صفوف `true`.
> **v4:** شغّل كمان `db/upgrade-store-v4.sql` (استيراد WooCommerce: عدة تصنيفات للمنتج، سعر خاص لكل خيار، وصف المنتج بيتجلب عند فتحه). آخر استعلام 3 صفوف `true`. الاستيراد: لوحة المتجر ← «استيراد منتجات» (ملف CSV من ووردبريس). نسخ الصور بيحتاج `worker.js` الجديد (`/api/store/import-image`).
> **v5:** شغّل كمان `db/upgrade-store-v5.sql` (قائمة ماركات منظّمة store_brands مع تعبئة تلقائية من ماركات منتجاتك الحالية + أيقونة متصفح favicon منفصلة عن اللوغو). آخر استعلام صفين `true`.
> **نسخ احتياطي / استعادة / فرمتة:** بتبويب «الإعدادات» صار في:
> - **تنزيل نسخة احتياطية:** ملف CSV واحد فيه كل شي (تصنيفات، منتجات، سلايدر، بنرات، ماركات، صفحات، كوبونات، إعدادات المتجر) — بدون الطلبات/التقييمات/المشتركين ولا مفاتيح بوابات الدفع.
> - **استعادة من نسخة احتياطية:** برفع نفس الملف بتستبدل كل شي بمحتواه (تأكيدين قبل التنفيذ).
> - **فرمتة المتجر بالكامل:** بتصفّر كل شي عدا اسم المتجر وإعداداته وبوابات الدفع والدومين والاشتراك وسجل الطلبات — بعداد 10 ثواني قبل ما يصير الزر قابل للضغط.
> **v6 — تخصيص أوسع:** شغّل `db/upgrade-store-v6.sql` (ترتيب/تفعيل أقسام الصفحة الرئيسية، استدارة الحواف، كثافة التباعد، أزواج خطوط). بتبويب «الثيم والمظهر» صار في: قسم «أقسام الصفحة الرئيسية» (تفعيل/إخفاء وترتيب بالأسهم)، «الشكل والتباعد» (حاد/ناعم/مدوّر + مريح/مضغوط)، و«الخط» (5 أزواج جاهزة عربي+إنكليزي أو افتراضي الثيم). آخر استعلام 4 أسطر true.
> **v7:** شغّل `db/upgrade-store-v7.sql` (تحكم أعمق: عنوان مخصّص وعدد عناصر لأقسام التصنيفات، وصل حديثاً، أحدث المنتجات + حد أقصى لعدد منتجات Hot Sale — من تبويب «الثيم والمظهر» ← «أقسام الصفحة الرئيسية» ← سهم ▸ بجانب القسم). آخر استعلام سطر true.
> الثيمات الجديدة: `nova` · `aurum` · `pulse` · `bloom` · `atelier` (الثيمات القديمة بتنتقل تلقائياً: maison→aurum، fresh→atelier، volt→pulse، petal→bloom).

## 1) قاعدة البيانات (Supabase — مشروع LibanApps)
1. SQL Editor → الصق كل `db/upgrade-store.sql` → Run.
   (آمن للتشغيل أكثر من مرة. آخر استعلام بيرجّع 3 صفوف كلها `true`.)
2. ما بيلزم buckets جديدة: المتجر بيستعمل `logos` و`items` و`banners` الموجودين.

## 2) النشر
نفس الخطوات المعتادة: `libanapps.zip` → رفع على Cloudflare Workers → اختبار بنافذة incognito.
ملفات جديدة: `store.html` · `store-admin.html` · `product-store.html` · `db/upgrade-store.sql`
ملفات معدّلة: `worker.js` · `account.html` · `super.html` · `index.html` وصفحات المنتجات (رابط التبويب).

## 3) الروابط
| الرابط | الوظيفة |
|---|---|
| `libanapps.com/store-info` | صفحة البيع والأسعار (تبويب «متجر إلكتروني») |
| `libanapps.com/portal-store/<slug>` | متجر الزبون |
| `libanapps.com/portal-store/<slug>/admin` | لوحة تحكم الزبون |

- التجربة: 5 أيام (`products.trial_days`) — الزبون بيضغط «ابدأ التجربة» من `/account` وبيختار الـslug.
- الاشتراك: باقة `store` — 250$ / 365 يوم (عدّلها من تبويب «الباقات» بلوحتك).
- بعد الدفع، المتجر بينبني تلقائياً أول ما الزبون يفتح لوحته.
- من `/super` → «إصدار ترخيص جديد» → البرنامج «متجر إلكتروني» + رابط واسم = متجر جاهز بدون دفع.
- انتهاء الاشتراك: المتجر بيظهر للزوار «متوقف مؤقتاً» والبيانات بتضل محفوظة.

## 4) الدومين الخاص (Cloudflare for SaaS)
الكود جاهز. لتفعيله بالكامل:
1. Cloudflare → منطقة `libanapps.com` → SSL/TLS → **Custom Hostnames**: فعّلها (تأكد من الخطة والتسعير).
2. أنشئ سجل DNS مُبروكسي (Proxied) اسمه `stores` ← يشير لأي هدف صالح، وحطّه كـ **Fallback Origin**.
3. تأكد إن الـWorker `libanapps` يستقبل طلبات هذا الـhostname (Route على المنطقة أو Custom Domain) — راجع توثيق Cloudflare لأنو الطريقة بتختلف حسب إعدادك.
4. أضف على الـWorker:
   - Secret: `CF_API_TOKEN` (صلاحية: SSL and Certificates → Edit، على هذه المنطقة)
   - Secret: `CF_ZONE_ID`
   - (اختياري) Variable: `STORE_CNAME_TARGET` (الافتراضي `stores.libanapps.com`)
5. الزبون بيضيف من لوحته «الدومين» ← بيعمل CNAME عند مزوّد دومينه ← «تحقق الآن».

بدون `CF_API_TOKEN`: الدومين بينسجّل «بانتظار الربط» وبتفعّله يدوياً:
```sql
update store_domains set status='active' where domain='shop.mybrand.com';
```
(الـWorker بيخدم أي دومين مسجّل إذا وصله الطلب فعلاً.)

## 5) بوابات الدفع (v2)
كل صاحب متجر بيفعّل البوابة بمفاتيحه من لوحته ← «الدفع». المفاتيح بتتخزن بجدول `store_gateways` (بدون أي RLS — ما بتوصل للمتصفح أبداً).
الطلب الأونلاين بيمرّ: `store_place_order` ← `/api/store/pay/create` (رابط الدفع) ← رجوع الزبون ← `/api/store/pay/verify` (تحقق مباشر من البوابة). `/api/store/pay/webhook?t=<token>` بيشغّل نفس التحقق.

| البوابة | الحقول المطلوبة | العملات |
|---|---|---|
| Stripe | `secret_key` (sk_live / sk_test) | أغلب العملات |
| PayPal | `client_id` + `secret` + `mode` (sandbox/live) | عملات PayPal المدعومة (USD, EUR, GBP…) |
| Binance Pay | `api_key` + `secret_key` + `currency` (USDT…) | متاجر USD (1:1 إلى USDT) أو EUR |
| Areeba (MPGS) | `merchant_id` + `api_password` + `host` + `api_version` | حسب حساب التاجر |
| Whish | `channel` + `secret` | USD / LBP |
| MontyPay / Custom | `create_url`, `body` (قالب), `redirect_path`, اختياري: `headers`, `content_type`, `ref_path`, `status_url`, `status_path`, `paid_values` | أي عملة |
| تحويل بنكي | `instructions` (نص يظهر بعد الطلب) | أي عملة |

قالب البوابة العامة بيدعم: `{{amount}} {{amount_minor}} {{currency}} {{order_no}} {{order_id}} {{reference}} {{return_url}} {{cancel_url}} {{webhook_url}} {{customer_name}} {{customer_email}} {{customer_phone}} {{store_name}}`.
بدون `status_url` ما بيتأكد الدفع تلقائياً — بيتأكد يدوياً من الطلبات.

**إضافة بوابة جديدة بالكود:** أضف adapter (`create` + `verify`) لـ`GATEWAYS` بـ`worker.js`، وسطر بـ`_gw_ready` و`_gw_supports` بالـSQL، وتعريف بـ`GW_DEFS` بـ`store-admin.html`.

**تنبيهات قبل الإنتاج (جرّبها بمفاتيح تجريبية أولاً):**
- Areeba: رابط الدفع `https://<host>/checkout/pay/<session>` — تأكد من نسخة الـAPI وإعدادات Hosted Checkout عند Areeba.
- Binance Pay: الـAPI v3 — تأكد إن العملة (USDT/…) مفعّلة بحساب التاجر.
- MontyPay: القالب مبني على إعدادات REST عامة؛ اضبط الحقول حسب توثيق MontyPay الرسمي.

## 6) قيود معروفة
- واجهة المتجر بتحمّل حتى 2000 منتج بطلب واحد؛ لمتاجر أكبر لازم صفحات (pagination).
- الصور بتنرفع للـbuckets العامة (نفس سياسات المنيو الحالية: أي مستخدم مسجّل يقدر يكتب بها).
- ترجمة الموقع الرئيسي EN/FR ما شملت نصوص الصفحة الجديدة (بتظهر بالعربي).
