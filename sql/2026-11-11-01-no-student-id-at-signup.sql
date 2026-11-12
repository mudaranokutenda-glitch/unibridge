-- Stage 1, item 1. Sign-up no longer asks for the student ID (inscription number).
-- Run AFTER all 2026-11-05 files. Safe to run twice. Deletes nothing.
--
-- What it does:
--   * profiles.inscription_number may now be empty (NULL).
--   * Every NEW profile is saved with inscription_number = NULL, whatever
--     handle_new_user() sends. This is done with a small trigger on profiles,
--     so the existing handle_new_user() (which is not in this project's files)
--     does not need to be rewritten.
--   * Old values are NOT removed here. That is the separate optional file
--     2026-11-11-99-optional-clear-old-student-ids.sql.
--   * The inscription number inside student_records (Student space) stays.

begin;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name = 'inscription_number'
  ) then
    execute 'alter table public.profiles alter column inscription_number drop not null';

    execute $f$
      create or replace function public.profiles_no_inscription()
      returns trigger
      language plpgsql
      as $body$
      begin
        new.inscription_number := null;
        return new;
      end;
      $body$
    $f$;

    execute 'drop trigger if exists profiles_no_inscription on public.profiles';
    execute 'create trigger profiles_no_inscription
             before insert on public.profiles
             for each row execute function public.profiles_no_inscription()';
  else
    raise notice 'profiles.inscription_number does not exist: nothing to do.';
  end if;
end $$;

commit;
