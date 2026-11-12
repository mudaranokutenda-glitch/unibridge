-- OPTIONAL. Run only if you really want it. It cannot be undone.
-- Removes the old student ID (inscription number) that sign-up used to store
-- in profiles. The inscription number in student_records (Student space)
-- is NOT touched.
--
-- Run AFTER 2026-11-11-01-no-student-id-at-signup.sql.

begin;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name = 'inscription_number'
  ) then
    execute 'update public.profiles set inscription_number = null
             where inscription_number is not null';
  end if;
end $$;

commit;
