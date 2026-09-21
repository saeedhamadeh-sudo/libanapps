-- ============================================================
--  ترقية: حذف الزبون يحذف مطاعمه وكل بياناتها
--  (الأصناف، الأقسام، الطلبات، الفواتير، السلايدر، العروض)
--  شغّله لحاله، أو شغّل schema.sql كامل
--  لا يحذف أي بيانات موجودة — يغيّر قاعدة الحذف فقط
-- ============================================================

alter table public.restaurants add column if not exists client_id uuid;

-- ترقية للقواعد القديمة: حذف الزبون يحذف مطاعمه معه
do $$
declare cname text;
begin
  select con.conname into cname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_attribute att on att.attrelid = rel.oid and att.attnum = con.conkey[1]
   where rel.relname = 'restaurants' and con.contype = 'f' and att.attname = 'client_id';
  if cname is not null then
    execute format('alter table public.restaurants drop constraint %I', cname);
  end if;
  alter table public.restaurants
    add constraint restaurants_client_id_fkey
    foreign key (client_id) references public.clients(id) on delete cascade;
end $$;
