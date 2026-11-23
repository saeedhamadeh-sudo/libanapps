/* دليل استخدام برنامج المولّد — كل قسم إلو جمهور (who):
   all = الجميع · reader = موظف أخذ العداد · collector = الجابي · cut = صلاحية الفتح/القطع · admin = المدير والمدير الأساسي · main = المدير الأساسي فقط
   النص: [عربي, English, Français] */
window.MOTOR_GUIDE = [
  /* ================= للجميع ================= */
  { id: 'start', who: ['all'], ic: '👋',
    t: ['البدء والدخول', 'Getting started', 'Premiers pas'],
    p: ['هذا الدليل مخصّص لعملك أنت، ويظهر فيه فقط ما يخصّ صلاحياتك في البرنامج.', 'This guide covers only what your account can do.', 'Ce guide ne couvre que ce que votre compte peut faire.'],
    s: [
      ['ادخل باسم المستخدم وكلمة السر اللذين أعطاك إياهما المدير. لا تعطِ كلمة السر لأي شخص.', 'Sign in with the username and password your manager gave you. Never share your password.', 'Connectez-vous avec l’identifiant et le mot de passe fournis par le gérant. Ne les partagez jamais.'],
      ['في أعلى الشاشة يظهر اسمك ونوع حسابك، وبجانبه «مباشر» باللون الأخضر عندما يكون الاتصال بالإنترنت جيداً.', 'Your name and role appear at the top, with a green “Live” mark when the connection is good.', 'Votre nom et votre rôle s’affichent en haut, avec « Direct » en vert quand la connexion est bonne.'],
      ['يمكنك تغيير لغة البرنامج (العربية / English / Français) من القائمة في أعلى الشاشة.', 'Change the language (Arabic / English / French) from the menu at the top.', 'Changez la langue (arabe / anglais / français) depuis le menu en haut.'],
      ['الصفحة الرئيسية 🏠 تعرض المربعات (الأيقونات) الخاصة بعملك؛ اضغط على أي مربع للانتقال إليه، وزر «الرئيسية» يعيدك دائماً.', 'The Home page 🏠 shows tiles for your work; tap a tile to open it, and “Home” always brings you back.', 'L’accueil 🏠 affiche des tuiles pour votre travail ; « Accueil » vous y ramène toujours.'],
      ['على الهاتف: افتح البرنامج من المتصفح ثم اختر «إضافة إلى الشاشة الرئيسية» ليصبح مثل التطبيق.', 'On a phone: open it in the browser, then choose “Add to Home screen” to use it like an app.', 'Sur téléphone : ouvrez-le dans le navigateur puis « Ajouter à l’écran d’accueil ».'],
      ['عند انتهاء العمل اضغط «خروج» في أعلى الشاشة، خصوصاً إذا كان الهاتف أو الكمبيوتر يستعمله غيرك.', 'When you finish, tap “Log out”, especially on a shared phone or computer.', 'À la fin, appuyez sur « Déconnexion », surtout sur un appareil partagé.']
    ] },
  { id: 'find', who: ['all'], ic: '🔎',
    t: ['البحث عن زبون', 'Finding a customer', 'Trouver un client'],
    s: [
      ['في خانة البحث اكتب جزءاً من الاسم، أو رقم الزبون، أو رقم الباركود، أو رقم العداد، أو رقم العلبة.', 'In the search box type part of the name, the customer number, barcode, meter number or box number.', 'Tapez une partie du nom, le numéro client, le code-barres, le numéro de compteur ou de boîtier.'],
      ['البحث لا يتأثر بالهمزات والتاء المربوطة: «احمد» تجد «أحمد».', 'Search ignores Arabic spelling variants (أ/ا, ة/ه).', 'La recherche ignore les variantes d’orthographe arabe.'],
      ['اختر «المنطقة» من القائمة لتعرض زبائن منطقة واحدة فقط.', 'Pick an “Area” to show only one area’s customers.', 'Choisissez une « Zone » pour n’afficher qu’une zone.'],
      ['زر «📷 مسح الباركود» يفتح الكاميرا: وجّهها نحو ملصق الباركود على العداد فيُفتح الزبون مباشرة. إذا لم تعمل الكاميرا اكتب الرقم يدوياً ثم اضغط Enter.', '“📷 Scan” opens the camera: point it at the meter’s barcode label to open the customer. If it fails, type the code and press Enter.', '« 📷 Scanner » ouvre la caméra ; visez l’étiquette du compteur. Sinon tapez le code puis Entrée.'],
      ['الزبون «المقطوع» يظهر بعلامة مختلفة، والزبون الذي عليه حسم تظهر بجانب اسمه علامة 🏷️.', 'Cut-off customers are marked, and customers with a discount show 🏷️ next to their name.', 'Les clients coupés sont signalés ; ceux avec remise affichent 🏷️.']
    ] },
  { id: 'custpage', who: ['all'], ic: '👤',
    t: ['صفحة الزبون', 'The customer page', 'La fiche client'],
    s: [
      ['تعرض الصفحة: الاسم، الرقم، الباركود، العلبة، المنطقة، رقم الهاتف، نوع الاشتراك، الرصيد المستحق، وآخر عداد.', 'It shows name, number, barcode, box, area, phone, plan, balance due and the last reading.', 'Elle affiche nom, numéro, code-barres, boîtier, zone, téléphone, formule, solde et dernier relevé.'],
      ['«كشف الحساب» يعرض كل الفواتير والإيصالات بالتاريخ مع الرصيد بعد كل حركة، ويمكن طباعته أو إرساله.', '“Statement” lists every bill and receipt by date with the running balance; you can print or send it.', '« Relevé » liste factures et reçus avec le solde courant ; imprimable ou envoyable.'],
      ['زر «واتساب» يفتح محادثة مع الزبون، وزر الموقع يفتح الخريطة للوصول إلى عنوانه إذا كان محفوظاً.', '“WhatsApp” opens a chat with the customer; the location button opens the map if a location is saved.', '« WhatsApp » ouvre une discussion ; le bouton position ouvre la carte si elle est enregistrée.'],
      ['يمكن كتابة «ملاحظة» على الزبون (مثلاً: لا أحد في البيت، العداد معطّل)، فيراها المدير.', 'You can add a note (e.g. nobody home, meter broken) that the manager will see.', 'Vous pouvez ajouter une note (personne, compteur en panne) visible par le gérant.']
    ] },

  /* ================= موظف أخذ العداد ================= */
  { id: 'read', who: ['reader'], ic: '📷',
    t: ['أخذ العداد خطوة بخطوة', 'Reading a meter, step by step', 'Relever un compteur, étape par étape'],
    p: ['من تبويب «📷 أخذ العداد». في أعلى الصفحة يظهر التقدّم: كم زبوناً أُخذ عداده من أصل كل الزبائن في هذه الدورة.', 'From the “📷 Read meter” tab. The top shows progress: how many meters are done out of all customers this cycle.', 'Depuis l’onglet « 📷 Relevé ». En haut : combien de compteurs sont relevés ce cycle.'],
    s: [
      ['تظهر تحت البحث قائمة «الزبائن المتبقّون» الذين لم يُؤخذ عدادهم بعد. اختر المنطقة لتمشي حسب الطريق.', 'Below the search is the list of remaining customers not read yet. Pick your area to follow your route.', 'Sous la recherche : les clients restants. Choisissez votre zone pour suivre votre tournée.'],
      ['امسح باركود العداد أو ابحث عن الزبون واضغط عليه.', 'Scan the meter barcode or search for the customer and tap it.', 'Scannez le code-barres ou cherchez le client et touchez-le.'],
      ['تأكد أن الاسم والعلبة يطابقان العداد الذي أمامك قبل أن تكتب أي رقم.', 'Check the name and box match the meter in front of you before typing anything.', 'Vérifiez que le nom et le boîtier correspondent au compteur devant vous.'],
      ['اكتب «العداد الحالي» كما هو ظاهر على شاشة العداد. يظهر لك العداد السابق والاستهلاك وقيمة الفاتورة التقديرية.', 'Type the current reading exactly as shown on the meter. The previous reading, consumption and estimated bill appear.', 'Saisissez le relevé actuel tel qu’affiché sur le compteur. Précédent, consommation et facture estimée s’affichent.'],
      ['صوّر العداد بحيث تكون الأرقام واضحة. إذا كانت الصورة إجبارية لا يُحفظ العداد بدونها.', 'Photograph the meter so the digits are clear. If photos are required, the reading cannot be saved without one.', 'Photographiez le compteur, chiffres lisibles. Si la photo est obligatoire, rien n’est enregistré sans elle.'],
      ['انتظر «📍 الموقع محدّد». إذا ظهر «تعذّر تحديد الموقع» فعّل GPS في الهاتف واسمح للمتصفح باستعمال الموقع ثم اضغط «إعادة المحاولة».', 'Wait for “📍 Location OK”. If it fails, turn on GPS, allow location in the browser, then tap “Retry”.', 'Attendez « 📍 Position OK ». Sinon activez le GPS, autorisez la position puis « Réessayer ».'],
      ['اضغط «حفظ». يختفي الزبون من قائمة المتبقّين وتُنشأ فاتورته تلقائياً.', 'Tap “Save”. The customer leaves the remaining list and the bill is created automatically.', 'Touchez « Enregistrer ». Le client quitte la liste et la facture est créée automatiquement.']
    ],
    k: [
      ['لا يمكن أن يكون العداد الحالي أقل من السابق؛ إذا ظهرت هذه الرسالة أعد قراءة العداد بتمهّل.', 'The current reading cannot be lower than the previous one; if you see this, read the meter again carefully.', 'Le relevé ne peut pas être inférieur au précédent ; relisez le compteur.'],
      ['يُؤخذ عداد كل زبون مرة واحدة في الدورة. إذا أخطأت لا تحاول إدخاله مرة ثانية — أخبر المدير فهو يستطيع تعديله أو إلغاءه.', 'Each meter is read once per cycle. If you made a mistake, tell the manager — they can edit or cancel it.', 'Un relevé par cycle. En cas d’erreur, prévenez le gérant qui peut le corriger.'],
      ['إذا كان العداد مكسوراً أو لا يمكن الوصول إليه، اكتب ملاحظة على الزبون بدلاً من وضع رقم تقريبي.', 'If the meter is broken or unreachable, write a note instead of guessing a number.', 'Compteur cassé ou inaccessible : écrivez une note plutôt que d’estimer.'],
      ['يتم حساب المسافة بينك وبين موقع الزبون المحفوظ؛ خذ العداد وأنت بجانبه.', 'Your distance from the saved customer location is recorded; read the meter while standing next to it.', 'La distance jusqu’au client est enregistrée ; relevez sur place.']
    ] },
  { id: 'window', who: ['reader'], ic: '🗓️',
    t: ['فترة أخذ العداد', 'Reading period', 'Période de relevé'],
    s: [
      ['المدير يحدّد لكل شهر من أي تاريخ إلى أي تاريخ يُسمح بأخذ العدادات، ويظهر ذلك في أعلى صفحة «أخذ العداد».', 'The manager sets, for each month, the dates when readings are allowed; they appear at the top of “Read meter”.', 'Le gérant fixe les dates de relevé de chaque mois ; elles s’affichent en haut de « Relevé ».'],
      ['خارج هذه التواريخ يرفض البرنامج حفظ العداد ويظهر لك التاريخ المسموح.', 'Outside these dates the reading is refused and the allowed dates are shown.', 'Hors de ces dates, le relevé est refusé et les dates autorisées s’affichent.'],
      ['حاول إنهاء كل منطقتك قبل آخر يوم في الفترة.', 'Try to finish your whole area before the last day of the period.', 'Terminez votre zone avant le dernier jour.']
    ] },
  { id: 'monthme', who: ['reader'], ic: '📋',
    t: ['عداداتي هذا الشهر', 'My readings this month', 'Mes relevés du mois'],
    s: [
      ['من تبويب «🗓️ جدول عدادات الشهر» ترى العدادات التي أخذتها أنت مع التاريخ والصورة والاستهلاك.', 'In “🗓️ Monthly readings” you see the readings you took, with date, photo and consumption.', 'Dans « 🗓️ Relevés du mois » : vos relevés avec date, photo et consommation.'],
      ['اضغط على الصورة لتكبيرها والتأكد من الرقم.', 'Tap a photo to enlarge it and check the number.', 'Touchez une photo pour l’agrandir.']
    ] },

  /* ================= الجابي ================= */
  { id: 'collect', who: ['collector'], ic: '💵',
    t: ['القبض من الزبون', 'Collecting a payment', 'Encaisser un paiement'],
    p: ['من تبويب «💵 القبض». القائمة تعرض الزبائن الذين عليهم مبالغ، الأعلى أولاً.', 'From the “💵 Collect” tab. The list shows customers who owe money, highest first.', 'Onglet « 💵 Encaisser » : les clients débiteurs, du plus élevé au plus faible.'],
    s: [
      ['امسح الباركود أو ابحث عن الزبون واضغط عليه، فيظهر المبلغ المستحق والأشهر غير المدفوعة.', 'Scan or search for the customer and tap them; the amount due and unpaid months appear.', 'Scannez ou cherchez le client ; le montant dû et les mois impayés s’affichent.'],
      ['اكتب المبلغ الذي استلمته فعلاً (يمكن أن يكون جزءاً من المستحق).', 'Enter the amount you actually received (it can be partial).', 'Saisissez le montant réellement reçu (peut être partiel).'],
      ['اختر العملة (دولار أو ليرة) — بالليرة يحوّل البرنامج المبلغ حسب سعر الصرف المحدد من المدير.', 'Choose the currency (USD or LBP) — LBP is converted at the manager’s exchange rate.', 'Choisissez la devise (USD ou LBP) — conversion au taux fixé par le gérant.'],
      ['اختر طريقة الدفع: نقداً أو Whish (إذا حوّل الزبون إلى Whish لا تستلم منه نقداً).', 'Choose the method: cash or Whish (if the customer paid by Whish, do not take cash).', 'Choisissez : espèces ou Whish (si payé par Whish, pas d’espèces).'],
      ['اضغط «✅ تأكيد القبض». يُنشأ إيصال برقم، وينقص رصيد الزبون فوراً.', 'Tap “✅ Confirm payment”. A numbered receipt is created and the balance drops immediately.', 'Touchez « ✅ Confirmer ». Un reçu numéroté est créé et le solde baisse.'],
      ['أرسل الإيصال للزبون عبر واتساب أو اطبعه.', 'Send the receipt by WhatsApp or print it.', 'Envoyez le reçu par WhatsApp ou imprimez-le.']
    ],
    k: [
      ['تأكد من المبلغ قبل التأكيد: الجابي لا يستطيع إلغاء إيصال، فقط المدير.', 'Check the amount before confirming: only the manager can cancel a receipt.', 'Vérifiez avant de confirmer : seul le gérant peut annuler un reçu.'],
      ['لا تقبض مرتين لنفس الدفعة. إذا لم تظهر رسالة «تم القبض ✓» افتح كشف حساب الزبون للتأكد قبل المحاولة مرة ثانية.', 'Never record the same payment twice. If you didn’t see “Payment recorded ✓”, check the customer statement before retrying.', 'N’enregistrez jamais deux fois. Sans « Paiement enregistré ✓ », vérifiez le relevé avant de réessayer.'],
      ['النقود التي تقبضها تدخل صندوقك أنت حتى تسلّمها للمدير.', 'Cash you collect stays in your own box until you hand it to the manager.', 'L’argent encaissé reste dans votre caisse jusqu’à sa remise au gérant.']
    ] },
  { id: 'mybox', who: ['collector'], ic: '🧾',
    t: ['صندوقي وإقفال الصندوق', 'My cash box and closing it', 'Ma caisse et sa clôture'],
    s: [
      ['من تبويب «🧾 كشف حساب الصندوق» ترى كل الإيصالات التي قبضتها منذ آخر إقفال، والمبلغ الموجود معك (نقداً وWhish).', 'In “🧾 Cash box statement” you see every receipt since your last closing and the amount you hold (cash and Whish).', 'Dans « 🧾 Relevé de caisse » : vos reçus depuis la dernière clôture et le montant détenu.'],
      ['عند تسليم المال: عُدّ النقود أولاً وقارنها بالمبلغ الظاهر.', 'When handing over: count the cash first and compare it with the amount shown.', 'Avant la remise : comptez l’argent et comparez.'],
      ['سلّم المال للمدير، ثم اضغط «🔒 إقفال صندوقي وطباعة التقرير» وأكّد (أو يستلم المدير منك من عنده). يُطبع «تقرير إقفال صندوق» بكل الإيصالات والمبلغ المسلّم.', 'Hand the money to the manager, then tap “🔒 Close my box and print the report” and confirm (or the manager receives it from their side). A closing report lists all receipts and the amount handed.', 'Remettez l’argent au gérant puis « 🔒 Clôturer ma caisse » (ou le gérant la reçoit de son côté). Un rapport de clôture est imprimé.'],
      ['بعد الإقفال يصبح صندوقك صفراً ويبدأ حساب جديد.', 'After closing your box returns to zero and a new period starts.', 'Après clôture votre caisse revient à zéro.']
    ],
    k: [
      ['إذا كان المال الذي معك لا يطابق الرقم، لا تُقفل — أخبر المدير أولاً.', 'If your cash doesn’t match the figure, don’t close — tell the manager first.', 'Si l’argent ne correspond pas, ne clôturez pas — prévenez le gérant.']
    ] },
  { id: 'unpaid', who: ['collector', 'reader'], ic: '⏳',
    t: ['الزبائن الذين لم يدفعوا بعد', 'Customers who have not paid', 'Clients n’ayant pas payé'],
    s: [
      ['تبويب «⏳ الزبائن الذين لم يدفعوا بعد» يعرض كل من عليه دين مع عدد الأشهر والمبلغ.', '“⏳ Customers who have not paid yet” lists everyone who owes, with months and amount.', '« ⏳ Clients n’ayant pas payé » liste les débiteurs avec mois et montant.'],
      ['استعمل فلتر المنطقة والترتيب لتنظيم جولتك، واضغط على الزبون لفتح صفحته والقبض منه.', 'Use the area filter and sorting to plan your round; tap a customer to open them and collect.', 'Filtrez par zone et triez pour votre tournée ; touchez un client pour encaisser.']
    ] },
  { id: 'baddebt', who: ['collector'], ic: '📉',
    t: ['الديون المعدومة والتقسيط', 'Bad debts and installments', 'Créances douteuses et échéances'],
    s: [
      ['تبويب «📉 زبائن الديون المعدومة» يعرض الزبائن الذين وضعهم المدير على نظام تقسيط.', '“📉 Bad-debt customers” shows customers the manager put on an installment plan.', '« 📉 Créances douteuses » : clients en plan d’échéances.'],
      ['يمكنك قبض أي مبلغ أو دفعة من مخطط التقسيط، تماماً مثل القبض العادي، ويصدر إيصال.', 'You can collect any amount or one installment, just like a normal payment; a receipt is issued.', 'Encaissez un montant ou une échéance comme un paiement normal ; un reçu est émis.']
    ] },
  { id: 'switch', who: ['cut'], ic: '🔌',
    t: ['فتح وقطع الاشتراك', 'Connecting and cutting', 'Brancher et couper'],
    s: [
      ['من تبويب «🔌 فتح/قطع اشتراك» ابحث عن الزبون أو امسح الباركود.', 'From “🔌 Connect / cut”, search or scan the customer.', 'Depuis « 🔌 Brancher / couper », cherchez ou scannez le client.'],
      ['اضغط «قطع» أو «وصل» واكتب السبب إذا وُجد، ثم أكّد. تُسجَّل العملية باسمك وتاريخها.', 'Tap “Cut” or “Connect”, add a reason if any, and confirm. It is logged with your name and date.', 'Touchez « Couper » ou « Brancher », ajoutez un motif et confirmez. L’action est journalisée.'],
      ['قد يصلك أمر قطع أو وصل من المدير عبر واتساب فيه اسم المشترك والعلبة والمنطقة؛ نفّذه ثم سجّله في البرنامج.', 'The manager may send you a cut/connect order on WhatsApp with name, box and area; do it, then record it here.', 'Le gérant peut vous envoyer un ordre par WhatsApp ; exécutez-le puis enregistrez-le.']
    ] },

  /* ================= المدير والمدير الأساسي ================= */
  { id: 'adm_home', who: ['admin'], ic: '🏠',
    t: ['الصفحة الرئيسية للمدير', 'Manager home page', 'Accueil du gérant'],
    s: [
      ['تعرض المربعات مجمّعة: العمل اليومي، الزبائن والفواتير، الصندوق والمالية، المخزون والموردون، التقارير، والإدارة.', 'Tiles are grouped: daily work, customers & bills, cash & finance, stock & suppliers, reports and administration.', 'Tuiles groupées : quotidien, clients et factures, caisse, stock, rapports, administration.'],
      ['تعرض الأرقام: الصندوق، رصيد Whish، المقبوض اليوم وهذا الشهر، وعدد الإشعارات غير المرسلة.', 'Figures shown: cash box, Whish balance, collected today and this month, unsent notices.', 'Chiffres : caisse, solde Whish, encaissé du jour et du mois, avis non envoyés.'],
      ['الرقم الأحمر على المربع يعني أن هناك عملاً ينتظرك (فواتير لم تُرسل، طلبات صيانة، سلة المحذوفات).', 'A red badge on a tile means work is waiting (unsent bills, maintenance requests, recycle bin).', 'Une pastille rouge signale du travail en attente.']
    ] },
  { id: 'adm_cust', who: ['admin'], ic: '👥',
    t: ['إدارة الزبائن', 'Managing customers', 'Gérer les clients'],
    s: [
      ['من «👥 الزبائن» أضف زبوناً جديداً: الاسم، الهاتف، الاشتراك، العلبة، المنطقة، الجابي المسؤول، والعداد الأولي أو الرصيد الافتتاحي. الباركود يُعطى تلقائياً.', 'In “👥 Customers” add a customer: name, phone, plan, box, area, collector, initial reading or opening balance. A barcode is assigned automatically.', 'Dans « 👥 Clients » ajoutez nom, téléphone, formule, boîtier, zone, encaisseur, relevé initial ou solde d’ouverture. Code-barres automatique.'],
      ['يمكن فرز الزبائن وطباعة لوائح: المفعّلون، المقطوعون، المفعّلون الذين عليهم دين، والمقطوعون الذين عليهم دين.', 'Sort and print lists: active, cut-off, active with debt, cut-off with debt.', 'Triez et imprimez : actifs, coupés, actifs endettés, coupés endettés.'],
      ['إلغاء الزبون يحرّر رقم الباركود ليُستعمل لزبون آخر، ويذهب الزبون إلى سلة المحذوفات.', 'Cancelling a customer frees their barcode and moves them to the recycle bin.', 'Annuler un client libère son code-barres et le place dans la corbeille.'],
      ['أزرار صفحة الزبون للمدير: 🏷️ حسم بكشف الحساب (السبب إجباري)، 🔔 تذكير بالدفع، ⚡ عداد مقطوع، 🔢 تعديل العداد، 🗑️ إلغاء عداد، ونقله إلى الديون المعدومة.', 'Manager buttons on the customer page: 🏷️ statement discount (reason required), 🔔 payment reminder, ⚡ monthly allowance, 🔢 edit reading, 🗑️ cancel a reading, move to bad debt.', 'Boutons gérant : 🏷️ remise, 🔔 rappel, ⚡ forfait, 🔢 corriger relevé, 🗑️ annuler relevé, créance douteuse.'],
      ['«⚡ عداد مقطوع»: عدد كيلوات شهري لا يُحسب على الزبون. مثال: الاستهلاك 240 والمقطوع 150 فيُحسب 90 فقط.', '“⚡ Monthly allowance”: kWh not billed each month. Example: 240 used, 150 allowance → 90 billed.', '« ⚡ Forfait » : kWh non facturés chaque mois. Ex. 240 consommés, 150 de forfait → 90 facturés.'],
      ['«🔔 تذكير بالدفع» يرسل للزبون رسالة بالأشهر والمبلغ المستحق، ويمكن إرساله أكثر من مرة.', '“🔔 Payment reminder” sends the months and amount due; it can be sent again.', '« 🔔 Rappel » envoie les mois et le montant dû ; renvoyable.']
    ] },
  { id: 'adm_read', who: ['admin'], ic: '🔢',
    t: ['العدادات: الأخذ والتعديل والإلغاء', 'Readings: take, edit, cancel', 'Relevés : saisir, corriger, annuler'],
    s: [
      ['المدير يستطيع أخذ العداد في أي وقت، حتى خارج فترة أخذ العدادات، ويستطيع أخذ عداد الدورة التالية أو قراءة «تصفية حساب».', 'Managers can read any time, even outside the period, including next cycle or a settlement reading.', 'Le gérant peut relever à tout moment, y compris le cycle suivant ou un relevé de solde.'],
      ['«🔢 تعديل العداد» من صفحة الزبون: صحّح العداد السابق أو الحالي لآخر قراءة؛ تُعاد حساب الفاتورة والرصيد وتُكتب ملاحظة بمن عدّل.', '“🔢 Edit reading”: fix the previous or current value of the latest reading; the bill and balance are recalculated and logged.', '« 🔢 Corriger » : ajustez précédent ou actuel du dernier relevé ; facture et solde recalculés.'],
      ['«🗑️ إلغاء عداد» لأي دورة: تُلغى الفاتورة معه ويرجع الرصيد، ويمكن أخذه من جديد. إلغاء عداد ليس الأخير يعني أن استهلاك تلك الدورة لن يُحسب.', '“🗑️ Cancel a reading” for any cycle: its bill is cancelled and the balance restored. Cancelling a non-latest reading means that cycle’s usage is not billed.', '« 🗑️ Annuler » pour tout cycle : facture annulée, solde rétabli. Un relevé non récent ne sera plus facturé.'],
      ['«🗓️ جدول عدادات الشهر»: اختر الدورة لترى كل العدادات مع الصورة والمسافة، وتحتها لائحة «زبائن لم يُؤخذ عدادهم بعد» مع الطباعة والتصدير.', '“🗓️ Monthly readings”: pick a cycle to see all readings with photo and distance, plus the “not read yet” list with print and export.', '« 🗓️ Relevés du mois » : relevés avec photo et distance, plus la liste « non relevés » imprimable.'],
      ['«تحديد الفترات» في صفحة أخذ العداد: حدّد لكل شهر تاريخ بداية ونهاية أخذ العدادات للجباة.', '“Set periods” on the read page: set the start and end date of readings for each month.', '« Définir les périodes » : dates de début et fin des relevés pour chaque mois.']
    ] },
  { id: 'adm_prices', who: ['admin'], ic: '⚡',
    t: ['الاشتراكات وتسعيرة الشهر', 'Plans and monthly price', 'Formules et prix mensuel'],
    s: [
      ['من «⚡ الاشتراكات والأسعار» أنشئ الاشتراكات: بالعداد (رسم ثابت + سعر الكيلو) أو مقطوع شهري (مبلغ ثابت).', 'In “⚡ Plans & prices” create plans: metered (fixed fee + kWh price) or flat monthly.', 'Dans « ⚡ Formules » : au compteur (frais fixe + prix kWh) ou forfait mensuel.'],
      ['حدّد «تسعيرة الشهر» لكل دورة. الفواتير المحسوبة تلقائياً تُعاد حسابها عند تغيير التسعيرة.', 'Set the “monthly price” for each cycle; automatically priced bills are recalculated when it changes.', 'Fixez le « prix du mois » ; les factures automatiques sont recalculées.'],
      ['سعر صرف الليرة والتقريب والعملة الأساسية من «⚙️ الإعدادات».', 'LBP exchange rate, rounding and main currency are in “⚙️ Settings”.', 'Taux LBP, arrondi et devise dans « ⚙️ Paramètres ».']
    ] },
  { id: 'adm_send', who: ['admin'], ic: '📨',
    t: ['إرسال الفواتير والتذكيرات', 'Sending bills and reminders', 'Envoi des factures et rappels'],
    s: [
      ['«📨 إرسال قيمة الفاتورة»: يرسل لكل زبون قيمة فاتورته الجديدة عبر واتساب.', '“📨 Send bill amount” sends each customer their new bill by WhatsApp.', '« 📨 Envoyer le montant » : chaque client reçoit sa facture par WhatsApp.'],
      ['«📲 إشعارات الدفع»: إرسال الإيصالات التي لم تُرسل بعد.', '“📲 Payment notices” sends receipts not yet sent.', '« 📲 Avis de paiement » : reçus non encore envoyés.'],
      ['من «⏳ الزبائن الذين لم يدفعوا بعد» يمكن إرسال رسالة تذكير لمنطقة محددة دفعة واحدة، وتعديل نص الرسالة.', 'From “⏳ Not paid yet” you can remind a whole area at once and edit the message text.', 'Depuis « ⏳ Non payés » : rappel groupé par zone, texte modifiable.']
    ] },
  { id: 'adm_pay', who: ['admin'], ic: '🧾',
    t: ['القبض والإيصالات والمبيعات', 'Payments, receipts and sales', 'Encaissements, reçus et ventes'],
    s: [
      ['المدير يقبض مثل الجابي من «💵 القبض» أو من صفحة الزبون.', 'Managers collect like collectors, from “💵 Collect” or the customer page.', 'Le gérant encaisse comme l’encaisseur.'],
      ['إلغاء إيصال أو فاتورة: من كشف حساب الزبون، زر الإلغاء. يرجع الرصيد ويذهب السطر إلى سلة المحذوفات.', 'Cancel a receipt or bill from the customer statement; the balance is restored and the line goes to the recycle bin.', 'Annulez un reçu ou une facture depuis le relevé ; solde rétabli, ligne à la corbeille.'],
      ['«🧾 فاتورة مبيعات وإيصال قبض»: بيع قطع من المخزون لزبون مع قبض ثمنها أو تسجيلها ديناً عليه.', '“🧾 Sales invoice & receipt”: sell stock items to a customer, paid now or added to their balance.', '« 🧾 Facture de vente » : vendre du stock, payé ou à crédit.']
    ] },
  { id: 'adm_disc', who: ['admin'], ic: '🏷️',
    t: ['الحسومات', 'Discounts', 'Remises'],
    s: [
      ['من «🏷️ الحسومات» حسم دائم لزبون: مبلغ ثابت أو نسبة مئوية تُطبّق على كل فاتورة جديدة. حسم 100% يجعل حسابه صفراً.', 'In “🏷️ Discounts” a permanent discount: fixed amount or percentage on every new bill. 100% makes the account zero.', 'Remise permanente : montant ou pourcentage sur chaque facture. 100 % = compte à zéro.'],
      ['حسم لمرة واحدة على فاتورة معيّنة: اختر الزبون والفاتورة ثم «مبلغ ثابت» أو «نسبة مئوية».', 'One-time discount on a bill: pick the customer and bill, then “fixed amount” or “percentage”.', 'Remise unique : client, facture, puis montant ou pourcentage.'],
      ['الزبون الذي عليه حسم تظهر بجانب اسمه علامة 🏷️، وتظهر اللائحة الكاملة في أسفل الصفحة.', 'Customers with a discount show 🏷️; the full list is at the bottom of the page.', 'Les clients avec remise affichent 🏷️ ; liste en bas de page.']
    ] },
  { id: 'adm_bad', who: ['admin'], ic: '📉',
    t: ['الديون المعدومة', 'Bad debts', 'Créances douteuses'],
    s: [
      ['انقل الزبون إلى الديون المعدومة من صفحته؛ يخرج من لوائح الديون العادية.', 'Move a customer to bad debt from their page; they leave the normal debt lists.', 'Passez un client en créance douteuse ; il quitte les listes de dettes.'],
      ['من «📉 زبائن الديون المعدومة» أنشئ مخطط تقسيط (عدد الدفعات والمبالغ) وأضف حسماً إذا لزم. الجباة يستطيعون رؤية هذه الحسابات والقبض منها.', 'In “📉 Bad-debt customers” create an installment plan and add a discount if needed. Collectors can see and collect.', 'Créez un plan d’échéances et une remise si besoin ; les encaisseurs peuvent encaisser.']
    ] },
  { id: 'adm_boxes', who: ['admin'], ic: '💰',
    t: ['الصناديق والاستلام من الجباة', 'Cash boxes and receiving from collectors', 'Caisses et remises des encaisseurs'],
    s: [
      ['كل جابي له صندوق؛ عندما يُقفل صندوقه ويختارك، ينتقل المبلغ إلى صندوقك.', 'Each collector has a box; when they close it to you, the amount moves into your box.', 'Chaque encaisseur a une caisse ; à sa clôture vers vous, le montant passe dans la vôtre.'],
      ['«🧑‍💼 كشف حساب الجابي»: اختر الجابي لترى إيصالاته وإقفالاته، واضغط «📥 استلام من الجابي» عندما يسلّمك المال فيُقفل صندوقه إلى صندوقك.', '“🧑‍💼 Collector statement”: pick a collector to see receipts and closings; you can receive from them directly.', '« 🧑‍💼 Relevé encaisseur » : reçus et clôtures ; vous pouvez recevoir directement.'],
      ['«🧾 كشف حساب الصندوق»: صندوقك أنت؛ إقفاله يسلّم المبلغ إلى الصندوق الأساسي.', '“🧾 Cash box statement”: your own box; closing it hands the amount to the main box.', '« 🧾 Relevé de caisse » : votre caisse ; sa clôture la remet à la caisse principale.'],
      ['«🟣 كشف حساب Whish»: كل ما دُفع عبر Whish والسحوبات.', '“🟣 Whish statement”: all Whish payments and withdrawals.', '« 🟣 Relevé Whish » : paiements et retraits Whish.'],
      ['سندات الصرف من الصندوق (موردون، مصاريف، معاشات) تنقص من صندوقك، ويمكن اختيار «من Whish» أو «مدفوع من خارج الصندوق».', 'Payment vouchers (suppliers, expenses, salaries) reduce your box; you can choose “from Whish” or “paid outside the box”.', 'Les bons de paiement réduisent votre caisse ; option « Whish » ou « hors caisse ».']
    ] },
  { id: 'adm_stock', who: ['admin'], ic: '📦',
    t: ['المخزون والموردون والمصاريف', 'Stock, suppliers and expenses', 'Stock, fournisseurs et dépenses'],
    s: [
      ['«📦 المخزون»: القطع مع الكمية والسعر؛ عدّل الكمية عند الشراء أو الجرد.', '“📦 Stock”: items with quantity and price; adjust quantities on purchase or count.', '« 📦 Stock » : articles, quantités et prix.'],
      ['«🚚 الموردون»: فواتير المشتريات وسندات الدفع وكشف حساب كل مورد.', '“🚚 Suppliers”: purchase invoices, payments and each supplier’s statement.', '« 🚚 Fournisseurs » : achats, paiements et relevés.'],
      ['«🧾 المصاريف» و«👷 المعاشات»: سجّل كل مصروف ومعاش ليظهر في التقارير.', '“🧾 Expenses” and “👷 Salaries”: record every expense and salary so reports are correct.', '« 🧾 Dépenses » et « 👷 Salaires » : enregistrez tout.'],
      ['«🛡️ التأمينات»: مبالغ التأمين التي يدفعها الزبون عند توصيل خط جديد.', '“🛡️ Deposits”: deposits customers pay for a new connection.', '« 🛡️ Cautions » : cautions pour nouveau branchement.'],
      ['«🔧 طلبات الصيانة»: الطلبات التي ترسلها الزبائن عبر واتساب؛ غيّر حالتها عند إنجازها.', '“🔧 Maintenance requests”: requests sent by customers on WhatsApp; update their status when done.', '« 🔧 Maintenance » : demandes WhatsApp ; changez l’état une fois faites.']
    ] },
  { id: 'adm_staff', who: ['admin'], ic: '🧑‍🔧',
    t: ['الموظفون والصلاحيات', 'Staff and permissions', 'Personnel et droits'],
    s: [
      ['من «🧑‍🔧 الموظفون» أضف موظفاً واختر نوعه: مدير، جابي (قبض + قطع)، موظف أخذ عداد، أو صلاحيات مخصّصة.', 'In “🧑‍🔧 Staff” add a member and choose: manager, collector (collect + cut), meter reader, or custom.', 'Ajoutez un employé : gérant, encaisseur, releveur ou personnalisé.'],
      ['ضع رقم هاتف الموظف ليصله أمر القطع والوصل عبر واتساب.', 'Add the staff phone number so cut/connect orders reach them on WhatsApp.', 'Ajoutez le téléphone pour les ordres WhatsApp.'],
      ['أوقف حساب الموظف الذي ترك العمل بدلاً من حذفه، ليبقى اسمه على إيصالاته القديمة.', 'Deactivate staff who leave instead of deleting them, so their name stays on old receipts.', 'Désactivez plutôt que supprimer.']
    ] },
  { id: 'adm_reports', who: ['admin'], ic: '📊',
    t: ['التقارير', 'Reports', 'Rapports'],
    s: [
      ['«📊 الكشف الشهري العام»: الفواتير والمقبوضات والديون لكل شهر.', '“📊 Monthly report”: bills, collections and debts per month.', '« 📊 Rapport mensuel » : factures, encaissements et dettes.'],
      ['كشف جميع الديون لا يشمل الديون المعدومة ولا الزبائن الذين عليهم حسم 100%.', 'The all-debts statement excludes bad debts and 100% discounted customers.', 'Le relevé des dettes exclut créances douteuses et remises 100 %.'],
      ['يمكن طباعة معظم الصفحات أو تصديرها إلى Excel من زر «طباعة» أو «تصدير».', 'Most pages can be printed or exported to Excel.', 'La plupart des pages s’impriment ou s’exportent.']
    ] },
  { id: 'adm_trash', who: ['admin'], ic: '🗑️',
    t: ['سلة المحذوفات', 'Recycle bin', 'Corbeille'],
    s: [
      ['كل ما يُلغى (زبون، فاتورة، إيصال، عداد، حركة) يذهب إلى «🗑️ سلة المحذوفات» ويمكن استرجاعه منها.', 'Everything cancelled (customer, bill, receipt, reading, move) goes to the recycle bin and can be restored.', 'Tout ce qui est annulé va à la corbeille et peut être restauré.'],
      ['تفريغ السلة يحذف نهائياً ولا يمكن التراجع عنه — لا تفرغها إلا عند التأكد.', 'Emptying the bin deletes permanently — only do it when sure.', 'Vider la corbeille supprime définitivement.']
    ] },
  { id: 'adm_backup', who: ['admin'], ic: '💾',
    t: ['النسخ الاحتياطي', 'Backups', 'Sauvegardes'],
    s: [
      ['إذا كان Google Drive مربوطاً، يأخذ البرنامج نسخة احتياطية كاملة تلقائياً كل ساعة دون أن يظهر شيء؛ تُحفظ نسخ آخر 48 ساعة ثم نسخة واحدة لكل يوم لمدة 30 يوماً.', 'With Google Drive linked, a full backup is taken automatically every hour; the last 48 hours are kept, then one per day for 30 days.', 'Avec Google Drive, sauvegarde complète automatique chaque heure ; 48 h conservées puis une par jour pendant 30 jours.'],
      ['من «⚙️ الإعدادات ← النسخ الاحتياطي» يمكن تنزيل نسخة على الكمبيوتر في أي وقت.', 'From “⚙️ Settings → Backup” you can download a copy anytime.', 'Depuis « ⚙️ Paramètres → Sauvegarde » : téléchargement à tout moment.'],
      ['«➕ إضافة الناقص من نسخة» آمن: يضيف فقط ما ليس موجوداً ولا يمسح شيئاً.', '“➕ Add missing from a backup” is safe: it only adds what is missing and deletes nothing.', '« ➕ Ajouter les manquants » est sûr : n’ajoute que le manquant.']
    ] },

  /* ================= المدير الأساسي فقط ================= */
  { id: 'main_only', who: ['main'], ic: '🛡️',
    t: ['خاص بالمدير الأساسي', 'Main manager only', 'Gérant principal uniquement'],
    s: [
      ['«💰 الصندوق الأساسي»: المال الذي يسلّمه المدراء، وحركاته.', '“💰 Main cash box”: money handed by managers, and its moves.', '« 💰 Caisse principale » : remises des gérants.'],
      ['«🧑‍💻 لوحة المدير»: مجموع كل الصناديق لكل يوم، وتعديل أرصدة الصناديق وWhish عند وجود خطأ.', '“🧑‍💻 Manager dashboard”: all boxes per day, and correcting box and Whish balances when wrong.', '« 🧑‍💻 Tableau » : caisses par jour, correction des soldes.'],
      ['«📒 اليومية» و«📒 دليل الحسابات» و«⚖️ الميزانية» (يمكن تعديل أرقامها) و«📈 التقرير الشهري».', '“📒 Journal”, “📒 Chart of accounts”, “⚖️ Balance sheet” (editable) and “📈 Monthly report”.', '« Journal », « Plan comptable », « Bilan » (modifiable) et « Rapport mensuel ».'],
      ['«🗺️ مواقع الموظفين»: آخر مكان أخذ فيه كل موظف عداداً أو قبض.', '“🗺️ Staff map”: where each staff member last read or collected.', '« 🗺️ Carte » : derniers emplacements du personnel.'],
      ['المورّدون والمصاريف «الخاصة» لا تظهر إلا للمدير الأساسي.', '“Private” suppliers and expenses are visible only to the main manager.', 'Les fournisseurs « privés » ne sont visibles que du gérant principal.']
    ],
    k: [
      ['⚠️ «♻️ استرجاع نسخة احتياطية» يمسح كل بيانات البرنامج ثم يرجعها من الملف. لا تستعمله إلا إذا طُلب منك ذلك؛ لإرجاع شيء ناقص استعمل «➕ إضافة الناقص من نسخة».', '⚠️ “♻️ Restore backup” wipes all data then reloads it from the file. Don’t use it unless asked; to bring back missing items use “➕ Add missing from a backup”.', '⚠️ « ♻️ Restaurer » efface tout puis recharge le fichier. Préférez « ➕ Ajouter les manquants ».']
    ] }
];
