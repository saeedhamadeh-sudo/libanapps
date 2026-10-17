/* ============================================================
   LibanApps Club — shared code (inlined into club pages by tools/club/build.js)
   i18n · formatting · subscription status · CR80 card · PDF · face recognition · dialogs
   ============================================================ */
var CLUB = (function () {
  'use strict';

  /* ---------------- i18n ---------------- */
  var DICT = {
    close: ['إغلاق', 'Close', 'Fermer'],
    cancel: ['إلغاء', 'Cancel', 'Annuler'],
    save: ['حفظ', 'Save', 'Enregistrer'],
    saving: ['جارٍ الحفظ…', 'Saving…', 'Enregistrement…'],
    loading: ['جارٍ التحميل…', 'Loading…', 'Chargement…'],
    please_wait: ['انتظر قليلاً…', 'Please wait…', 'Veuillez patienter…'],
    error: ['حدث خطأ', 'An error occurred', 'Une erreur est survenue'],
    no_connection: ['تعذّر الاتصال بالإنترنت', 'No internet connection', 'Pas de connexion Internet'],
    yes: ['نعم', 'Yes', 'Oui'],
    no: ['لا', 'No', 'Non'],
    st_active: ['فعّال', 'Active', 'Actif'],
    st_expiring: ['ينتهي قريبًا', 'Expiring soon', 'Expire bientôt'],
    st_expired: ['منتهٍ', 'Expired', 'Expiré'],
    st_none: ['بلا اشتراك', 'No subscription', 'Sans abonnement'],
    st_inactive: ['موقوف', 'Inactive', 'Inactif'],
    days_left: ['{n} يوم متبقٍ', '{n} days left', '{n} jours restants'],
    day_left_1: ['يوم واحد متبقٍ', '1 day left', '1 jour restant'],
    overdue_days: ['متأخر {n} يوم', '{n} days overdue', 'En retard de {n} jours'],
    owed: ['مستحق: {v}', 'Due: {v}', 'Dû : {v}'],
    paid_up: ['خالص', 'Paid up', 'À jour'],
    paid_until: ['مدفوع حتى', 'Paid until', 'Payé jusqu’au'],
    member_since: ['عضو منذ', 'Member since', 'Membre depuis'],
    level: ['المستوى', 'Level', 'Niveau'],
    group: ['الفرقة', 'Group', 'Groupe'],
    card_scan: ['امسح البطاقة عند الباب', 'Scan this card at the door', 'Scannez cette carte à l’entrée'],
    card_member: ['بطاقة عضوية', 'Membership card', 'Carte de membre'],
    card_found: ['في حال العثور على البطاقة يُرجى إعادتها إلى النادي', 'If found, please return to the club', 'En cas de perte, merci de la rapporter au club'],
    medal_gold: ['ذهبية', 'Gold', 'Or'],
    medal_silver: ['فضية', 'Silver', 'Argent'],
    medal_bronze: ['برونزية', 'Bronze', 'Bronze'],
    medal_participation: ['مشاركة', 'Participation', 'Participation'],
    medal_other: ['أخرى', 'Other', 'Autre'],
    m_cash: ['نقدًا', 'Cash', 'Espèces'],
    m_whish: ['Whish', 'Whish', 'Whish'],
    m_card: ['بطاقة', 'Card', 'Carte'],
    m_transfer: ['تحويل', 'Transfer', 'Virement'],
    m_other: ['أخرى', 'Other', 'Autre'],
    face_loading: ['جارٍ تحميل نظام التعرّف على الوجه…', 'Loading face recognition…', 'Chargement de la reconnaissance faciale…'],
    face_failed: ['تعذّر تحميل نظام التعرّف على الوجه', 'Could not load face recognition', 'Impossible de charger la reconnaissance faciale']
  };
  var LANGS = ['ar', 'en', 'fr'];
  var lang = 'ar';
  var storeKey = 'club_lang';

  function add(d) { for (var k in d) DICT[k] = d[k]; }
  function initLang(fallback) {
    var saved = null;
    try { saved = localStorage.getItem(storeKey); } catch (e) {}
    var q = (new URLSearchParams(location.search)).get('lang');
    lang = LANGS.indexOf(q) >= 0 ? q : (LANGS.indexOf(saved) >= 0 ? saved : (LANGS.indexOf(fallback) >= 0 ? fallback : 'ar'));
    applyDir();
    return lang;
  }
  function setLang(l) {
    if (LANGS.indexOf(l) < 0) return;
    lang = l;
    try { localStorage.setItem(storeKey, l); } catch (e) {}
    applyDir();
  }
  function applyDir() {
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === 'ar' ? 'rtl' : 'ltr';
  }
  function t(key, vars) {
    var row = DICT[key];
    var s = row ? (row[LANGS.indexOf(lang)] || row[1] || row[0]) : key;
    if (vars) for (var v in vars) s = s.split('{' + v + '}').join(vars[v]);
    return s;
  }
  function applyAll(root) {
    (root || document).querySelectorAll('[data-t]').forEach(function (el) { el.textContent = t(el.getAttribute('data-t')); });
    (root || document).querySelectorAll('[data-tp]').forEach(function (el) { el.setAttribute('placeholder', t(el.getAttribute('data-tp'))); });
    (root || document).querySelectorAll('[data-tt]').forEach(function (el) { el.setAttribute('title', t(el.getAttribute('data-tt'))); el.setAttribute('aria-label', t(el.getAttribute('data-tt'))); });
  }

  /* ---------------- formatting ---------------- */
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function locale() { return lang === 'ar' ? 'ar-LB-u-nu-latn' : (lang === 'fr' ? 'fr-FR' : 'en-GB'); }
  function parseDate(d) {
    if (!d) return null;
    if (d instanceof Date) return d;
    var m = String(d).match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (m) return new Date(+m[1], +m[2] - 1, +m[3], 12);
    return new Date(d);
  }
  function fmtDate(d) {
    var x = parseDate(d); if (!x || isNaN(x)) return '—';
    return x.toLocaleDateString(locale(), { day: '2-digit', month: 'short', year: 'numeric' });
  }
  function fmtTime(d) {
    var x = parseDate(d); if (!x || isNaN(x)) return '';
    return x.toLocaleTimeString(locale(), { hour: '2-digit', minute: '2-digit' });
  }
  function fmtDateTime(d) { return fmtDate(d) + ' · ' + fmtTime(d); }
  function money(v, sym) {
    var n = Number(v || 0);
    var s = n.toLocaleString('en-US', { minimumFractionDigits: n % 1 ? 2 : 0, maximumFractionDigits: 2 });
    sym = sym == null ? '$' : sym;
    return sym === '$' ? '$' + s : s + ' ' + sym;
  }
  function todayIn(tz) {
    try { return new Intl.DateTimeFormat('en-CA', { timeZone: tz || 'Asia/Beirut', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date()); }
    catch (e) { var d = new Date(); return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }
  }
  function pad(n) { return (n < 10 ? '0' : '') + n; }
  function iso(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }
  function daysBetween(a, b) { return Math.round((parseDate(b) - parseDate(a)) / 86400000); }
  function addMonths(isoDate, m) {
    var d = parseDate(isoDate); var day = d.getDate();
    d.setDate(1); d.setMonth(d.getMonth() + m);
    var last = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
    d.setDate(Math.min(day, last));
    return iso(d);
  }
  function addDays(isoDate, n) { var d = parseDate(isoDate); d.setDate(d.getDate() + n); return iso(d); }

  /* نفس منطق _club_status بالداتابيس */
  function status(paidUntil, fee, today, expiring, grace) {
    fee = Number(fee || 0);
    if (!paidUntil) return { state: 'none', days_left: 0, overdue_days: 0, owed_months: 1, owed: fee, door_ok: false };
    var d = daysBetween(today, paidUntil);
    if (d >= 0) return { state: d < (expiring == null ? 5 : expiring) ? 'expiring' : 'active', days_left: d + 1, overdue_days: 0, owed_months: 0, owed: 0, door_ok: true };
    var a = parseDate(paidUntil), b = parseDate(today);
    var months = (b.getFullYear() - a.getFullYear()) * 12 + (b.getMonth() - a.getMonth());
    var probe = new Date(a); probe.setMonth(probe.getMonth() + months);
    if (probe > b) { months -= 1; }
    var anchor = new Date(a); anchor.setMonth(anchor.getMonth() + months);
    if (iso(anchor) !== iso(b)) months += 1;
    months = Math.max(1, months);
    return { state: 'expired', days_left: 0, overdue_days: -d, owed_months: months, owed: Math.round(months * fee * 100) / 100, door_ok: d >= -(grace || 0) };
  }
  function statusLabel(s) {
    if (!s) return '';
    if (s.state === 'active' || s.state === 'expiring') return s.days_left === 1 ? t('day_left_1') : t('days_left', { n: s.days_left });
    if (s.state === 'expired') return t('overdue_days', { n: s.overdue_days });
    return t('st_none');
  }
  function stateName(st) { return t('st_' + st); }

  /* ---------------- images ---------------- */
  function imgUrl(u, w) {
    if (!u) return '';
    var m = String(u).match(/\/storage\/v1\/object\/public\/(.+)$/);
    if (!m) return u;
    return '/img/' + m[1] + (w ? '?w=' + w : '');
  }
  function loadImg(url) {
    return new Promise(function (res) {
      if (!url) return res(null);
      var im = new Image();
      if (/^https?:/i.test(url) && url.indexOf(location.origin) !== 0) im.crossOrigin = 'anonymous';
      im.onload = function () { res(im); };
      im.onerror = function () { res(null); };
      im.src = url;
    });
  }
  function initials(name) {
    var p = String(name || '').trim().split(/\s+/);
    return ((p[0] || '').charAt(0) + (p.length > 1 ? p[p.length - 1].charAt(0) : '')).toUpperCase();
  }
  function shade(hex, amt) {
    var h = String(hex || '#0f766e').replace('#', '');
    if (h.length === 3) h = h.split('').map(function (c) { return c + c; }).join('');
    var n = parseInt(h, 16); if (isNaN(n)) n = 0x0f766e;
    var r = Math.max(0, Math.min(255, (n >> 16) + amt)), g = Math.max(0, Math.min(255, ((n >> 8) & 255) + amt)), b = Math.max(0, Math.min(255, (n & 255) + amt));
    return '#' + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
  }
  function readable(hex) {
    var h = String(hex || '').replace('#', ''); if (h.length === 3) h = h.split('').map(function (c) { return c + c; }).join('');
    var n = parseInt(h, 16); if (isNaN(n)) return '#fff';
    var r = n >> 16, g = (n >> 8) & 255, b = n & 255;
    return (r * 299 + g * 587 + b * 114) / 1000 > 150 ? '#111827' : '#ffffff';
  }

  /* ---------------- QR ---------------- */
  function qrMatrix(text) { return ClubQR(text, 'M'); }
  function drawQr(ctx, text, x, y, size, dark) {
    var m = qrMatrix(text), n = m.length, q = 2, cell = size / (n + q * 2);
    ctx.fillStyle = '#ffffff'; ctx.fillRect(x, y, size, size);
    ctx.fillStyle = dark || '#000000';
    for (var r = 0; r < n; r++) for (var c = 0; c < n; c++) if (m[r][c])
      ctx.fillRect(Math.floor(x + (c + q) * cell), Math.floor(y + (r + q) * cell), Math.ceil(cell), Math.ceil(cell));
  }
  function qrPayload(token) { return 'LA-CLUB:' + token; }
  function qrSvg(text, px) {
    var m = qrMatrix(text), n = m.length, q = 2, s = n + q * 2, d = '';
    for (var r = 0; r < n; r++) for (var c = 0; c < n; c++) if (m[r][c]) d += 'M' + (c + q) + ' ' + (r + q) + 'h1v1h-1z';
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + s + ' ' + s + '" width="' + (px || 160) + '" height="' + (px || 160) + '" shape-rendering="crispEdges"><rect width="100%" height="100%" fill="#fff"/><path d="' + d + '" fill="#000"/></svg>';
  }

  /* ---------------- CR80 card (85.6 × 54 mm @ 300 dpi) ---------------- */
  var CW = 1011, CH = 638;
  var FONT = "'Cairo', 'Segoe UI', Tahoma, Arial, sans-serif";
  function rr(ctx, x, y, w, h, r) {
    ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
  }
  function fit(ctx, text, maxW, size, weight, min) {
    var s = size;
    do { ctx.font = (weight || 700) + ' ' + s + 'px ' + FONT; if (ctx.measureText(text).width <= maxW) break; s -= 2; } while (s > (min || 18));
    return s;
  }
  function ellip(ctx, text, maxW) {
    text = String(text || '');
    if (ctx.measureText(text).width <= maxW) return text;
    while (text.length > 1 && ctx.measureText(text + '…').width > maxW) text = text.slice(0, -1);
    return text + '…';
  }
  async function fontsReady() {
    try { if (document.fonts) { await document.fonts.load('700 40px Cairo'); await document.fonts.load('400 30px Cairo'); await document.fonts.ready; } } catch (e) {}
  }
  function coverDraw(ctx, img, x, y, w, h) {
    var s = Math.max(w / img.width, h / img.height), sw = w / s, sh = h / s;
    ctx.drawImage(img, (img.width - sw) / 2, Math.max(0, (img.height - sh) / 2 - (img.height - sh) * 0.15), sw, sh, x, y, w, h);
  }
  function containDraw(ctx, img, x, y, w, h) {
    var s = Math.min(w / img.width, h / img.height), dw = img.width * s, dh = img.height * s;
    ctx.drawImage(img, x + (w - dw) / 2, y + (h - dh) / 2, dw, dh);
  }

  /* d = {club, student, level, group} */
  async function renderCard(side, d) {
    await fontsReady();
    var cv = document.createElement('canvas'); cv.width = CW; cv.height = CH;
    var c = cv.getContext('2d');
    var rtl = lang === 'ar';
    var P = d.club.primary_color || '#0f766e', A = d.club.accent_color || '#f59e0b';
    var onP = readable(P);
    function X(x, w) { return rtl ? CW - x - (w || 0) : x; }
    c.textBaseline = 'alphabetic';
    c.direction = rtl ? 'rtl' : 'ltr';
    var logo = await loadImg(imgUrl(d.club.logo_url, 320));

    if (side === 'front') {
      c.fillStyle = '#ffffff'; c.fillRect(0, 0, CW, CH);
      // شريط الرأس
      var g = c.createLinearGradient(0, 0, CW, 160); g.addColorStop(0, P); g.addColorStop(1, shade(P, -40));
      c.fillStyle = g; c.fillRect(0, 0, CW, 160);
      c.fillStyle = A; c.fillRect(0, 160, CW, 8);
      // اللوغو
      var lx = X(40, 116);
      c.save(); c.beginPath(); c.arc(lx + 58, 80, 58, 0, Math.PI * 2); c.fillStyle = '#fff'; c.fill(); c.clip();
      if (logo) containDraw(c, logo, lx + 8, 30, 100, 100);
      else { c.fillStyle = P; c.font = '700 44px ' + FONT; c.textAlign = 'center'; c.fillText(initials(d.club.name), lx + 58, 96); }
      c.restore();
      // اسم النادي
      c.fillStyle = onP; c.textAlign = rtl ? 'right' : 'left';
      var tx = rtl ? CW - 180 : 180;
      fit(c, d.club.name || '', CW - 230, 46, 700, 26); c.fillText(ellip(c, d.club.name || '', CW - 230), tx, 82);
      c.font = '400 26px ' + FONT; c.globalAlpha = 0.9;
      c.fillText(ellip(c, (d.club.sport ? d.club.sport + ' · ' : '') + t('card_member'), CW - 230), tx, 124); c.globalAlpha = 1;
      // الصورة
      var px = X(44, 250), py = 200, pw = 250, ph = 310;
      c.save(); rr(c, px, py, pw, ph, 22); c.fillStyle = '#e5e7eb'; c.fill(); c.clip();
      var ph1 = await loadImg(imgUrl(d.student.photo_url, 640));
      if (ph1) coverDraw(c, ph1, px, py, pw, ph);
      else { c.fillStyle = '#9ca3af'; c.font = '700 96px ' + FONT; c.textAlign = 'center'; c.fillText(initials(d.student.full_name), px + pw / 2, py + ph / 2 + 34); }
      c.restore();
      c.lineWidth = 6; c.strokeStyle = A; rr(c, px, py, pw, ph, 22); c.stroke();
      // المعلومات
      var ix = rtl ? CW - 330 : 330, iw = CW - 330 - 44;
      c.textAlign = rtl ? 'right' : 'left'; c.fillStyle = '#111827';
      fit(c, d.student.full_name || '', iw, 52, 700, 28);
      c.fillText(ellip(c, d.student.full_name || '', iw), ix, 262);
      c.fillStyle = '#6b7280'; c.font = '600 30px ' + FONT;
      c.fillText('#' + (d.student.code || ''), ix, 308);
      var y = 350;
      if (d.level && d.level.name) {
        c.font = '700 28px ' + FONT;
        var lw = c.measureText(d.level.name).width + 44;
        var lx2 = rtl ? ix - lw : ix;
        rr(c, lx2, y, lw, 52, 26); c.fillStyle = d.level.color || P; c.fill();
        c.strokeStyle = 'rgba(0,0,0,.12)'; c.lineWidth = 2; c.stroke();
        c.fillStyle = readable(d.level.color || P); c.textAlign = 'center'; c.fillText(d.level.name, lx2 + lw / 2, y + 36);
        c.textAlign = rtl ? 'right' : 'left';
        y += 82;
      } else y += 20;
      c.fillStyle = '#374151'; c.font = '400 26px ' + FONT;
      var iw2 = iw - 150;   // مساحة للـQR الصغير بالزاوية
      if (d.group && d.group.name) { c.fillText(ellip(c, t('group') + ': ' + d.group.name, iw2), ix, y); y += 44; }
      c.fillText(ellip(c, t('member_since') + ': ' + fmtDate(d.student.joined_at), iw2), ix, y);
      // QR صغير بالزاوية (للطابعات ذات الوجه الواحد)
      var qs = 124, qx = rtl ? 40 : CW - 40 - qs;
      drawQr(c, qrPayload(d.student.card_token), qx, CH - qs - 30, qs);
      c.fillStyle = P; c.fillRect(0, CH - 18, CW, 18);
    } else {
      var g2 = c.createLinearGradient(0, 0, CW, CH); g2.addColorStop(0, shade(P, -30)); g2.addColorStop(1, P);
      c.fillStyle = g2; c.fillRect(0, 0, CW, CH);
      // زخرفة خفيفة
      c.globalAlpha = 0.08; c.fillStyle = '#fff';
      c.beginPath(); c.arc(X(CW - 120), -40, 260, 0, Math.PI * 2); c.fill();
      c.beginPath(); c.arc(X(80), CH + 60, 220, 0, Math.PI * 2); c.fill(); c.globalAlpha = 1;
      // QR كبير
      var qsz = 330, qx2 = X(56, qsz + 28), qy = (CH - qsz - 28) / 2;
      rr(c, qx2, qy, qsz + 28, qsz + 28, 24); c.fillStyle = '#fff'; c.fill();
      drawQr(c, qrPayload(d.student.card_token), qx2 + 14, qy + 14, qsz);
      // نصوص
      var bx = rtl ? CW - 56 - qsz - 28 - 44 : 56 + qsz + 28 + 44, bw = CW - (56 + qsz + 28 + 44) - 50;
      c.textAlign = rtl ? 'right' : 'left'; c.fillStyle = onP;
      if (logo) { var ls = 96; c.save(); c.beginPath(); c.arc(rtl ? bx - ls / 2 : bx + ls / 2, 120, ls / 2, 0, Math.PI * 2); c.fillStyle = '#fff'; c.fill(); c.clip(); containDraw(c, logo, (rtl ? bx - ls : bx) + 8, 120 - ls / 2 + 8, ls - 16, ls - 16); c.restore(); }
      c.fillStyle = onP;
      fit(c, d.club.name || '', bw, 40, 700, 24); c.fillText(ellip(c, d.club.name || '', bw), bx, 222);
      c.font = '600 28px ' + FONT; c.fillText(ellip(c, t('card_scan'), bw), bx, 270);
      c.font = '400 26px ' + FONT; var yy = 330;
      if (d.club.whatsapp) { c.fillText(ellip(c, '☎ \u2066+' + String(d.club.whatsapp).replace(/^\+/, '') + '\u2069', bw), bx, yy); yy += 42; }
      if (d.club.address) { c.fillText(ellip(c, d.club.address, bw), bx, yy); yy += 42; }
      c.font = '400 22px ' + FONT; c.globalAlpha = 0.85;
      var note = d.club.card_note || t('card_found');
      wrap(c, note, bx, Math.max(yy + 10, 470), bw, 30, 3); c.globalAlpha = 1;
    }
    return cv;
  }
  function wrap(c, text, x, y, maxW, lh, maxLines) {
    var words = String(text || '').split(/\s+/), line = '', n = 0;
    for (var i = 0; i < words.length; i++) {
      var test = line ? line + ' ' + words[i] : words[i];
      if (c.measureText(test).width > maxW && line) { c.fillText(line, x, y); y += lh; line = words[i]; if (++n >= maxLines - 1) { line = ellip(c, words.slice(i).join(' '), maxW); break; } }
      else line = test;
    }
    if (line) c.fillText(line, x, y);
  }

  /* ---------------- PDF (صور JPEG — بدون مكتبات خارجية) ---------------- */
  function b64ToBytes(b64) { var bin = atob(b64), u = new Uint8Array(bin.length); for (var i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return u; }
  function makePdf(pages) {
    var enc = new TextEncoder(), parts = [], offs = [], len = 0;
    function push(x) { var b = typeof x === 'string' ? enc.encode(x) : x; parts.push(b); len += b.length; }
    function obj(id, body) { offs[id] = len; push(id + ' 0 obj\n'); body(); push('\nendobj\n'); }
    var mm = 72 / 25.4, n = pages.length, kids = [];
    for (var i = 0; i < n; i++) kids.push((3 + i * 3) + ' 0 R');
    push('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
    obj(1, function () { push('<< /Type /Catalog /Pages 2 0 R >>'); });
    obj(2, function () { push('<< /Type /Pages /Kids [' + kids.join(' ') + '] /Count ' + n + ' >>'); });
    pages.forEach(function (p, i) {
      var pid = 3 + i * 3, cid = pid + 1, iid = pid + 2;
      var W = (p.wMm * mm).toFixed(2), H = (p.hMm * mm).toFixed(2);
      var jpg = b64ToBytes(p.canvas.toDataURL('image/jpeg', 0.93).split(',')[1]);
      var content = 'q ' + W + ' 0 0 ' + H + ' 0 0 cm /Im0 Do Q';
      obj(pid, function () { push('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ' + W + ' ' + H + '] /Resources << /XObject << /Im0 ' + iid + ' 0 R >> >> /Contents ' + cid + ' 0 R >>'); });
      obj(cid, function () { push('<< /Length ' + content.length + ' >>\nstream\n' + content + '\nendstream'); });
      obj(iid, function () {
        push('<< /Type /XObject /Subtype /Image /Width ' + p.canvas.width + ' /Height ' + p.canvas.height + ' /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ' + jpg.length + ' >>\nstream\n');
        push(jpg); push('\nendstream');
      });
    });
    var xref = len, total = 3 + n * 3;
    var x = 'xref\n0 ' + total + '\n0000000000 65535 f \n';
    for (var k = 1; k < total; k++) x += String(offs[k]).padStart(10, '0') + ' 00000 n \n';
    push(x + 'trailer\n<< /Size ' + total + ' /Root 1 0 R >>\nstartxref\n' + xref + '\n%%EOF');
    return new Blob(parts, { type: 'application/pdf' });
  }
  /* صفحة A4 فيها 10 بطاقات (2×5) مع علامات القص — الظهر معكوس للطباعة على الوجهين */
  function a4Sheet(cards, mirror) {
    var dpi = 300 / 25.4, W = Math.round(210 * dpi), H = Math.round(297 * dpi);
    var cw = 85.6 * dpi, ch = 54 * dpi, gx = 8 * dpi, gy = 4 * dpi;
    var ox = (W - (2 * cw + gx)) / 2, oy = (H - (5 * ch + 4 * gy)) / 2;
    var cv = document.createElement('canvas'); cv.width = W; cv.height = H;
    var c = cv.getContext('2d'); c.fillStyle = '#fff'; c.fillRect(0, 0, W, H);
    cards.forEach(function (card, i) {
      var col = i % 2, row = Math.floor(i / 2); if (mirror) col = 1 - col;
      var x = ox + col * (cw + gx), y = oy + row * (ch + gy);
      c.save(); rr(c, x, y, cw, ch, 3.18 * dpi); c.clip(); c.drawImage(card, x, y, cw, ch); c.restore();
      c.strokeStyle = '#999'; c.lineWidth = 1.5; var m = 4 * dpi;
      [[x, y], [x + cw, y], [x, y + ch], [x + cw, y + ch]].forEach(function (p) {
        c.beginPath(); c.moveTo(p[0] - m, p[1]); c.lineTo(p[0] - m / 3, p[1]); c.moveTo(p[0] + m / 3, p[1]); c.lineTo(p[0] + m, p[1]);
        c.moveTo(p[0], p[1] - m); c.lineTo(p[0], p[1] - m / 3); c.moveTo(p[0], p[1] + m / 3); c.lineTo(p[0], p[1] + m); c.stroke();
      });
    });
    return cv;
  }
  /* items = [{club, student, level, group}] · mode = 'cr80' | 'a4' */
  async function cardsPdf(items, mode, onProgress) {
    var pages = [];
    if (mode === 'a4') {
      for (var s = 0; s < items.length; s += 10) {
        var fronts = [], backs = [];
        for (var i = s; i < Math.min(items.length, s + 10); i++) {
          fronts.push(await renderCard('front', items[i])); backs.push(await renderCard('back', items[i]));
          if (onProgress) onProgress(i + 1, items.length);
        }
        pages.push({ canvas: a4Sheet(fronts, false), wMm: 210, hMm: 297 });
        pages.push({ canvas: a4Sheet(backs, true), wMm: 210, hMm: 297 });
      }
    } else {
      for (var j = 0; j < items.length; j++) {
        pages.push({ canvas: await renderCard('front', items[j]), wMm: 85.6, hMm: 54 });
        pages.push({ canvas: await renderCard('back', items[j]), wMm: 85.6, hMm: 54 });
        if (onProgress) onProgress(j + 1, items.length);
      }
    }
    return makePdf(pages);
  }
  function download(blob, name) {
    var a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name;
    document.body.appendChild(a); a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 4000);
  }

  /* ---------------- التعرّف على الوجه (face-api — يُحمَّل عند الحاجة فقط) ---------------- */
  var FACE_JS = 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@1/dist/face-api.js';
  var FACE_MODELS = 'https://cdn.jsdelivr.net/npm/@vladmandic/face-api@1/model/';
  var faceP = null;
  function loadScript(src) {
    return new Promise(function (res, rej) {
      var s = document.createElement('script'); s.src = src; s.async = true;
      s.onload = res; s.onerror = function () { rej(new Error(t('face_failed'))); };
      document.head.appendChild(s);
    });
  }
  function loadFace(opts) {
    opts = opts || {};
    if (faceP) return faceP;
    faceP = (async function () {
      if (!window.faceapi) await loadScript(FACE_JS);
      var fa = window.faceapi;
      try { await fa.tf.setBackend('webgl'); } catch (e) {}
      try { await fa.tf.ready(); } catch (e) {}
      var jobs = [fa.nets.faceLandmark68Net.loadFromUri(FACE_MODELS), fa.nets.faceRecognitionNet.loadFromUri(FACE_MODELS),
                  fa.nets.tinyFaceDetector.loadFromUri(FACE_MODELS)];
      if (opts.ssd) jobs.push(fa.nets.ssdMobilenetv1.loadFromUri(FACE_MODELS));
      await Promise.all(jobs);
      return fa;
    })();
    faceP.catch(function () { faceP = null; });
    return faceP;
  }
  /* بصمة وجه واحد من صورة أو فيديو أو canvas — يرجّع مصفوفة 128 رقم أو null */
  async function faceDescriptor(input, opts) {
    opts = opts || {};
    var fa = await loadFace({ ssd: !!opts.ssd });
    var det = opts.ssd && fa.nets.ssdMobilenetv1.isLoaded
      ? new fa.SsdMobilenetv1Options({ minConfidence: 0.45 })
      : new fa.TinyFaceDetectorOptions({ inputSize: opts.inputSize || 416, scoreThreshold: 0.45 });
    var r = await fa.detectSingleFace(input, det).withFaceLandmarks().withFaceDescriptor();
    if (!r) return null;
    return { descriptor: Array.prototype.map.call(r.descriptor, function (v) { return Math.round(v * 100000) / 100000; }), box: r.detection.box, score: r.detection.score };
  }
  function faceDist(a, b) { var s = 0; for (var i = 0; i < a.length; i++) { var d = a[i] - b[i]; s += d * d; } return Math.sqrt(s); }

  /* ---------------- dialogs (لا تُغلق عند الضغط خارجها، وقابلة للتمرير) ---------------- */
  var stack = [];
  function modal(opts) {
    var ov = document.createElement('div'); ov.className = 'cl-ov on';
    ov.innerHTML = '<div class="cl-modal' + (opts.wide ? ' wide' : '') + '" role="dialog" aria-modal="true">' +
      '<div class="cl-mh"><h3></h3><button type="button" class="cl-x" aria-label="' + esc(t('close')) + '">×</button></div>' +
      '<div class="cl-mb"></div><div class="cl-mf"></div></div>';
    ov.querySelector('h3').textContent = opts.title || '';
    var body = ov.querySelector('.cl-mb'); body.innerHTML = opts.body || '';
    var foot = ov.querySelector('.cl-mf');
    var msg = document.createElement('div'); msg.className = 'cl-msg'; body.appendChild(msg);
    var api = {
      el: ov, body: body,
      close: function () { ov.remove(); stack.splice(stack.indexOf(api), 1); document.body.classList.toggle('cl-lock', stack.length > 0); if (opts.onClose) opts.onClose(); },
      msg: function (text, kind) { msg.textContent = text || ''; msg.className = 'cl-msg' + (kind ? ' ' + kind : ''); if (text) msg.scrollIntoView({ block: 'nearest' }); },
      $: function (s) { return ov.querySelector(s); }
    };
    ov.querySelector('.cl-x').onclick = api.close;
    var closeB = document.createElement('button'); closeB.type = 'button'; closeB.className = 'cl-btn ghost'; closeB.textContent = opts.cancelText || t(opts.onSave ? 'cancel' : 'close'); closeB.onclick = api.close;
    foot.appendChild(closeB);
    (opts.buttons || []).forEach(function (b) {
      var x = document.createElement('button'); x.type = 'button'; x.className = 'cl-btn ' + (b.cls || 'alt'); x.textContent = b.text;
      x.onclick = function () { b.onClick(api, x); }; foot.appendChild(x);
    });
    if (opts.onSave) {
      var sv = document.createElement('button'); sv.type = 'button'; sv.className = 'cl-btn ' + (opts.saveCls || ''); sv.textContent = opts.saveText || t('save');
      sv.onclick = async function () {
        sv.disabled = true; api.msg(t('saving'));
        try { var r = await opts.onSave(api); if (r !== false) api.close(); else sv.disabled = false; }
        catch (e) { api.msg(errText(e), 'e'); sv.disabled = false; }
      };
      foot.appendChild(sv); api.saveBtn = sv;
    }
    document.body.appendChild(ov); stack.push(api); document.body.classList.add('cl-lock');
    if (opts.onOpen) opts.onOpen(api);
    return api;
  }
  function confirmBox(text, okText, danger) {
    return new Promise(function (res) {
      var done = false;
      var m = modal({ title: text, body: '', saveText: okText || t('yes'), saveCls: danger ? 'danger' : '', onSave: function () { done = true; res(true); }, onClose: function () { if (!done) res(false); } });
      m.body.style.display = 'none';
    });
  }
  function toast(text, kind) {
    var el = document.createElement('div'); el.className = 'cl-toast ' + (kind || ''); el.textContent = text;
    document.body.appendChild(el); setTimeout(function () { el.classList.add('on'); }, 10);
    setTimeout(function () { el.classList.remove('on'); setTimeout(function () { el.remove(); }, 400); }, kind === 'e' ? 6000 : 2800);
  }
  var ERRS = {
    'not allowed': ['غير مسموح', 'Not allowed', 'Non autorisé'],
    'username taken': ['اسم المستخدم مستعمل لتلميذ آخر', 'Username already used by another student', 'Nom d’utilisateur déjà utilisé'],
    'invalid username': ['اسم المستخدم: أحرف إنكليزية وأرقام فقط (3 إلى 30)', 'Username: latin letters and digits only (3–30)', 'Identifiant : lettres latines et chiffres (3–30)'],
    'password too short': ['كلمة المرور قصيرة جدًا (4 أحرف على الأقل)', 'Password too short (min 4)', 'Mot de passe trop court (4 min.)'],
    'slug taken': ['هذا الرابط محجوز', 'This link is taken', 'Ce lien est déjà pris'],
    'Failed to fetch': ['تعذّر الاتصال بالإنترنت', 'No internet connection', 'Pas de connexion Internet']
  };
  function errText(e) {
    var m = String((e && (e.message || e.error_description || e.details)) || e || '');
    for (var k in ERRS) if (m.indexOf(k) >= 0) return ERRS[k][LANGS.indexOf(lang)];
    return t('error') + (m ? ': ' + m : '');
  }
  function waLink(phone, text) {
    var p = String(phone || '').replace(/\D/g, '');
    if (p.length === 8 && /^(3|7|8)/.test(p)) p = '961' + p;      // رقم لبناني محلي
    if (p.length === 7 && p.charAt(0) === '3') p = '9613' + p.slice(1);
    if (p.indexOf('00') === 0) p = p.slice(2);
    return 'https://wa.me/' + p + (text ? '?text=' + encodeURIComponent(text) : '');
  }
  var WA_SVG = '<svg viewBox="0 0 32 32" width="30" height="30" aria-hidden="true"><path fill="#fff" d="M16 3C9 3 3.3 8.6 3.3 15.6c0 2.4.7 4.7 1.9 6.7L3 29l6.9-2.1c1.9 1 4 1.6 6.1 1.6 7 0 12.7-5.6 12.7-12.6S23 3 16 3zm0 23.2c-1.9 0-3.8-.5-5.4-1.5l-.4-.2-4.1 1.2 1.2-4-.3-.4c-1.1-1.7-1.7-3.6-1.7-5.7C5.3 9.8 10.1 5.1 16 5.1s10.7 4.7 10.7 10.5S21.9 26.2 16 26.2zm5.9-7.8c-.3-.2-1.9-.9-2.2-1s-.5-.2-.7.2-.8 1-1 1.2-.4.2-.7.1c-.3-.2-1.4-.5-2.6-1.6-1-.9-1.6-1.9-1.8-2.2s0-.5.1-.6l.5-.6c.2-.2.2-.4.3-.6s0-.4 0-.6l-1-2.4c-.3-.6-.5-.5-.7-.5h-.6c-.2 0-.6.1-.9.4s-1.2 1.1-1.2 2.7 1.2 3.1 1.4 3.4c.2.2 2.4 3.6 5.7 5 .8.3 1.4.5 1.9.7.8.3 1.5.2 2.1.1.6-.1 1.9-.8 2.2-1.5.3-.7.3-1.4.2-1.5-.1-.2-.3-.3-.6-.4z"/></svg>';

  return {
    add: add, initLang: initLang, setLang: setLang, t: t, applyAll: applyAll, lang: function () { return lang; }, LANGS: LANGS,
    esc: esc, fmtDate: fmtDate, fmtTime: fmtTime, fmtDateTime: fmtDateTime, money: money, todayIn: todayIn, iso: iso,
    addMonths: addMonths, addDays: addDays, daysBetween: daysBetween, parseDate: parseDate,
    status: status, statusLabel: statusLabel, stateName: stateName,
    imgUrl: imgUrl, loadImg: loadImg, initials: initials, shade: shade, readable: readable,
    qrSvg: qrSvg, qrPayload: qrPayload, renderCard: renderCard, cardsPdf: cardsPdf, makePdf: makePdf, download: download,
    loadFace: loadFace, faceDescriptor: faceDescriptor, faceDist: faceDist, loadScript: loadScript,
    modal: modal, confirmBox: confirmBox, toast: toast, errText: errText, waLink: waLink, WA_SVG: WA_SVG
  };
})();
