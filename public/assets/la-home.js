/* LibanApps — أيقونات مرسومة للواجهة الرئيسية + صفحة دخول عصرية (نفس ستايل برنامج الموتير) — لبرامج التجارة والصناعيين */
(function(){
var SK='#f2b98a';
var BASE={
 read:'<rect x="10" y="4" width="44" height="56" rx="9" fill="#1e3a5f"/><rect x="15" y="9" width="34" height="27" rx="6" fill="#e0f2fe"/><path d="M20 31a12 12 0 0 1 24 0" fill="none" stroke="#e2e8f0" stroke-width="5"/><path d="M20 31a12 12 0 0 1 6-10.4" fill="none" stroke="#22c55e" stroke-width="5"/><path d="M26 20.6a12 12 0 0 1 12 0" fill="none" stroke="#facc15" stroke-width="5"/><path d="M38 20.6A12 12 0 0 1 44 31" fill="none" stroke="#ef4444" stroke-width="5"/><path d="M32 31l6-8" stroke="#0f172a" stroke-width="2.6" stroke-linecap="round"/><circle cx="32" cy="31" r="2.8" fill="#0f172a"/><rect x="16" y="41" width="32" height="10" rx="2.5" fill="#0f172a"/><rect x="19" y="43.5" width="5" height="5" rx="1" fill="#4ade80"/><rect x="26" y="43.5" width="5" height="5" rx="1" fill="#4ade80"/><rect x="33" y="43.5" width="5" height="5" rx="1" fill="#4ade80"/><rect x="40" y="43.5" width="5" height="5" rx="1" fill="#facc15"/><path d="M34 52.5l-3.5 5h3l-1.5 3.5 5-5.5h-3l1.5-3z" fill="#facc15"/>',
 pay:'<rect x="5" y="15" width="42" height="25" rx="4" fill="#15803d" transform="rotate(-9 26 27)"/><rect x="9" y="20" width="44" height="26" rx="4" fill="#22c55e"/><rect x="12" y="23" width="38" height="20" rx="3" fill="none" stroke="#bbf7d0" stroke-width="1.5"/><circle cx="31" cy="33" r="7.5" fill="#bbf7d0"/><path d="M33.6 30.2c-.6-.8-1.6-1.2-2.6-1.2-1.6 0-2.6.8-2.6 2 0 2.8 5.6 1.5 5.6 4.3 0 1.3-1.1 2.1-2.8 2.1-1.2 0-2.4-.5-3-1.4M31 27.6v1.4M31 37.3v1.4" fill="none" stroke="#15803d" stroke-width="1.7" stroke-linecap="round"/><ellipse cx="49" cy="54" rx="10" ry="4.5" fill="#a16207"/><rect x="39" y="47" width="20" height="7" fill="#ca8a04"/><ellipse cx="49" cy="47" rx="10" ry="4.5" fill="#facc15"/><ellipse cx="49" cy="47" rx="5" ry="2" fill="#fde047"/>',
 sales:'<path d="M12 4h32v54l-5.3-3.4-5.4 3.4-5.3-3.4-5.4 3.4-5.3-3.4-5.3 3.4z" fill="#fff" stroke="#cbd5e1" stroke-width="2" stroke-linejoin="round"/><rect x="17" y="11" width="22" height="4" rx="2" fill="#f59e0b"/><rect x="17" y="20" width="15" height="2.6" rx="1.3" fill="#94a3b8"/><rect x="34" y="20" width="5" height="2.6" rx="1.3" fill="#94a3b8"/><rect x="17" y="27" width="12" height="2.6" rx="1.3" fill="#94a3b8"/><rect x="34" y="27" width="5" height="2.6" rx="1.3" fill="#94a3b8"/><rect x="17" y="34" width="14" height="2.6" rx="1.3" fill="#94a3b8"/><rect x="34" y="34" width="5" height="2.6" rx="1.3" fill="#94a3b8"/><rect x="17" y="42" width="22" height="4.5" rx="2.2" fill="#1e3a5f"/><path d="M38 33h12.5l8 8-12 12-8.5-8.5z" fill="#f97316"/><circle cx="46" cy="38.5" r="2.2" fill="#fff"/>',
 switch:'<rect x="22" y="2" width="5" height="14" rx="2.5" fill="#94a3b8"/><rect x="37" y="2" width="5" height="14" rx="2.5" fill="#94a3b8"/><path d="M15 13h34v11a17 17 0 0 1-34 0z" fill="#ef4444"/><path d="M15 13h34v4H15z" fill="#dc2626"/><path d="M34 17l-7 10h5l-2 8 8-11h-5l2-7z" fill="#facc15"/><rect x="28.5" y="40" width="7" height="8" fill="#334155"/><path d="M32 48c0 7 5 10 14 10" fill="none" stroke="#334155" stroke-width="5" stroke-linecap="round"/>',
 customers:'<circle cx="44" cy="20" r="8.5" fill="#d4956a"/><path d="M28 56a16 16 0 0 1 32 0v2H28z" fill="#8b5cf6"/><circle cx="23" cy="18" r="10" fill="'+SK+'"/><path d="M13 16a10 10 0 0 1 20 0c-3-3-7-4-10-4s-7 1-10 4z" fill="#334155"/><path d="M4 58a19 19 0 0 1 38 0v2H4z" fill="#3b82f6"/><path d="M23 39l-4 8 4 4 4-4z" fill="#1e40af"/>',
 unpaid:'<rect x="6" y="6" width="34" height="46" rx="5" fill="#fff" stroke="#cbd5e1" stroke-width="2"/><rect x="12" y="14" width="22" height="3" rx="1.5" fill="#94a3b8"/><rect x="12" y="22" width="16" height="3" rx="1.5" fill="#cbd5e1"/><rect x="12" y="29" width="19" height="3" rx="1.5" fill="#cbd5e1"/><rect x="12" y="38" width="14" height="5" rx="2.5" fill="#ef4444"/><circle cx="45" cy="45" r="15" fill="#f97316"/><circle cx="45" cy="45" r="11.5" fill="#fff7ed"/><path d="M45 37v8.5l5.5 3.5" fill="none" stroke="#c2410c" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>',
 month:'<rect x="6" y="10" width="52" height="48" rx="7" fill="#fff" stroke="#cbd5e1" stroke-width="2"/><path d="M6 17a7 7 0 0 1 7-7h38a7 7 0 0 1 7 7v8H6z" fill="#6366f1"/><rect x="16" y="4" width="6" height="13" rx="3" fill="#334155"/><rect x="42" y="4" width="6" height="13" rx="3" fill="#334155"/><g fill="#c7d2fe"><rect x="13" y="31" width="8" height="7" rx="1.5"/><rect x="24" y="31" width="8" height="7" rx="1.5"/><rect x="35" y="31" width="8" height="7" rx="1.5"/><rect x="46" y="31" width="6" height="7" rx="1.5"/><rect x="13" y="42" width="8" height="7" rx="1.5"/><rect x="35" y="42" width="8" height="7" rx="1.5"/></g><rect x="24" y="42" width="8" height="7" rx="1.5" fill="#f97316"/>',
 cstmt:'<rect x="10" y="8" width="40" height="52" rx="6" fill="#8b5cf6"/><rect x="15" y="15" width="30" height="40" rx="3" fill="#fff"/><rect x="23" y="4" width="14" height="9" rx="3" fill="#475569"/><path d="M19 24l2.5 2.5 4.5-4.5M19 34l2.5 2.5 4.5-4.5M19 44l2.5 2.5 4.5-4.5" fill="none" stroke="#22c55e" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/><rect x="29" y="23" width="12" height="3" rx="1.5" fill="#cbd5e1"/><rect x="29" y="33" width="10" height="3" rx="1.5" fill="#cbd5e1"/><rect x="29" y="43" width="12" height="3" rx="1.5" fill="#cbd5e1"/>',
 bills:'<rect x="4" y="16" width="32" height="42" rx="5" fill="#fff" stroke="#cbd5e1" stroke-width="2"/><rect x="10" y="24" width="20" height="3" rx="1.5" fill="#94a3b8"/><rect x="10" y="31" width="14" height="3" rx="1.5" fill="#cbd5e1"/><rect x="10" y="38" width="17" height="3" rx="1.5" fill="#cbd5e1"/><rect x="10" y="47" width="20" height="5" rx="2.5" fill="#14b8a6"/><path d="M61 4L27 22l13 5z" fill="#2dd4bf"/><path d="M61 4L40 27l3 17z" fill="#0d9488"/><path d="M40 27l3 17 6-11z" fill="#115e59"/>',
 wa:'<path d="M32 5a25 25 0 0 0-21.5 37.7L7 57l14.8-3.5A25 25 0 1 0 32 5z" fill="#22c55e"/><path d="M32 9a21 21 0 0 0-18 31.8l-2.4 9.6 9.9-2.4A21 21 0 1 0 32 9z" fill="#4ade80" opacity=".35"/><path d="M21 31.5l7.5 7.5 14-14" fill="none" stroke="#fff" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round"/>',
 cash:'<rect x="7" y="6" width="50" height="46" rx="7" fill="#475569"/><rect x="12" y="11" width="40" height="36" rx="4" fill="#64748b"/><circle cx="30" cy="29" r="11" fill="#facc15"/><circle cx="30" cy="29" r="4.5" fill="#475569"/><path d="M30 18v4M30 36v4M19 29h4M37 29h4" stroke="#475569" stroke-width="2.4" stroke-linecap="round"/><rect x="45" y="22" width="3.5" height="14" rx="1.75" fill="#cbd5e1"/><rect x="11" y="52" width="9" height="7" rx="2" fill="#334155"/><rect x="44" y="52" width="9" height="7" rx="2" fill="#334155"/>',
 whish:'<path d="M10 16l30-11 5 11z" fill="#c4b5fd"/><rect x="5" y="15" width="48" height="38" rx="7" fill="#7c3aed"/><rect x="5" y="15" width="48" height="7" rx="3" fill="#6d28d9"/><rect x="35" y="27" width="22" height="15" rx="5" fill="#5b21b6"/><circle cx="43" cy="34.5" r="3.5" fill="#facc15"/>',
 journal:'<rect x="12" y="4" width="42" height="56" rx="5" fill="#f59e0b"/><rect x="12" y="4" width="9" height="56" rx="4" fill="#b45309"/><rect x="25" y="12" width="23" height="17" rx="2.5" fill="#fff"/><rect x="28.5" y="17" width="16" height="2.6" rx="1.3" fill="#cbd5e1"/><rect x="28.5" y="22.5" width="10" height="2.6" rx="1.3" fill="#cbd5e1"/><path d="M42 60V47l4 3 4-3v13" fill="#ef4444"/>',
 expenses:'<rect x="13" y="6" width="30" height="17" rx="3" fill="#22c55e" transform="rotate(-8 28 14)"/><rect x="5" y="17" width="44" height="34" rx="7" fill="#ef4444"/><rect x="5" y="17" width="44" height="9" rx="4" fill="#b91c1c"/><rect x="33" y="31" width="16" height="12" rx="4" fill="#991b1b"/><circle cx="49" cy="49" r="12" fill="#fff" stroke="#fecaca" stroke-width="2"/><path d="M49 42v13M43.5 50l5.5 5.5 5.5-5.5" fill="none" stroke="#ef4444" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>',
 salaries:'<path d="M6 58a19 19 0 0 1 38 0v2H6z" fill="#0ea5e9"/><path d="M19 42h12l-6 8z" fill="#0369a1"/><circle cx="25" cy="24" r="10" fill="'+SK+'"/><path d="M13 22a12 12 0 0 1 24 0z" fill="#facc15"/><rect x="11" y="20.5" width="28" height="3.5" rx="1.75" fill="#eab308"/><rect x="36" y="38" width="26" height="17" rx="3" fill="#16a34a"/><rect x="38" y="40" width="22" height="13" rx="2" fill="#22c55e"/><circle cx="49" cy="46.5" r="4" fill="#bbf7d0"/>',
 stock:'<path d="M32 5l23 10.5-23 10.5L9 15.5z" fill="#fbbf24"/><path d="M9 15.5l23 10.5v33L9 48.5z" fill="#d97706"/><path d="M55 15.5L32 26v33l23-10.5z" fill="#b45309"/><path d="M20 10.5l23 10.5v9l-5 2.3v-9L15 12.8z" fill="#fde68a"/>',
 suppliers:'<rect x="3" y="14" width="36" height="28" rx="3" fill="#3b82f6"/><rect x="8" y="20" width="12" height="9" rx="1.5" fill="#fbbf24"/><rect x="22" y="20" width="12" height="9" rx="1.5" fill="#fbbf24"/><path d="M39 22h13l9 10v11H39z" fill="#1e40af"/><path d="M43 25.5h7.5l6 7H43z" fill="#bfdbfe"/><rect x="3" y="40" width="58" height="5" rx="2" fill="#1e293b"/><circle cx="15" cy="47" r="7" fill="#1e293b"/><circle cx="15" cy="47" r="3" fill="#cbd5e1"/><circle cx="49" cy="47" r="7" fill="#1e293b"/><circle cx="49" cy="47" r="3" fill="#cbd5e1"/>',
 insurance:'<path d="M32 3l23 8.5v17C55 43 45 53.5 32 60 19 53.5 9 43 9 28.5v-17z" fill="#14b8a6"/><path d="M32 3v57C19 53.5 9 43 9 28.5v-17z" fill="#0d9488"/><path d="M21 31.5l7.5 7.5 14.5-14.5" fill="none" stroke="#fff" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round"/>',
 report:'<rect x="4" y="6" width="56" height="42" rx="5" fill="#fff" stroke="#cbd5e1" stroke-width="2"/><rect x="12" y="30" width="8" height="12" rx="1.5" fill="#3b82f6"/><rect x="24" y="18" width="8" height="24" rx="1.5" fill="#22c55e"/><rect x="36" y="24" width="8" height="18" rx="1.5" fill="#f59e0b"/><rect x="48" y="13" width="5" height="29" rx="1.5" fill="#ef4444"/><rect x="30" y="48" width="4" height="8" fill="#94a3b8"/><rect x="21" y="55" width="22" height="4" rx="2" fill="#94a3b8"/>',
 finrep:'<rect x="8" y="4" width="38" height="52" rx="5" fill="#fff" stroke="#cbd5e1" stroke-width="2"/><circle cx="27" cy="22" r="11" fill="#f0abfc"/><path d="M27 22V11a11 11 0 0 1 11 11z" fill="#a21caf"/><rect x="15" y="39" width="24" height="3" rx="1.5" fill="#cbd5e1"/><rect x="15" y="45.5" width="16" height="3" rx="1.5" fill="#cbd5e1"/><circle cx="48" cy="47" r="13" fill="#22c55e"/><path d="M40.5 51.5l5.5-5.5 3.5 3.5 6.5-6.5M51 43h5v5" fill="none" stroke="#fff" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/>',
 map:'<path d="M4 18l17-7 22 7 17-7v40l-17 7-22-7-17 7z" fill="#bbf7d0"/><path d="M21 11v40" stroke="#86efac" stroke-width="2.5"/><path d="M43 18v40" stroke="#86efac" stroke-width="2.5"/><path d="M8 40c8-6 14 4 24-2s14-8 24-4" fill="none" stroke="#38bdf8" stroke-width="3" stroke-linecap="round"/><path d="M38 3a11 11 0 0 0-11 11c0 9 11 20 11 20s11-11 11-20A11 11 0 0 0 38 3z" fill="#ef4444"/><circle cx="38" cy="14" r="4.2" fill="#fff"/>',
 staff:'<rect x="27" y="2" width="10" height="13" rx="2.5" fill="#94a3b8"/><rect x="6" y="11" width="52" height="40" rx="6" fill="#3b82f6"/><rect x="6" y="11" width="52" height="10" rx="5" fill="#1d4ed8"/><rect x="27" y="13" width="10" height="4" rx="2" fill="#e2e8f0"/><circle cx="21" cy="32" r="6.5" fill="'+SK+'"/><path d="M11 46a10 10 0 0 1 20 0z" fill="#fff"/><rect x="35" y="27" width="17" height="3.5" rx="1.75" fill="#bfdbfe"/><rect x="35" y="34" width="12" height="3.5" rx="1.75" fill="#bfdbfe"/><rect x="35" y="41" width="15" height="3.5" rx="1.75" fill="#bfdbfe"/>',
 disc:'<path d="M30 4h22a4 4 0 0 1 4 4v22L30 56a5 5 0 0 1-7 0L8 41a5 5 0 0 1 0-7z" fill="#ec4899"/><path d="M30 4h22a4 4 0 0 1 4 4v22L43 43 21 13z" fill="#f472b6"/><circle cx="46" cy="14" r="4" fill="#fff"/><circle cx="24" cy="31" r="3.6" fill="none" stroke="#fff" stroke-width="2.6"/><circle cx="36" cy="39" r="3.6" fill="none" stroke="#fff" stroke-width="2.6"/><path d="M38 28L22 42" stroke="#fff" stroke-width="2.8" stroke-linecap="round"/>',
 maint:'<path d="M44 4a12 12 0 0 0-11.4 15.8L8 44.4a5.6 5.6 0 0 0 7.9 7.9l24.6-24.6A12 12 0 0 0 56 16l-7.2 7.2-6.8-1.2-1.2-6.8L48 8a12 12 0 0 0-4-4z" fill="#64748b"/><circle cx="12" cy="48.3" r="2.6" fill="#e2e8f0"/><circle cx="46" cy="46" r="15" fill="#f97316"/><path d="M46 37v10" stroke="#fff" stroke-width="4" stroke-linecap="round"/><circle cx="46" cy="53.5" r="2.4" fill="#fff"/>',
 coa:'<rect x="9" y="4" width="44" height="56" rx="5" fill="#0f766e"/><rect x="9" y="4" width="9" height="56" rx="4" fill="#115e59"/><rect x="22" y="11" width="25" height="42" rx="2.5" fill="#f0fdfa"/><g fill="#14b8a6"><rect x="25" y="16" width="7" height="3" rx="1"/><rect x="25" y="23" width="7" height="3" rx="1"/><rect x="25" y="30" width="7" height="3" rx="1"/><rect x="25" y="37" width="7" height="3" rx="1"/><rect x="25" y="44" width="7" height="3" rx="1"/></g><g fill="#94a3b8"><rect x="34" y="16" width="10" height="3" rx="1"/><rect x="34" y="23" width="8" height="3" rx="1"/><rect x="34" y="30" width="10" height="3" rx="1"/><rect x="34" y="37" width="7" height="3" rx="1"/><rect x="34" y="44" width="9" height="3" rx="1"/></g><circle cx="52" cy="52" r="10" fill="#f59e0b"/><path d="M48 52h8M52 48v8" stroke="#fff" stroke-width="2.6" stroke-linecap="round"/>',
 bsheet:'<rect x="30" y="8" width="4" height="46" rx="2" fill="#475569"/><rect x="18" y="54" width="28" height="6" rx="3" fill="#334155"/><path d="M10 16h44" stroke="#475569" stroke-width="4" stroke-linecap="round"/><circle cx="32" cy="10" r="4" fill="#f59e0b"/><path d="M14 16L5 36M14 16l9 20M50 16l-9 20M50 16l9 20" stroke="#94a3b8" stroke-width="1.8"/><path d="M3 36h22a11 7 0 0 1-22 0z" fill="#22c55e"/><path d="M39 36h22a11 7 0 0 1-22 0z" fill="#3b82f6"/><circle cx="14" cy="32" r="3.5" fill="#facc15"/><circle cx="50" cy="32" r="3.5" fill="#facc15"/>',
 plans:'<path d="M38 2L12 36h17l-5 26 28-36H34z" fill="#facc15"/><path d="M38 2L24 36h5l-5 26 13-27z" fill="#eab308"/>',
 trash:'<rect x="13" y="18" width="38" height="42" rx="5" fill="#94a3b8"/><rect x="9" y="11" width="46" height="8" rx="3.5" fill="#64748b"/><rect x="25" y="5" width="14" height="8" rx="2.5" fill="#64748b"/><path d="M23 27v24M32 27v24M41 27v24" stroke="#e2e8f0" stroke-width="3.2" stroke-linecap="round"/>',
 settings:'<g transform="translate(4 4) scale(2.333)"><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" fill="#94a3b8" stroke="#475569" stroke-width=".9"/><circle cx="12" cy="12" r="3.4" fill="#f8fafc" stroke="#475569" stroke-width=".9"/></g>'
};
BASE.barcode='<rect x="6" y="10" width="52" height="44" rx="7" fill="#fff" stroke="#cbd5e1" stroke-width="2"/><g fill="#0f172a"><rect x="13" y="17" width="3" height="24"/><rect x="18.5" y="17" width="1.6" height="24"/><rect x="22.5" y="17" width="4" height="24"/><rect x="29" y="17" width="1.6" height="24"/><rect x="33" y="17" width="3" height="24"/><rect x="38.5" y="17" width="1.6" height="24"/><rect x="42.5" y="17" width="4" height="24"/><rect x="48.5" y="17" width="2" height="24"/></g><rect x="13" y="44" width="38" height="4" rx="2" fill="#94a3b8"/><path d="M4 30h56" stroke="#ef4444" stroke-width="2.5" stroke-linecap="round" opacity=".85"/>';
BASE.key='<circle cx="22" cy="24" r="15" fill="#f59e0b"/><circle cx="22" cy="24" r="6" fill="#fff7ed"/><path d="M33 33l22 22" stroke="#d97706" stroke-width="8" stroke-linecap="round"/><path d="M44 44l6-6M50 50l5-5" stroke="#d97706" stroke-width="6" stroke-linecap="round"/><circle cx="48" cy="14" r="9" fill="#3b82f6"/><circle cx="48" cy="11" r="3.4" fill="#fff"/><path d="M41.5 20a6.5 6.5 0 0 1 13 0z" fill="#fff"/>';
BASE.lock='<rect x="9" y="27" width="46" height="33" rx="7" fill="#64748b"/><path d="M19 27v-8a13 13 0 0 1 26 0v8" fill="none" stroke="#94a3b8" stroke-width="6"/><rect x="14" y="33" width="36" height="21" rx="4" fill="#475569"/><circle cx="32" cy="41" r="4.5" fill="#facc15"/><rect x="30" y="43" width="4" height="7" rx="2" fill="#facc15"/>';
BASE.ruler='<rect x="4" y="36" width="56" height="16" rx="3" fill="#facc15" transform="rotate(-30 32 44)"/><g stroke="#92400e" stroke-width="2.4" stroke-linecap="round" transform="rotate(-30 32 44)"><path d="M10 36v6M16 36v4M22 36v6M28 36v4M34 36v6M40 36v4M46 36v6M52 36v4"/></g><path d="M40 6l14 14-20 20H20V26z" fill="#38bdf8"/><path d="M20 40l6-6" stroke="#0369a1" stroke-width="2.5"/>';
BASE.calc='<rect x="12" y="4" width="40" height="56" rx="7" fill="#334155"/><rect x="17" y="9" width="30" height="13" rx="3" fill="#bbf7d0"/><rect x="34" y="13" width="10" height="4" rx="1" fill="#15803d"/><g fill="#e2e8f0"><rect x="17" y="27" width="8" height="7" rx="2"/><rect x="28" y="27" width="8" height="7" rx="2"/><rect x="17" y="37" width="8" height="7" rx="2"/><rect x="28" y="37" width="8" height="7" rx="2"/><rect x="17" y="47" width="8" height="7" rx="2"/><rect x="28" y="47" width="8" height="7" rx="2"/></g><rect x="39" y="27" width="8" height="27" rx="2" fill="#f97316"/>';
BASE.window='<rect x="8" y="6" width="48" height="52" rx="4" fill="#94a3b8"/><rect x="12" y="10" width="19" height="21" fill="#bae6fd"/><rect x="33" y="10" width="19" height="21" fill="#7dd3fc"/><rect x="12" y="33" width="19" height="21" fill="#7dd3fc"/><rect x="33" y="33" width="19" height="21" fill="#bae6fd"/><path d="M15 26l10-12M36 49l10-12" stroke="#fff" stroke-width="2.5" stroke-linecap="round" opacity=".8"/>';
BASE.bank='<path d="M32 4L4 18v6h56v-6z" fill="#0ea5e9"/><path d="M32 8L12 18h40z" fill="#38bdf8"/><circle cx="32" cy="14" r="3" fill="#facc15"/><g fill="#e2e8f0"><rect x="9" y="27" width="7" height="22" rx="1.5"/><rect x="21" y="27" width="7" height="22" rx="1.5"/><rect x="36" y="27" width="7" height="22" rx="1.5"/><rect x="48" y="27" width="7" height="22" rx="1.5"/></g><rect x="5" y="49" width="54" height="5" rx="2" fill="#0284c7"/><rect x="2" y="55" width="60" height="6" rx="2" fill="#075985"/><circle cx="50" cy="48" r="11" fill="#22c55e"/><text x="50" y="53" font-size="14" font-weight="800" text-anchor="middle" fill="#fff" font-family="Arial">$</text>';
BASE.ledger='<rect x="8" y="6" width="44" height="54" rx="5" fill="#1e3a8a"/><rect x="12" y="6" width="40" height="50" rx="4" fill="#f8fafc"/><path d="M32 10v42" stroke="#cbd5e1" stroke-width="2"/><g stroke="#94a3b8" stroke-width="2.4" stroke-linecap="round"><path d="M16 18h12M16 25h12M16 32h12M36 18h12M36 25h12M36 32h12"/></g><circle cx="22" cy="44" r="6" fill="#22c55e"/><path d="M19 44h6M22 41v6" stroke="#fff" stroke-width="2.2" stroke-linecap="round"/><circle cx="42" cy="44" r="6" fill="#ef4444"/><path d="M39 44h6" stroke="#fff" stroke-width="2.2" stroke-linecap="round"/><path d="M50 2l8 8-14 14-9 2 2-9z" fill="#f59e0b"/>';
BASE.pl='<rect x="4" y="6" width="56" height="52" rx="7" fill="#fff" stroke="#cbd5e1" stroke-width="2"/><rect x="12" y="30" width="8" height="20" rx="2" fill="#22c55e"/><rect x="24" y="20" width="8" height="30" rx="2" fill="#16a34a"/><rect x="36" y="36" width="8" height="14" rx="2" fill="#ef4444"/><rect x="48" y="42" width="6" height="8" rx="2" fill="#dc2626"/><path d="M12 22l12-8 12 10 14-12" fill="none" stroke="#0ea5e9" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/><circle cx="50" cy="12" r="3" fill="#0ea5e9"/>';
BASE.ledgerbook='<rect x="10" y="4" width="44" height="56" rx="5" fill="#7c3aed"/><rect x="14" y="8" width="36" height="48" rx="3" fill="#fff"/><path d="M32 12v40" stroke="#c4b5fd" stroke-width="2"/><g stroke="#94a3b8" stroke-width="2.2" stroke-linecap="round"><path d="M18 18h10M18 24h10M18 30h10M36 18h10M36 24h10M36 30h10"/></g><text x="23" y="47" font-size="12" font-weight="900" text-anchor="middle" fill="#16a34a" font-family="Arial">+</text><text x="41" y="47" font-size="13" font-weight="900" text-anchor="middle" fill="#dc2626" font-family="Arial">−</text>';
BASE.plstmt='<rect x="6" y="6" width="52" height="52" rx="8" fill="#0f766e"/><rect x="12" y="34" width="8" height="18" rx="2" fill="#5eead4"/><rect x="24" y="26" width="8" height="26" rx="2" fill="#99f6e4"/><rect x="36" y="38" width="8" height="14" rx="2" fill="#fca5a5"/><rect x="48" y="18" width="5" height="34" rx="2" fill="#facc15"/><path d="M12 22l12-8 10 6 16-10" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>';
BASE.accgov='<path d="M32 4L6 18h52z" fill="#1e3a8a"/><rect x="6" y="18" width="52" height="5" fill="#1e40af"/><g fill="#93c5fd"><rect x="10" y="25" width="6" height="24"/><rect x="21" y="25" width="6" height="24"/><rect x="37" y="25" width="6" height="24"/><rect x="48" y="25" width="6" height="24"/></g><rect x="4" y="50" width="56" height="8" rx="2" fill="#1e3a8a"/><circle cx="32" cy="13" r="3" fill="#facc15"/>';
BASE.balsheet='<path d="M32 8v44" stroke="#475569" stroke-width="4" stroke-linecap="round"/><path d="M10 18h44" stroke="#475569" stroke-width="4" stroke-linecap="round"/><path d="M14 18L6 36h16z" fill="#bfdbfe"/><path d="M50 18l-8 18h16z" fill="#bbf7d0"/><path d="M4 36a10 6 0 0 0 20 0z" fill="#2563eb"/><path d="M40 36a10 6 0 0 0 20 0z" fill="#16a34a"/><rect x="20" y="52" width="24" height="6" rx="3" fill="#334155"/><circle cx="32" cy="8" r="4" fill="#facc15"/>';
BASE.fyear='<rect x="6" y="10" width="52" height="46" rx="6" fill="#fff" stroke="#0369a1" stroke-width="3"/><rect x="6" y="10" width="52" height="13" rx="6" fill="#0369a1"/><path d="M18 5v10M46 5v10" stroke="#0c4a6e" stroke-width="4" stroke-linecap="round"/><text x="24" y="47" font-size="15" font-weight="900" text-anchor="middle" fill="#0369a1" font-family="Arial">31</text><rect x="38" y="35" width="14" height="12" rx="2" fill="#f59e0b"/><path d="M41 35v-4a4 4 0 0 1 8 0v4" fill="none" stroke="#b45309" stroke-width="2.5"/>';
BASE.vat='<rect x="10" y="4" width="44" height="56" rx="5" fill="#dc2626"/><rect x="15" y="10" width="34" height="44" rx="3" fill="#fff"/><text x="32" y="30" font-size="13" font-weight="900" text-anchor="middle" fill="#dc2626" font-family="Arial">TVA</text><text x="32" y="47" font-size="13" font-weight="900" text-anchor="middle" fill="#111827" font-family="Arial">11%</text>';
BASE.assets='<rect x="6" y="28" width="52" height="28" rx="4" fill="#f59e0b"/><rect x="12" y="34" width="12" height="10" rx="2" fill="#fff7ed"/><rect x="28" y="34" width="12" height="10" rx="2" fill="#fff7ed"/><path d="M10 28V14h16l6 8h22v6" fill="#b45309"/><circle cx="18" cy="56" r="5" fill="#334155"/><circle cx="46" cy="56" r="5" fill="#334155"/><path d="M44 10l8 8M52 10l-8 8" stroke="#64748b" stroke-width="3" stroke-linecap="round"/>';
BASE.fx='<circle cx="22" cy="24" r="16" fill="#16a34a"/><text x="22" y="30" font-size="17" font-weight="900" text-anchor="middle" fill="#fff" font-family="Arial">$</text><circle cx="42" cy="42" r="16" fill="#0ea5e9"/><text x="42" y="47" font-size="11" font-weight="900" text-anchor="middle" fill="#fff" font-family="Arial">LL</text><path d="M44 8a14 14 0 0 1 12 12" fill="none" stroke="#64748b" stroke-width="3" stroke-linecap="round"/><path d="M20 56A14 14 0 0 1 8 44" fill="none" stroke="#64748b" stroke-width="3" stroke-linecap="round"/>';
BASE.bankrec='<path d="M32 4L6 16h52z" fill="#0f766e"/><g fill="#5eead4"><rect x="10" y="19" width="6" height="18"/><rect x="22" y="19" width="6" height="18"/><rect x="36" y="19" width="6" height="18"/><rect x="48" y="19" width="6" height="18"/></g><rect x="6" y="37" width="52" height="5" fill="#0f766e"/><circle cx="44" cy="50" r="11" fill="#22c55e"/><path d="M38 50l4 4 8-8" fill="none" stroke="#fff" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>';
BASE.nssf='<path d="M32 4l22 8v16c0 14-10 24-22 30C20 52 10 42 10 28V12z" fill="#2563eb"/><path d="M32 10l16 6v12c0 10-7 18-16 23-9-5-16-13-16-23V16z" fill="#dbeafe"/><circle cx="32" cy="24" r="5" fill="#1d4ed8"/><path d="M22 40c2-6 6-8 10-8s8 2 10 8" fill="#1d4ed8"/>';
BASE.cashflow='<path d="M32 6C24 18 14 26 14 38a18 18 0 0 0 36 0C50 26 40 18 32 6z" fill="#0ea5e9"/><path d="M26 40a7 7 0 0 0 7 7" fill="none" stroke="#e0f2fe" stroke-width="3" stroke-linecap="round"/><text x="32" y="38" font-size="14" font-weight="900" text-anchor="middle" fill="#fff" font-family="Arial">$</text><path d="M6 56h52" stroke="#0369a1" stroke-width="4" stroke-linecap="round"/>';
BASE.stockcount='<path d="M8 22l24-12 24 12v28L32 62 8 50z" fill="#d97706"/><path d="M8 22l24 12 24-12" fill="none" stroke="#fde68a" stroke-width="3"/><path d="M32 34v28" stroke="#fde68a" stroke-width="3"/><rect x="38" y="4" width="22" height="26" rx="3" fill="#fff" stroke="#334155" stroke-width="2"/><path d="M42 12l3 3 5-6M42 22l3 3 5-6" fill="none" stroke="#16a34a" stroke-width="2.5" stroke-linecap="round"/>';
BASE.audit='<rect x="8" y="6" width="36" height="48" rx="4" fill="#fff" stroke="#475569" stroke-width="3"/><path d="M16 18h20M16 26h20M16 34h12" stroke="#94a3b8" stroke-width="3" stroke-linecap="round"/><circle cx="42" cy="40" r="11" fill="none" stroke="#7c3aed" stroke-width="5"/><path d="M50 48l8 8" stroke="#7c3aed" stroke-width="6" stroke-linecap="round"/>';
BASE.payroll='<rect x="6" y="14" width="52" height="36" rx="5" fill="#16a34a"/><circle cx="32" cy="32" r="9" fill="#bbf7d0"/><text x="32" y="37" font-size="12" font-weight="900" text-anchor="middle" fill="#166534" font-family="Arial">$</text><circle cx="14" cy="32" r="3" fill="#bbf7d0"/><circle cx="50" cy="32" r="3" fill="#bbf7d0"/><rect x="18" y="50" width="28" height="8" rx="2" fill="#0f766e"/>';
BASE.cheque='<rect x="4" y="16" width="56" height="32" rx="4" fill="#fef3c7" stroke="#b45309" stroke-width="3"/><path d="M10 26h22M10 34h30" stroke="#92400e" stroke-width="2.5" stroke-linecap="round"/><path d="M38 41c4-6 6 2 9-3s4 2 7-1" fill="none" stroke="#1d4ed8" stroke-width="2.5" stroke-linecap="round"/><rect x="42" y="21" width="12" height="7" rx="1.5" fill="#fff" stroke="#b45309" stroke-width="1.5"/>';
BASE.aging='<circle cx="32" cy="34" r="24" fill="#fff" stroke="#dc2626" stroke-width="4"/><path d="M32 34V18M32 34l10 6" stroke="#111827" stroke-width="4" stroke-linecap="round"/><path d="M8 34a24 24 0 0 1 24-24" fill="none" stroke="#f59e0b" stroke-width="4"/><rect x="26" y="2" width="12" height="6" rx="2" fill="#dc2626"/>';
BASE.recurring='<circle cx="32" cy="32" r="22" fill="none" stroke="#2563eb" stroke-width="6"/><path d="M50 14v12H38" fill="none" stroke="#2563eb" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/><rect x="22" y="24" width="20" height="18" rx="3" fill="#dbeafe"/><path d="M26 30h12M26 36h8" stroke="#1d4ed8" stroke-width="2.5" stroke-linecap="round"/>';
BASE.costcenter='<path d="M6 30L30 6h22a6 6 0 0 1 6 6v22L34 58a4 4 0 0 1-6 0L6 36a4 4 0 0 1 0-6z" fill="#f97316"/><circle cx="46" cy="18" r="5" fill="#fff"/><path d="M22 34l8 8M28 28l8 8" stroke="#fff7ed" stroke-width="3" stroke-linecap="round"/>';
BASE.guide='<path d="M5 15c9-4 18-3 27 3v38c-9-6-18-7-27-3z" fill="#1d4ed8"/><path d="M59 15c-9-4-18-3-27 3v38c9-6 18-7 27-3z" fill="#3b82f6"/><path d="M10 21c6-1.6 12-1 18 2M10 28c6-1.6 12-1 18 2M10 35c6-1.6 12-1 18 2M36 23c6-3 12-3.6 18-2M36 30c6-3 12-3.6 18-2" stroke="#dbeafe" stroke-width="2.2" fill="none" stroke-linecap="round"/><circle cx="49" cy="47" r="10" fill="#f59e0b"/><path d="M45.5 44a3.6 3.6 0 1 1 5 3.3c-1 .5-1.5 1.2-1.5 2.4" stroke="#fff" stroke-width="2.6" fill="none" stroke-linecap="round"/><circle cx="49" cy="53.2" r="1.6" fill="#fff"/>';
BASE.plus='<circle cx="32" cy="32" r="26" fill="#22c55e"/><path d="M32 19v26M19 32h26" stroke="#fff" stroke-width="7" stroke-linecap="round"/>';
BASE.inbox='<path d="M6 34l8-22h36l8 22v20a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4z" fill="#22c55e"/><path d="M6 34h16l4 7h12l4-7h16v20a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4z" fill="#15803d"/><path d="M32 6v20M24 18l8 8 8-8" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>';
BASE.outbox='<path d="M6 34l8-22h36l8 22v20a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4z" fill="#ef4444"/><path d="M6 34h16l4 7h12l4-7h16v20a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4z" fill="#b91c1c"/><path d="M32 26V6M24 14l8-8 8 8" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>';

// مفاتيح البطاقات بالبرنامجين ← الأيقونة
var MAP={ '#/pos':'sales', '#/safe':'cash', '#/statement':'cstmt', '#/whish':'whish', '#/coa':'coa', '#/shift-closes':'lock', '#/journal':'journal',
  '#/product-sales':'report', '#/barcodes':'barcode', '#/reports':'finrep', '#/customers':'customers', '#/suppliers':'suppliers', '#/warehouse':'stock',
  '#/workers':'salaries', '#/budget':'expenses', '#/settings':'settings', '#/customer-accounts':'key', '#/worker-accounts':'key', '#/trash':'trash',
  '#/loans':'bank', '#/leb-journal':'ledgerbook', '#/leb-pl':'plstmt', '#/acc':'accgov', '#/leb-bs':'balsheet', '#/leb-year':'fyear', '#/leb-vat':'vat', '#/leb-assets':'assets', '#/leb-fx':'fx', '#/leb-bank':'bankrec', '#/leb-nssf':'nssf', '#/leb-cf':'cashflow', '#/leb-stock':'stockcount', '#/leb-audit':'audit', '#/leb-payroll':'payroll', '#/leb-cheques':'cheque', '#/leb-aging':'aging', '#/leb-recurring':'recurring', '#/leb-cc':'costcenter', '#/leb-forms':'vat', '#/leb-pack':'finrep', '#/leb-health':'audit', '#/guide':'guide', '#/ledger-lb':'ledger', '#/pl':'pl', '#/deductions':'ruler', '#/quotes':'bills', '#/orders':'calc', '#/budget-overview':'finrep' };
window.LA_ICONS = BASE;
window.laIcon = function(k){ var b = BASE[k] || BASE[MAP[k]]; return b? '<svg viewBox="0 0 64 64" aria-hidden="true">'+b+'</svg>' : ''; };
// بيبدّل الإيموجي بالبطاقات (‎.hub-card‎) بأيقونات مرسومة — بعد كل رسم للصفحة
function upgrade(root){
  (root||document).querySelectorAll('.hub-card .hub-icon:not([data-la])').forEach(function(el){
    var card = el.closest('.hub-card'); var nav = card && card.getAttribute('data-nav') || '';
    var t = (el.textContent||'').trim(); var k = MAP[nav] || (nav.indexOf('#/budget-category/')===0? (t==='📥'? 'inbox' : 'outbox') : (nav.indexOf('#/category')===0 || t==='🪟'? 'window' : (t==='➕'? 'plus' : '')));
    var svg = nav==='#/whish'? '<img src="/assets/whish.png" alt="Whish" style="width:100%;height:100%;object-fit:contain;border-radius:22%;filter:drop-shadow(0 6px 8px rgba(15,28,43,.18));">' : (k? window.laIcon(k) : ''); el.setAttribute('data-la','1'); if(svg){ el.innerHTML = svg; el.classList.add('la-ic'); }
  });
}
window.laUpgradeIcons = upgrade;
// ===== الشريط فوق (متل الموتير): أيقونات مرسومة للرئيسية، نقطة البيع، كلمة السر، الخروج =====
var HB = {
  home:'<path d="M14 28v28h36V28L32 12z" fill="#fde68a"/><path d="M8 30L32 8l24 22" fill="none" stroke="#ef4444" stroke-width="6.5" stroke-linecap="round" stroke-linejoin="round"/><rect x="27" y="38" width="10" height="18" rx="2" fill="#b45309"/><rect x="17" y="33" width="7.5" height="7.5" rx="1.5" fill="#38bdf8"/><rect x="39.5" y="33" width="7.5" height="7.5" rx="1.5" fill="#38bdf8"/>',
  out:'<rect x="8" y="6" width="28" height="52" rx="3" fill="#e2e8f0"/><path d="M8 9l18 5v44l-18-3z" fill="#64748b"/><circle cx="21" cy="35" r="2.2" fill="#facc15"/><path d="M33 32h23M47.5 23.5L56 32l-8.5 8.5" fill="none" stroke="#f87171" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round"/>',
  key:'<circle cx="22" cy="24" r="15" fill="#f59e0b"/><circle cx="22" cy="24" r="6" fill="#fff7ed"/><path d="M33 33l22 22" stroke="#d97706" stroke-width="8" stroke-linecap="round"/><path d="M44 44l6-6M50 50l5-5" stroke="#d97706" stroke-width="6" stroke-linecap="round"/>'
};
function hsvg(b){ return '<svg viewBox="0 0 64 64" aria-hidden="true">'+b+'</svg>'; }
function upgradeTop(){
  var lb = document.getElementById('laLangBtn'); if(lb){ var l = (lb.textContent||'').replace('🌐','').trim(); if(lb.getAttribute('data-lbl')!==l) lb.setAttribute('data-lbl', l); }
  document.querySelectorAll('.topbar .topbar-actions > .btn:not([data-la])').forEach(function(b){
    if(b.id==='laLangBtn') return;
    var txt = (b.textContent||'').replace(/[\u{1F300}-\u{1FAFF}☀-➿️]/gu,'').trim(), ic = '', cls = '';
    if(b.getAttribute('data-nav')==='#/'){ ic = hsvg(HB.home); cls = 'home'; }
    else if(b.getAttribute('data-nav')==='#/pos'){ ic = hsvg(BASE.sales); cls = 'pos'; }
    else if(/logout/i.test(b.id||'')){ ic = hsvg(HB.out); cls = 'out'; }
    else if(b.id==='selfPwBtn'){ ic = hsvg(HB.key); cls = 'ic'; }
    b.setAttribute('data-la','1'); if(!ic) return;
    b.classList.add('la-hb', 'la-hb-'+cls); b.innerHTML = ic + (txt? '<span>'+txt+'</span>' : '');
  });
}
// ===== شعار Whish بدل 📱 بكل محل فيه Whish =====
var WH_IMG = '/assets/whish.png';
function whishify(root){
  var w = document.createTreeWalker(root||document.body, NodeFilter.SHOW_TEXT, { acceptNode:function(n){ return n.nodeValue.indexOf('📱')>=0? 1 : 3; } });
  var list = [], n; while((n = w.nextNode())) list.push(n);
  list.forEach(function(t){
    var p = t.parentElement; if(!p || /^(OPTION|SCRIPT|STYLE|TEXTAREA|TITLE)$/.test(p.tagName)) return;
    var ctx = (p.closest('button,label,td,th,h2,h3,div,span,b,a')||p).textContent||'';
    if(!/whish|ويش/i.test(ctx) || ctx.length>400) return;
    var parts = t.nodeValue.split('📱'), frag = document.createDocumentFragment();
    parts.forEach(function(x,i){ if(i){ var im = document.createElement('img'); im.src = WH_IMG; im.alt = 'Whish'; im.className = 'wh-ic'; frag.appendChild(im); } if(x) frag.appendChild(document.createTextNode(x)); });
    p.replaceChild(frag, t);
  });
}
window.laWhishify = whishify;

/* ===== ☁️ Google Drive + 💬 WhatChimp لبرامج المحاسبة — البرنامج بيعرّف window.LA_APP ===== */
// النسخة المحلية (الإصدار 2.0.2+) بتمرّق الطلب عبر السيرفر المحلي حتى يضيف جلسة صاحب المحل
var API = (window.LA_LOCAL && !window.LA_LOCAL.mirror && window.LA_LOCAL.accProxy) ? '/local-api/acc-int' : 'https://libanapps.com/api/acc-int';
var ST = null, STAT_AT = 0;
function A(){ return window.LA_APP || null; }
// جلسة البرنامج (بالسحابة) — السيرفر بيطلبها أول مرة بينسجّل فيها مفتاح الربط
async function H(extra){ var h = Object.assign({}, extra||{}); try{ var a = A(); var t = a && a.token ? await a.token() : ''; if(t) h.Authorization = 'Bearer ' + t; }catch(e){} return h; }
async function call(op, extra){
  var a = A(); if(!a || !a.cid()) throw new Error('no_client');
  var r = await fetch(API, { method:'POST', headers: await H({'Content-Type':'application/json'}), body: JSON.stringify(Object.assign({ op:op, cid:a.cid(), product:a.product, key: await a.key() }, extra||{})) });
  var j = await r.json().catch(function(){ return {}; }); if(!r.ok || j.ok===false){ var e = new Error(j.error||('http_'+r.status)); e.j = j; throw e; } return j;
}
async function status(force){ if(!force && ST && Date.now()-STAT_AT < 60000) return ST; try{ ST = await call('status'); STAT_AT = Date.now(); }catch(e){ ST = { err:e.message }; } return ST; }
window.laIntStatus = status;
function errTxt(e){ var m = String(e && e.message || e); return ({ gd_not_configured:'ربط Google Drive مش مفعّل عالسيرفر بعد', gd_off:'Google Drive مش مربوط', need_login:'افتح البرنامج من رابطه وسجّل دخول أول، وبعدين اربط', key_mismatch:'مفتاح الربط مش مطابق — تواصل مع LibanApps', no_client:'افتح البرنامج من رابطو الرسمي أول', wc_bad_key:'مفتاح WhatChimp غلط', wc_no_key:'حط مفتاح WhatChimp أول', bad_key:'مفتاح WhatChimp غلط' })[m] || (m.indexOf('gd_token')===0? 'انتهى ربط Google Drive — افصلو واربطو من جديد' : /^gd_folder(:(401|403)|$)/.test(m)? 'Google ما عطى إذن Drive — كبوس «فصل Drive» واربطو من جديد، وبشاشة Google علّم صح على «الوصول لملفات Google Drive»' : m.indexOf('gd_folder')===0? 'ما قدرنا نعمل مجلد على Drive ('+m.slice(10)+')' : m); }
function T(msg){ var a = A(); if(a && a.toast) a.toast(msg); }
// رفع نسخة احتياطية على Drive (why: logout / daily / manual)
window.laDriveBackup = async function(why){
  var a = A(); if(!a) return { ok:false };
  var st = await status(); if(!st || !st.gd || !st.gd.on) return { ok:false, error:'gd_off' };
  var body = a.backup();
  var u = API + '/upload?' + new URLSearchParams({ cid:a.cid(), product:a.product, key: await a.key(), name: a.name()||'', why: why||'' }).toString();
  var r = await fetch(u, { method:'POST', headers: await H({'Content-Type':'application/json'}), body: body });
  var j = await r.json().catch(function(){ return {}; }); if(r.ok && j.ok){ ST = null; } return j;
};
// نسخة يومية تلقائية (مرة كل يوم) — للمدير
window.laDriveDaily = async function(){
  try{ var a = A(); if(!a || !a.canAdmin()) return; var st = await status(); if(!st || !st.gd || !st.gd.on) return;
    var last = st.gd.last_at? Date.parse(st.gd.last_at) : 0; if(Date.now()-last < 20*3600000) return;
    await window.laDriveBackup('daily'); }catch(e){}
};
// نسخة كل ساعة بالخفاء (من أي جهاز فاتح البرنامج، بلا ما يبيّن شي للموظف)
var _hourlyBusy = false;
window.laDriveHourly = async function(){
  if(_hourlyBusy) return; _hourlyBusy = true;
  try{ var a = A(); if(!a || !a.cid() || (a.loggedIn && !a.loggedIn())) return;
    if(a.hasKey && !a.hasKey() && !a.canAdmin()) return;   // الموظف ما بيولّد مفتاح ربط جديد
    var st = await status(true); if(!st || !st.gd || !st.gd.on) return;
    var last = st.gd.last_at? Date.parse(st.gd.last_at) : 0; if(Date.now()-last < 55*60000) return;
    await window.laDriveBackup('hourly');
  }catch(e){} finally{ _hourlyBusy = false; }
};
(function(){ var started = false;
  function go(){ if(started) return; started = true;
    setTimeout(function(){ window.laDriveHourly(); }, 90000);
    setInterval(function(){ window.laDriveHourly(); }, 10*60000); }
  var iv = setInterval(function(){ var a = A(); if(a && a.cid() && (!a.loggedIn || a.loggedIn())){ clearInterval(iv); go(); } }, 15000);
})();
// WhatChimp: كل زبون جديد أو تعديل رقم → جهة اتصال
var _wcMap = null;
window.laWcCustomersSaved = function(list){
  var a = A(); if(!a || !Array.isArray(list)) return;
  var m = {}; list.forEach(function(c){ if(c && !c.deleted && c.phone) m[c.id] = String(c.phone)+'|'+String(c.name||''); });
  var prev = _wcMap; _wcMap = m; if(!prev) return;
  if(!ST || !ST.wc || !ST.wc.on) return;
  Object.keys(m).forEach(function(id){ if(prev[id]!==m[id]){ var c = list.find(function(x){ return x.id===id; }); if(c) call('wc_upsert', { phone:c.phone, name:c.name }).catch(function(){}); } });
};
window.laIntCardHtml = function(){
  return '<div class="card" id="laIntDrive"><h2><span class="dot"></span> ☁️ نسخ احتياطي على Google Drive</h2>'
    + '<p style="font-size:12.5px; color:var(--ink-soft); line-height:1.7;">بيرفع نسخة كاملة من البيانات على Google Drive تبعك: <b>كل يوم مرة</b> و<b>عند الخروج</b>. النسخ الأقدم من 30 يوم بتنمحى لحالها.</p>'
    + '<div class="la-int-body" data-int="gd" style="font-size:13.5px;">⏳ ...</div></div>'
    + '<div class="card" id="laIntWc"><h2><span class="dot"></span> 💬 WhatsApp — WhatChimp API</h2>'
    + '<p style="font-size:12.5px; color:var(--ink-soft); line-height:1.7;">اعمل مفتاح API من WhatChimp: Settings ← Integrations ← API keys ← Create API key (صلاحية «Contacts and labels»)، والصقو هون. المفتاح بينحفظ عالسيرفر وما بيبيّن بعد الحفظ. بعدها كل زبون إلو رقم بينضاف جهة اتصال على WhatChimp تحت التصنيف يلي بتختارو.</p>'
    + '<div class="la-int-body" data-int="wc" style="font-size:13.5px;">⏳ ...</div></div>';
};
function fmtD(t){ try{ return new Date(t).toLocaleString('en-GB',{day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'}); }catch(e){ return t; } }
async function fillInt(){
  var boxes = document.querySelectorAll('.la-int-body:not([data-filled])'); if(!boxes.length) return;
  boxes.forEach(function(b){ b.setAttribute('data-filled','1'); });
  var st = await status(true);
  boxes.forEach(function(b){
    if(st.err==='need_login' || st.err==='key_mismatch'){
      b.innerHTML = '<div style="margin-bottom:8px;">🔐 قبل أول ربط، أكّد إنو هالنسخة إلك: بتنفتح صفحة libanapps.com، بتسجّل دخول بحساب صاحب المؤسسة وبتكبس «أكّد». بعدها بترجع هون وبتربط عادي — من أي مكان، أونلاين أو محلي.</div>'
        + '<div class="action-row"><button class="btn btn-primary" data-la-int="pair">🔐 تأكيد الربط بحساب libanapps.com</button>'
        + (b.getAttribute('data-int')==='gd'? '<button class="btn" data-la-int="dl_now">⬇ تنزيل نسخة عالجهاز</button>' : '') + '</div>';
      return; }
    if(st.err){ b.innerHTML = '<span style="color:var(--debit);">⚠️ '+errTxt(st.err)+'</span>'; return; }
    if(b.getAttribute('data-int')==='gd'){
      var g = st.gd||{};
      b.innerHTML = g.on
        ? '<div>✅ مربوط بـ <b dir="ltr">'+(g.email||'Google')+'</b></div><div style="color:var(--ink-soft); margin:4px 0 10px;">آخر نسخة: '+(g.last_at? '<b class="num">'+fmtD(g.last_at)+'</b>' : 'بعد ما انرفعت ولا نسخة')+(g.last_err? ' — <span style="color:var(--debit);">'+errTxt(g.last_err)+'</span>' : '')+'</div>'
          + '<div class="action-row"><button class="btn btn-primary" data-la-int="gd_now">☁️ نسخة على Drive هلق</button><button class="btn" data-la-int="gd_restore">↺ استرجاع نسخة من Drive</button><button class="btn" data-la-int="dl_now">⬇ تنزيل نسخة عالجهاز</button><button class="btn btn-danger" data-la-int="gd_unlink">فصل Drive</button></div>'
        : (st.gd_conf===false? '<div style="color:var(--debit);">ربط Google Drive مش مفعّل عالسيرفر بعد</div>' : '<div style="margin-bottom:10px;">❌ مش مربوط</div><div class="action-row"><button class="btn btn-primary" data-la-int="gd_link">🔗 ربط Google Drive</button><button class="btn" data-la-int="dl_now">⬇ تنزيل نسخة عالجهاز</button></div>');
    } else {
      var w = st.wc||{};
      b.innerHTML = (w.on? '<div style="margin-bottom:8px;">✅ مفتاح WhatChimp محفوظ</div>' : '<div style="margin-bottom:8px;">❌ ما في مفتاح بعد</div>')
        + '<div class="grid grid-2"><div class="field" style="margin:0;"><label>مفتاح API</label><input type="password" id="laWcKey" placeholder="'+(w.on? '•••••••• (محفوظ — اكتب جديد لتغيّرو)' : 'الصق المفتاح هون')+'" dir="ltr"></div>'
        + '<div class="field" style="margin:0;"><label>تصنيف جهات الاتصال (Label)</label><input type="text" id="laWcLabel" value="'+String(w.label||'زبائن').replace(/"/g,'&quot;')+'"></div></div>'
        + '<div class="action-row" style="margin-top:10px;"><button class="btn btn-primary" data-la-int="wc_save">💾 حفظ</button>'
        + (w.on? '<button class="btn" data-la-int="wc_sync">🔄 إضافة كل الزباين على WhatChimp</button><button class="btn btn-danger" data-la-int="wc_clear">شيل المفتاح</button>' : '') + '</div><div id="laWcMsg" style="font-size:12.5px; margin-top:6px;"></div>';
    }
  });
}
document.addEventListener('click', async function(e){
  var b = e.target.closest && e.target.closest('[data-la-int]'); if(!b) return; e.preventDefault();
  var a = A(); if(!a) return; var op = b.getAttribute('data-la-int');
  var redo = function(){ document.querySelectorAll('.la-int-body').forEach(function(x){ x.removeAttribute('data-filled'); }); ST = null; fillInt(); };
  try{
    if(op==='dl_now'){ a.download(); return; }
    if(op==='pair'){
      if(!(window.crypto && crypto.subtle)){ T('⚠️ افتح البرنامج من رابط https أو من الكمبيوتر الأساسي'); return; }
      var kk = await a.key(); var hb = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(String(kk)));
      var kh = Array.from(new Uint8Array(hb)).map(function(x){ return x.toString(16).padStart(2,'0'); }).join('');
      var pu = 'https://libanapps.com/acc-pair?' + new URLSearchParams({ cid:a.cid(), product:a.product, kh:kh }).toString();
      var wn = window.open(pu, '_blank'); if(!wn) location.href = pu;
      b.disabled = true; b.textContent = '⏳ ناطر التأكيد…';
      var tries = 0; var iv = setInterval(async function(){ tries++; ST = null; var s2 = await status(true);
        if(!s2.err){ clearInterval(iv); T('✅ تأكّد الربط — هلق فيك تربط Google Drive'); redo(); }
        else if(tries > 60){ clearInterval(iv); b.disabled = false; b.textContent = '🔐 تأكيد الربط بحساب libanapps.com'; } }, 4000);
      return; }
    if(op==='gd_link'){ var j = await call('gd_auth_url', { ret: location.href.split('#')[0] }); location.href = j.url; return; }
    if(op==='gd_unlink'){ if(!confirm('فصل Google Drive؟ النسخ يلي عليه بتضل.')) return; await call('gd_unlink'); T('انفصل Google Drive'); redo(); return; }
    if(op==='gd_now'){ b.disabled = true; b.textContent = '⏳ عم يرفع…'; var r = await window.laDriveBackup('manual'); T(r && r.ok? '☁️ انرفعت النسخة على Google Drive ✅' : '⚠️ '+errTxt(r && r.error)); redo(); return; }
    if(op==='gd_restore'){ var l = await call('gd_list'); openRestore(l.files||[]); return; }
    if(op==='wc_save'){ var k = (document.getElementById('laWcKey')||{}).value||'', lab = (document.getElementById('laWcLabel')||{}).value||'';
      if(k.trim()) await call('wc_set', { wc_key:k.trim(), wc_label:lab }); else await call('wc_label', { wc_label:lab });
      T('تم الحفظ ✅'); redo(); return; }
    if(op==='wc_clear'){ if(!confirm('شيل مفتاح WhatChimp؟')) return; await call('wc_clear'); redo(); return; }
    if(op==='wc_sync'){ var cs = a.contacts(); b.disabled = true; var r2 = await call('wc_sync', { contacts: cs }); var mm = document.getElementById('laWcMsg'); if(mm) mm.textContent = '✅ انبعتو '+(r2.count||0)+' رقم على WhatChimp — عم يتضافو هلق'; b.disabled = false; return; }
  }catch(err){ T('⚠️ '+errTxt(err)); b.disabled = false; }
});
// الرجعة من شاشة Google: ‎#/settings?gd=ok|no_scope|denied|...
(function(){ var m = String(location.hash).match(/[?&]gd=([a-z_]+)/); if(!m) return;
  var q = m[1]; try{ history.replaceState(null, '', location.pathname + location.search + location.hash.replace(/[?&]gd=[a-z_]+/, '')); }catch(e){}
  var msg = q==='ok'? '☁️ انربط Google Drive ✅' : q==='no_scope'? '⚠️ ما انعطى إذن Drive — اربط من جديد وعلّم صح على «الوصول لملفات Google Drive»' : q==='denied'? '⚠️ انلغى الربط' : '⚠️ ما زبط الربط ('+q+')';
  var tries = 0; var iv = setInterval(function(){ tries++; if(A() && A().toast){ clearInterval(iv); A().toast(msg); } else if(tries > 40) clearInterval(iv); }, 250); })();
var _homeOnce = false;
function onHome(){ if(_homeOnce || !document.querySelector('.hub-grid') || !A()) return; _homeOnce = true;
  setTimeout(function(){ status(true).then(function(){ try{ window.laWcCustomersSaved(A().customers()); }catch(e){} window.laDriveDaily(); }); }, 4000); }
function openRestore(files){
  var a = A(); var w = document.createElement('div'); w.className = 'modal-bg';
  w.innerHTML = '<div class="modal" style="max-width:520px;"><h3>↺ استرجاع نسخة من Google Drive</h3><div style="font-size:12.5px; color:var(--debit); margin-bottom:8px;">⚠️ الاسترجاع بيستبدل كل البيانات الحالية بالنسخة يلي بتختارها.</div>'
    + (files.length? '<div style="max-height:50vh; overflow:auto;">'+files.map(function(f){ return '<div style="display:flex; justify-content:space-between; gap:8px; align-items:center; padding:6px 0; border-bottom:1px dashed var(--line);"><span><b dir="ltr" style="font-size:12.5px;">'+f.name+'</b><br><small class="num" style="color:var(--ink-soft);">'+fmtD(f.createdTime)+' · '+Math.round((+f.size||0)/1024)+' KB</small></span><button class="btn btn-sm btn-primary" data-gd-pick="'+f.id+'">استرجاع</button></div>'; }).join('')+'</div>' : '<div>ما في نسخ على Drive بعد</div>')
    + '<div class="row" style="margin-top:10px;"><button class="btn" id="gdr_x">إغلاق</button></div></div>';
  document.body.appendChild(w);
  w.querySelector('#gdr_x').addEventListener('click', function(){ w.remove(); });
  w.querySelectorAll('[data-gd-pick]').forEach(function(btn){ btn.addEventListener('click', async function(){
    if(!confirm('أكيد؟ رح تتبدّل كل البيانات الحالية بهالنسخة.')) return;
    btn.disabled = true; btn.textContent = '⏳';
    try{ var r = await fetch(API, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ op:'gd_get', id:btn.getAttribute('data-gd-pick'), cid:a.cid(), product:a.product, key: await a.key() }) });
      if(!r.ok) throw new Error('http_'+r.status); var data = await r.json(); w.remove(); await a.restore(data); }
    catch(e){ T('⚠️ '+errTxt(e)); btn.disabled = false; btn.textContent = 'استرجاع'; }
  }); });
}
var _q = false; var mo = new MutationObserver(function(){ if(_q) return; _q = true; requestAnimationFrame(function(){ _q = false; mo.disconnect(); try{ upgrade(); upgradeTop(); whishify(); fillInt(); onHome(); }catch(e){} mo.observe(document.body, {childList:true, subtree:true, characterData:true}); }); });
function start(){ upgrade(); upgradeTop(); whishify(); mo.observe(document.body, {childList:true, subtree:true, characterData:true}); }
if(document.body) start(); else document.addEventListener('DOMContentLoaded', start);

// صفحة الدخول: يسار صورة وتعريف، يمين مربع الدخول — نفس الـ IDs يلي بيستعملها البرنامج
window.laLoginShell = function(o){
  o = o || {};
  var ill = (o.ill || ['sales','cash','stock']).map(function(k){ return BASE[k]; }).map(function(b,i){ return '<svg viewBox="0 0 64 64" aria-hidden="true">'+b+'</svg>'; }).join('');
  var user = '<svg viewBox="0 0 64 64" aria-hidden="true"><circle cx="32" cy="22" r="12" fill="#f2b98a"/><path d="M20 20a12 12 0 0 1 24 0c-4-4-8-5-12-5s-8 1-12 5z" fill="#334155"/><path d="M8 60a24 24 0 0 1 48 0z" fill="#3b82f6"/></svg>';
  var lock = '<svg viewBox="0 0 64 64" aria-hidden="true"><rect x="10" y="28" width="44" height="32" rx="7" fill="#f59e0b"/><path d="M19 28v-8a13 13 0 0 1 26 0v8" fill="none" stroke="#64748b" stroke-width="6"/><circle cx="32" cy="42" r="5" fill="#7c2d12"/><rect x="30" y="44" width="4" height="9" rx="2" fill="#7c2d12"/></svg>';
  return '<div class="la-gate"><div class="la-hero"><div class="la-ill">'+ill+'</div><h2>'+(o.heroTitle||'برنامج المحاسبة')+'</h2><p>'+(o.heroText||'فواتير، صناديق، مخزون وكشوفات حساب — كلو بمحل واحد ومباشر على كل الأجهزة.')+'</p>'
    +'<div class="la-feat">'+(o.feats||['🧾 فواتير','🗄 صناديق','📦 مخزون','📒 كشوفات']).map(function(f){ return '<span>'+f+'</span>'; }).join('')+'</div></div>'
    +'<div class="la-side"><div class="la-box">'+(o.logo? '<img src="'+o.logo+'" alt="">' : '')+'<h1>'+(o.title||'تسجيل الدخول')+'</h1>'+(o.sub? '<div class="la-sub">'+o.sub+'</div>' : '')
    +'<div class="la-form">'
    +'<div class="la-fld"><label for="login_user">اسم المستخدم</label><div class="la-in">'+user+'<input type="text" id="login_user" autocomplete="username" autocapitalize="off" spellcheck="false"></div></div>'
    +'<div class="la-fld"><label for="login_pass">كلمة السر</label><div class="la-in">'+lock+'<input type="password" id="login_pass" autocomplete="current-password"><button type="button" class="la-peek" onclick="var i=document.getElementById(\'login_pass\'); i.type=i.type===\'password\'?\'text\':\'password\';">👁️</button></div></div>'
    +'<div id="login_err" class="la-err"></div><button class="btn btn-primary la-btn" id="loginBtn">دخول</button><div id="wa_login_slot"></div></div>'
    +(o.footer||'')+'</div></div></div>';
};

var css = `
.hub-card{background:transparent!important; border:0!important; box-shadow:none!important; padding:12px 8px 10px!important; border-radius:18px!important;}
.hub-card:hover{background:rgba(12,59,94,.06)!important; transform:none!important;}
.hub-card .hub-icon.la-ic{width:84px; height:84px; margin:0 auto 8px; font-size:0; transition:transform .2s cubic-bezier(.2,.8,.3,1.4);}
.hub-card:hover .hub-icon.la-ic{transform:translateY(-4px) scale(1.06);}
.hub-card:active .hub-icon.la-ic{transform:scale(.94);}
.hub-card .hub-icon.la-ic svg{width:100%; height:100%; display:block; filter:drop-shadow(0 6px 8px rgba(15,28,43,.18));}
.hub-card .hub-title{font-size:15.5px!important;}
.hub-card .hub-sub{font-size:12px!important;}
.hub-grid{grid-template-columns:repeat(auto-fill,minmax(170px,1fr))!important; gap:10px!important;}
@media(min-width:1100px){ .hub-grid{grid-template-columns:repeat(5,1fr)!important;} .hub-card .hub-icon.la-ic{width:92px; height:92px;} }
@media(max-width:640px){ .hub-grid{grid-template-columns:repeat(2,1fr)!important; gap:4px!important;} .hub-card .hub-icon.la-ic{width:66px; height:66px;} .hub-card .hub-title{font-size:14px!important;} .hub-card .hub-sub{display:none;} }
.la-gate{position:fixed; inset:0; z-index:60; overflow:auto; display:grid; grid-template-columns:1.05fr 1fr; background:#f4f6fa; font-family:inherit;}
.la-hero{position:relative; overflow:hidden; background:radial-gradient(120% 90% at 85% 10%,#1d5f93 0%,#0c3b5e 45%,#071f33 100%); color:#fff; display:flex; flex-direction:column; justify-content:center; align-items:center; padding:48px 40px; text-align:center;}
.la-hero::before{content:""; position:absolute; inset:-30%; background:conic-gradient(from 210deg at 50% 50%,transparent 0 60%,rgba(245,164,0,.18) 70%,transparent 80%); animation:laspin 26s linear infinite;}
@keyframes laspin{to{transform:rotate(360deg)}}
.la-hero>*{position:relative}
.la-ill{display:flex; gap:18px; align-items:flex-end; justify-content:center; margin:26px 0 8px;}
.la-ill svg{width:84px; height:84px; filter:drop-shadow(0 10px 14px rgba(0,0,0,.35)); animation:lafloat 5s ease-in-out infinite;}
.la-ill svg:nth-child(2){width:112px; height:112px; animation-delay:-1.6s;} .la-ill svg:nth-child(3){animation-delay:-3.2s;}
@keyframes lafloat{50%{transform:translateY(-10px)}}
.la-hero h2{font-size:30px; margin:14px 0 6px; font-weight:800; color:#fff;}
.la-hero p{margin:0; opacity:.85; font-size:15.5px; max-width:420px; line-height:1.7;}
.la-feat{display:flex; gap:10px; flex-wrap:wrap; justify-content:center; margin-top:22px;}
.la-feat span{background:rgba(255,255,255,.1); border:1px solid rgba(255,255,255,.18); padding:6px 12px; border-radius:999px; font-size:13px; font-weight:700;}
.la-side{position:relative; z-index:1; display:flex; align-items:center; justify-content:center; padding:32px 22px;}
.la-box{background:#fff; border-radius:24px; box-shadow:0 1px 2px rgba(15,28,43,.06),0 24px 60px -20px rgba(15,28,43,.35); padding:34px 30px 22px; max-width:420px; width:100%; text-align:center; border:1px solid #e5e9f0;}
.la-box img{width:104px; height:104px; object-fit:contain; margin:0 auto 10px; display:block; filter:drop-shadow(0 8px 12px rgba(15,28,43,.18));}
.la-box h1{font-size:25px; margin:2px 0 4px; color:#0c3b5e; font-weight:800;}
.la-sub{font-size:14px; color:#64748b;}
.la-form{text-align:start; margin-top:22px;}
.la-fld{margin-bottom:14px;} .la-fld label{font-weight:700; font-size:13.5px; color:#334155; margin-bottom:6px; display:block;}
.la-in{position:relative;}
.la-in svg{position:absolute; top:50%; inset-inline-start:14px; transform:translateY(-50%); width:22px; height:22px; pointer-events:none;}
.la-in input{width:100%; height:54px; border-radius:14px; padding-inline-start:46px!important; font-size:16px; border:1.5px solid #e2e8f0; background:#f8fafc; box-sizing:border-box;}
.la-in input:focus{background:#fff; border-color:#0c3b5e; box-shadow:0 0 0 4px rgba(12,59,94,.12); outline:none;}
.la-peek{position:absolute; top:50%; inset-inline-end:8px; transform:translateY(-50%); border:0; background:transparent; cursor:pointer; padding:8px; border-radius:10px; font-size:18px; line-height:1;}
.la-err{color:#dc2626; font-size:13px; min-height:18px; margin-bottom:6px;}
.la-btn{width:100%; height:56px; border-radius:14px!important; font-size:17px!important; font-weight:800; justify-content:center; background:linear-gradient(135deg,#1d5f93,#0c3b5e)!important; border:0!important; color:#fff!important; box-shadow:0 12px 24px -10px rgba(12,59,94,.7);}
.la-box .app-footer{margin-top:16px;}
@media (max-width:899px){
  .la-gate{grid-template-columns:1fr; grid-template-rows:auto 1fr;}
  .la-hero{padding:28px 18px 70px;} .la-hero h2{font-size:22px;} .la-hero p{font-size:14px;} .la-feat{display:none;}
  .la-ill{margin:10px 0 0;} .la-ill svg{width:58px; height:58px;} .la-ill svg:nth-child(2){width:76px; height:76px;}
  .la-side{padding:0 14px 24px; margin-top:-56px; align-items:flex-start;}
  .la-box{padding:26px 18px 18px; border-radius:22px;}
}
@media print{ .la-gate{display:none;} }
.wh-ic{height:1.3em; width:auto; vertical-align:-0.3em; border-radius:22%; margin-inline:1px;}
.stat .k .wh-ic, h2 .wh-ic{height:1.5em;}
/* الشريط فوق: فاتح متل الموتير */
.topbar{background:#fff!important; color:#0f172a!important; border:1px solid #e5e9f0; box-shadow:0 4px 14px -10px rgba(15,28,43,.25)!important; padding:10px 14px!important;}
.topbar::before{display:none!important;}
.topbar .brand .name{color:#0c3b5e!important;} .topbar .brand .tag{color:#64748b!important;}
.topbar .brand img{height:56px!important; width:auto; filter:drop-shadow(0 4px 6px rgba(15,28,43,.18));}
.topbar-actions{align-items:center; flex-wrap:wrap; justify-content:flex-end;}
.topbar-actions .btn, #laLangBtn{display:inline-flex!important; align-items:center; gap:8px; height:48px; padding:0 14px 0 10px!important; border-radius:14px!important; border:1px solid #e5e9f0!important; background:#fff!important; color:#0c3b5e!important; box-shadow:0 1px 2px rgba(15,28,43,.06),0 6px 14px -8px rgba(15,28,43,.25)!important; font-weight:800!important; font-size:15px!important;}
.topbar-actions .btn:hover, #laLangBtn:hover{background:#f1f5f9!important;}
.la-hb svg{width:32px; height:32px; flex:none; filter:drop-shadow(0 2px 2px rgba(0,0,0,.15));}
.la-hb-pos{background:#fff7ed!important; border-color:#fed7aa!important; color:#9a3412!important;}
.la-hb-out{background:#fef2f2!important; border-color:#fecaca!important; color:#b91c1c!important;}
.la-hb-ic{padding:0 8px!important;}
.topbar-actions #laLangBtn{font-size:0!important; padding:0 10px!important;}
.topbar-actions #laLangBtn::before{content:""; width:30px; height:30px; background:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Ccircle cx='32' cy='32' r='25' fill='%233b82f6'/%3E%3Cpath d='M17 15c5 3 3 9 9 10s3 9-2 11-3 8-8 6c-6-5-9-12-8-20 2-3 5-5 9-7z' fill='%234ade80'/%3E%3Cpath d='M40 10c6 2 12 8 14.5 15-5 1-7 5-11 4s-3-7-7-9 0-8 3.5-10z' fill='%234ade80'/%3E%3Cpath d='M42 40c4-1 8 1 9.5 4-2 5-6 9-11 11-1-5-2.5-12 1.5-15z' fill='%234ade80'/%3E%3C/svg%3E") center/contain no-repeat;}
.topbar-actions #laLangBtn::after{content:attr(data-lbl); font-size:15px; font-weight:800; color:#0c3b5e;}
@media(max-width:640px){ .topbar-actions .btn, #laLangBtn{height:42px; padding:0 8px!important;} .la-hb span{display:none;} .la-hb svg{width:28px; height:28px;} .topbar .brand img{height:40px!important;} }

`;
var st = document.createElement('style'); st.id = 'la-home-css'; st.textContent = css; (document.head||document.documentElement).appendChild(st);
})();
