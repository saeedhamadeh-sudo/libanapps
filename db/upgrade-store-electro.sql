-- إضافة ثيم Electro — شغّله إذا كنت شغّلت upgrade-store-v2.sql سابقاً (آمن للتكرار)
do $$
declare c record;
begin
  for c in select conname from pg_constraint
           where conrelid = 'public.stores'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%theme%'
  loop execute format('alter table public.stores drop constraint %I', c.conname); end loop;
end $$;
alter table public.stores add constraint stores_theme_chk
  check (theme in ('nova','aurum','pulse','bloom','atelier','electro'));
select 'electro theme allowed' as item, true as ok;
