-- The four test accounts for the files in sql/tests. Run this file ONCE, before the tests.
-- Safe to run twice: it updates the emails.
--
-- HOW TO USE
--   1. Open this file in the Supabase SQL Editor (not in VS Code).
--   2. In the editor ONLY, replace the four placeholders below with the real emails of four
--      DIFFERENT accounts (the emails you use to log in to the app):
--        STUDENT-A-EMAIL  a student, with a student record, in the Governor's wilaya
--        STUDENT-B-EMAIL  another student, in a DIFFERENT wilaya
--        GOVERNOR-EMAIL   a Governor (role rep) whose rep_wilaya is Student A's wilaya
--        ATTACHE-EMAIL    the Educational Attache (role attache) - or your own admin account
--   3. Press Run. The four rows are shown at the end.
--   Never save your real emails in this file in the project. If you want a local copy
--   with your emails, name it 00-test-accounts.local.sql (git ignores that name).
--
-- WHO CAN DO WHAT (test_support.accounts)
--   anon, authenticated (the app) : nothing (no rights on the schema or the table,
--                                   and row-level security on with no policy)
--   the owner (SQL Editor)        : everything
-- The schema test_support is NOT exposed by the API. Run 99-remove-test-accounts.sql
-- before launch: it drops the schema and the emails with it.

begin;

do $$
declare
  a_mail text := 'STUDENT-A-EMAIL';
  b_mail text := 'STUDENT-B-EMAIL';
  g_mail text := 'GOVERNOR-EMAIL';
  t_mail text := 'ATTACHE-EMAIL';
begin
  if position('@' in a_mail) = 0 or position('@' in b_mail) = 0
     or position('@' in g_mail) = 0 or position('@' in t_mail) = 0 then
    raise exception 'SETUP PROBLEM: replace STUDENT-A-EMAIL, STUDENT-B-EMAIL, GOVERNOR-EMAIL and ATTACHE-EMAIL in this file (in the SQL Editor) with four real emails.';
  end if;
  if lower(trim(a_mail)) in (lower(trim(b_mail)), lower(trim(g_mail)), lower(trim(t_mail)))
     or lower(trim(b_mail)) in (lower(trim(g_mail)), lower(trim(t_mail)))
     or lower(trim(g_mail)) = lower(trim(t_mail)) then
    raise exception 'SETUP PROBLEM: the four emails must belong to four different accounts (an email is used twice).';
  end if;

  create schema if not exists test_support;
  revoke all on schema test_support from public, anon, authenticated;

  create table if not exists test_support.accounts (
    key   text primary key check (key in ('STUDENT_A', 'STUDENT_B', 'GOVERNOR', 'ATTACHE')),
    email text not null check (position('@' in email) > 1)
  );
  revoke all on table test_support.accounts from public, anon, authenticated;
  alter table test_support.accounts enable row level security;

  insert into test_support.accounts (key, email) values
    ('STUDENT_A', trim(a_mail)),
    ('STUDENT_B', trim(b_mail)),
    ('GOVERNOR',  trim(g_mail)),
    ('ATTACHE',   trim(t_mail))
  on conflict (key) do update set email = excluded.email;
end $$;

commit;

-- The four rows that were saved (check them):
select key, email from test_support.accounts order by key;
