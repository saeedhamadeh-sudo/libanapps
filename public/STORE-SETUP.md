# برنامج المتجر الإلكتروني (Ecommerce Website) — خطوات التشغيل

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

## 5) Whish لكل متجر
صاحب المتجر بيحط Channel/Secret الخاصين فيه من الإعدادات. متاح للدولار والليرة فقط.
الـcallbacks: `/api/store/whish/callback-success` و`/callback-failure` (نفس منطق المنيو: تحقق مباشر من Whish).

## 6) قيود معروفة
- واجهة المتجر بتحمّل حتى 2000 منتج بطلب واحد؛ لمتاجر أكبر لازم صفحات (pagination).
- الصور بتنرفع للـbuckets العامة (نفس سياسات المنيو الحالية: أي مستخدم مسجّل يقدر يكتب بها).
- ترجمة الموقع الرئيسي EN/FR ما شملت نصوص الصفحة الجديدة (بتظهر بالعربي).
