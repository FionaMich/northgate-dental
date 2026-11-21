-- Plain names everywhere people read them (Fiona, 2026-11-21): clinics, staff and dentists lose the "(synthetic)" and
-- "Synthetic" wording, so it no longer reaches patient emails, receipts or the portal. The safety controls stay:
-- is_synthetic on every patient, and patient email addresses limited to .synthetic domains, so real details cannot
-- be stored.
update public.organisation set name = replace(name, ' (synthetic)', '') where name like '% (synthetic)';
update public.locations set name = replace(name, ' (synthetic)', '') where name like '% (synthetic)';

update public.profiles
   set display_name = regexp_replace(regexp_replace(display_name, '^Synthetic ', ''), ' \(synthetic ([^)]+)\)', ' (\1)')
 where display_name ~* 'synthetic';

update public.practitioners
   set display_name = regexp_replace(regexp_replace(display_name, '^Synthetic ', ''), ' \(synthetic ([^)]+)\)', ' (\1)')
 where display_name ~* 'synthetic';
