-- ============================================================
--  LibanApps — ربط السائق بفرع معين (اختياري)
--  آمن للتشغيل أكثر من مرة
-- ============================================================

alter table public.drivers
  add column if not exists branch_id uuid references public.restaurant_branches(id) on delete set null;

create index if not exists drivers_branch_idx on public.drivers (branch_id);

-- تحقق
select id, name, branch_id from public.drivers limit 10;
