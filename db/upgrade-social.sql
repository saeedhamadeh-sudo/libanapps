-- ============================================================
--  ترقية: روابط التواصل بتذييل المنيو
--  شغّله لحاله، أو شغّل schema.sql كامل — ما بيحذف أي بيانات
-- ============================================================

alter table public.restaurants add column if not exists instagram text default '';
alter table public.restaurants add column if not exists facebook  text default '';
alter table public.restaurants add column if not exists tiktok    text default '';
