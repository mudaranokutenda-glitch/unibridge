-- Tests for sql/2026-11-11-01-no-student-id-at-signup.sql and 2026-11-11-02-phone.sql
-- Needs the four test accounts: run 00-test-accounts.sql once first (see README.md).
-- Both students get a phone number inside the test (rolled back), so every
-- check really tests something. Nothing is saved: the result is shown as an
-- error at the end (RESULT SUMMARY), which also undoes everything.

begin;

-- ---------- Setup check: finds the 4 accounts by email (test_support.accounts) and checks them ----------
-- Stops with one SETUP PROBLEM line if something is wrong; then no test runs.
do $$A
declare
  a_id uuid; b_id uuid; g_id uuid; t_id uuid;
  mail text; n int; r text; a_wil text; b_wil text; g_wil text;
  a_mail text; b_mail text; g_mail text; t_mail text;
begin
  if to_regclass('test_support.accounts') is null then
    raise exception 'SETUP PROBLEM: test_support.accounts does not exist. Run sql/tests/00-test-accounts.sql once first (see README.md).';
  end if;
  select lower(trim(a.email)) into mail from test_support.accounts a where a.key = 'STUDENT_A';
  if mail is null then
    raise exception 'SETUP PROBLEM: there is no STUDENT_A row in test_support.accounts. Run sql/tests/00-test-accounts.sql again.';
  end if;
  if position('@' in mail) = 0 then
    raise exception 'SETUP PROBLEM: the STUDENT_A email is still a placeholder (%). Run 00-test-accounts.sql with your real email.', mail;
  end if;
  select count(*) into n from auth.users u where lower(u.email) = mail;
  if n = 0 then
    raise exception 'SETUP PROBLEM: Student A email "%" was not found in auth.users (no account has this email).', mail;
  end if;
  if n > 1 then
    raise exception 'SETUP PROBLEM: Student A email "%" matches % accounts in auth.users.', mail, n;
  end if;
  select u.id into a_id from auth.users u where lower(u.email) = mail;
  a_mail := mail;
  select p.role::text into r from public.profiles p where p.id = a_id;
  if not found then
    raise exception 'SETUP PROBLEM: Student A (%) has no row in profiles.', mail;
  end if;
  if r <> 'student' then
    raise exception 'SETUP PROBLEM: Student A (%) has role %, expected student.', mail, r;
  end if;
  select lower(trim(a.email)) into mail from test_support.accounts a where a.key = 'STUDENT_B';
  if mail is null then
    raise exception 'SETUP PROBLEM: there is no STUDENT_B row in test_support.accounts. Run sql/tests/00-test-accounts.sql again.';
  end if;
  if position('@' in mail) = 0 then
    raise exception 'SETUP PROBLEM: the STUDENT_B email is still a placeholder (%). Run 00-test-accounts.sql with your real email.', mail;
  end if;
  select count(*) into n from auth.users u where lower(u.email) = mail;
  if n = 0 then
    raise exception 'SETUP PROBLEM: Student B email "%" was not found in auth.users (no account has this email).', mail;
  end if;
  if n > 1 then
    raise exception 'SETUP PROBLEM: Student B email "%" matches % accounts in auth.users.', mail, n;
  end if;
  select u.id into b_id from auth.users u where lower(u.email) = mail;
  b_mail := mail;
  select p.role::text into r from public.profiles p where p.id = b_id;
  if not found then
    raise exception 'SETUP PROBLEM: Student B (%) has no row in profiles.', mail;
  end if;
  if r <> 'student' then
    raise exception 'SETUP PROBLEM: Student B (%) has role %, expected student.', mail, r;
  end if;
  select lower(trim(a.email)) into mail from test_support.accounts a where a.key = 'GOVERNOR';
  if mail is null then
    raise exception 'SETUP PROBLEM: there is no GOVERNOR row in test_support.accounts. Run sql/tests/00-test-accounts.sql again.';
  end if;
  if position('@' in mail) = 0 then
    raise exception 'SETUP PROBLEM: the GOVERNOR email is still a placeholder (%). Run 00-test-accounts.sql with your real email.', mail;
  end if;
  select count(*) into n from auth.users u where lower(u.email) = mail;
  if n = 0 then
    raise exception 'SETUP PROBLEM: the Governor email "%" was not found in auth.users (no account has this email).', mail;
  end if;
  if n > 1 then
    raise exception 'SETUP PROBLEM: the Governor email "%" matches % accounts in auth.users.', mail, n;
  end if;
  select u.id into g_id from auth.users u where lower(u.email) = mail;
  g_mail := mail;
  select p.role::text into r from public.profiles p where p.id = g_id;
  if not found then
    raise exception 'SETUP PROBLEM: the Governor (%) has no row in profiles.', mail;
  end if;
  if r <> 'rep' then
    raise exception 'SETUP PROBLEM: the Governor (%) has role %, expected rep.', mail, r;
  end if;
  select lower(trim(a.email)) into mail from test_support.accounts a where a.key = 'ATTACHE';
  if mail is null then
    raise exception 'SETUP PROBLEM: there is no ATTACHE row in test_support.accounts. Run sql/tests/00-test-accounts.sql again.';
  end if;
  if position('@' in mail) = 0 then
    raise exception 'SETUP PROBLEM: the ATTACHE email is still a placeholder (%). Run 00-test-accounts.sql with your real email.', mail;
  end if;
  select count(*) into n from auth.users u where lower(u.email) = mail;
  if n = 0 then
    raise exception 'SETUP PROBLEM: the Educational Attache email "%" was not found in auth.users (no account has this email).', mail;
  end if;
  if n > 1 then
    raise exception 'SETUP PROBLEM: the Educational Attache email "%" matches % accounts in auth.users.', mail, n;
  end if;
  select u.id into t_id from auth.users u where lower(u.email) = mail;
  t_mail := mail;
  select p.role::text into r from public.profiles p where p.id = t_id;
  if not found then
    raise exception 'SETUP PROBLEM: the Educational Attache (%) has no row in profiles.', mail;
  end if;
  if r not in ('attache', 'admin') then
    raise exception 'SETUP PROBLEM: the Educational Attache (%) has role %, expected attache or admin.', mail, r;
  end if;
  if a_id = b_id then
    raise exception 'SETUP PROBLEM: the four accounts must be four different accounts, but Student A and Student B are the same account (%).', a_mail;
  end if;
  if a_id = g_id then
    raise exception 'SETUP PROBLEM: the four accounts must be four different accounts, but Student A and the Governor are the same account (%).', a_mail;
  end if;
  if a_id = t_id then
    raise exception 'SETUP PROBLEM: the four accounts must be four different accounts, but Student A and the Educational Attache are the same account (%).', a_mail;
  end if;
  if b_id = g_id then
    raise exception 'SETUP PROBLEM: the four accounts must be four different accounts, but Student B and the Governor are the same account (%).', b_mail;
  end if;
  if b_id = t_id then
    raise exception 'SETUP PROBLEM: the four accounts must be four different accounts, but Student B and the Educational Attache are the same account (%).', b_mail;
  end if;
  if g_id = t_id then
    raise exception 'SETUP PROBLEM: the four accounts must be four different accounts, but the Governor and the Educational Attache are the same account (%).', g_mail;
  end if;
  a_wil := coalesce((select x.wilaya from public.student_records x where x.user_id = a_id),
                    (select p.wilaya from public.profiles p where p.id = a_id));
  select p.rep_wilaya into g_wil from public.profiles p where p.id = g_id;
  if a_wil is null then
    raise exception 'SETUP PROBLEM: Student A (%) has no wilaya (profile or student record).', a_mail;
  end if;
  if g_wil is distinct from a_wil then
    raise exception 'SETUP PROBLEM: the Governor (%) has rep_wilaya %, but Student A (%) is in wilaya %. They must be the same.', g_mail, g_wil, a_mail, a_wil;
  end if;
  b_wil := coalesce((select x.wilaya from public.student_records x where x.user_id = b_id),
                    (select p.wilaya from public.profiles p where p.id = b_id));
  if b_wil is null then
    raise exception 'SETUP PROBLEM: Student B (%) has no wilaya (profile or student record).', b_mail;
  end if;
  if b_wil = g_wil then
    raise exception 'SETUP PROBLEM: Student B (%) must be in a DIFFERENT wilaya from the Governor (both are in %).', b_mail, b_wil;
  end if;
  perform set_config('test.a_id', a_id::text, true);
  perform set_config('test.b_id', b_id::text, true);
  perform set_config('test.g_id', g_id::text, true);
  perform set_config('test.t_id', t_id::text, true);
end $$;

-- ---------- Result table and helpers (temporary objects, gone at the end) ----------
-- Every check writes one line (PASS / FAIL / SKIP) into pg_temp.test_results.
-- The SQL Editor does not show RAISE NOTICE, so the lines are shown in the
-- RESULT SUMMARY error at the very end.
create temp table test_results (n serial primary key, line text not null);
grant insert, select on pg_temp.test_results to authenticated, anon;
grant usage, select on sequence pg_temp.test_results_n_seq to authenticated, anon;

create function pg_temp.t_record(p_result text, p_label text, p_detail text default null)
returns void language sql as $f$
  insert into pg_temp.test_results (line)
  values (p_result || ' ' || p_label || coalesce(' -> ' || p_detail, ''));
$f$;

create function pg_temp.t_check(p_label text, p_ok boolean, p_detail text default null)
returns void language sql as $f$
  select pg_temp.t_record(case when coalesce(p_ok, false) then 'PASS' else 'FAIL' end,
                          p_label,
                          case when coalesce(p_ok, false) then null else p_detail end);
$f$;

create function pg_temp.t_skip(p_label text, p_why text)
returns void language sql as $f$
  select pg_temp.t_record('SKIP', p_label, p_why);
$f$;

-- Must be refused: PASS only if it fails with one of the expected error codes
-- (comma separated, for example '42501' or '23514,23502'). Any other error, or
-- no error at all, is a FAIL that shows what really happened.
-- p_like (optional): the error message must also match it.
create function pg_temp.t_refused(p_label text, p_sql text, p_codes text, p_like text default null)
returns void language plpgsql as $f$
declare st text; msg text; worked boolean := false;
begin
  begin
    execute p_sql;
    worked := true;
  exception when others then
    st := sqlstate; msg := sqlerrm;
  end;
  if worked then
    perform pg_temp.t_record('FAIL', p_label, 'it was NOT refused');
  elsif not (st = any (string_to_array(p_codes, ','))) then
    perform pg_temp.t_record('FAIL', p_label,
      'refused with the wrong error ' || st || ' (' || msg || '), expected ' || p_codes);
  elsif p_like is not null and msg not ilike p_like then
    perform pg_temp.t_record('FAIL', p_label,
      'refused with ' || st || ' but the message was: ' || msg);
  else
    perform pg_temp.t_record('PASS', p_label, 'refused with ' || st);
  end if;
end $f$;

-- Must work: PASS if it runs without error.
create function pg_temp.t_works(p_label text, p_sql text)
returns void language plpgsql as $f$
begin
  execute p_sql;
  perform pg_temp.t_record('PASS', p_label);
exception when others then
  perform pg_temp.t_record('FAIL', p_label, sqlstate || ' ' || sqlerrm);
end $f$;

-- The query must return exactly p_expected rows.
create function pg_temp.t_rows(p_label text, p_query text, p_expected int)
returns void language plpgsql as $f$
declare n int; st text; msg text;
begin
  begin
    execute 'select count(*) from (' || p_query || ') q' into n;
  exception when others then
    st := sqlstate; msg := sqlerrm;
  end;
  if n is null then
    perform pg_temp.t_record('FAIL', p_label, 'the query failed: ' || st || ' ' || msg);
  elsif n = p_expected then
    perform pg_temp.t_record('PASS', p_label);
  else
    perform pg_temp.t_record('FAIL', p_label, 'found ' || n || ' rows, expected ' || p_expected);
  end if;
end $f$;

-- Must NOT be readable: PASS if 0 rows, or "permission denied" (42501).
-- Rows found, or any other error, is a FAIL.
create function pg_temp.t_hidden(p_label text, p_query text)
returns void language plpgsql as $f$
declare n int; st text; msg text;
begin
  begin
    execute 'select count(*) from (' || p_query || ') q' into n;
  exception when others then
    st := sqlstate; msg := sqlerrm;
  end;
  if st is not null and st = '42501' then
    perform pg_temp.t_record('PASS', p_label, 'permission denied (42501)');
  elsif st is not null then
    perform pg_temp.t_record('FAIL', p_label, 'unexpected error ' || st || ': ' || msg);
  elsif n = 0 then
    perform pg_temp.t_record('PASS', p_label, '0 rows');
  else
    perform pg_temp.t_record('FAIL', p_label, 'it can see ' || n || ' row(s)');
  end if;
end $f$;

-- An update or delete that must change nothing: PASS if 0 rows were changed,
-- or if it fails with one of the expected codes (p_codes may be '' = none accepted).
create function pg_temp.t_noeffect(p_label text, p_sql text, p_codes text default '')
returns void language plpgsql as $f$
declare n int; st text; msg text;
begin
  begin
    execute p_sql;
    get diagnostics n = row_count;
  exception when others then
    st := sqlstate; msg := sqlerrm;
  end;
  if st is not null then
    if p_codes <> '' and st = any (string_to_array(p_codes, ',')) then
      perform pg_temp.t_record('PASS', p_label, 'refused with ' || st);
    else
      perform pg_temp.t_record('FAIL', p_label, 'unexpected error ' || st || ': ' || msg);
    end if;
  elsif n = 0 then
    perform pg_temp.t_record('PASS', p_label, 'no row was changed');
  else
    perform pg_temp.t_record('FAIL', p_label, n || ' row(s) were changed');
  end if;
end $f$;

-- A statement that must change exactly p_expected rows (a control test).
create function pg_temp.t_rowcount(p_label text, p_sql text, p_expected int)
returns void language plpgsql as $f$
declare n int;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n = p_expected then
    perform pg_temp.t_record('PASS', p_label);
  else
    perform pg_temp.t_record('FAIL', p_label, n || ' row(s) changed, expected ' || p_expected);
  end if;
exception when others then
  perform pg_temp.t_record('FAIL', p_label, sqlstate || ' ' || sqlerrm);
end $f$;

-- ---------- Section 1 (owner) ----------
reset role;
do $$
begin
perform pg_temp.t_check('T0 profiles.inscription_number may be empty',
  not exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'profiles'
                and column_name = 'inscription_number' and is_nullable = 'NO'),
  'the column is still NOT NULL: run file 01');
perform pg_temp.t_check('T1 phone format: +213555123456 and +263771234567 ok; 0555123456, +33612345678, +2135551 refused',
  public.is_valid_phone('+213555123456') and public.is_valid_phone('+263771234567')
  and not public.is_valid_phone('0555123456') and not public.is_valid_phone('+33612345678')
  and not public.is_valid_phone('+2135551'),
  'is_valid_phone gives a wrong answer');
-- Fixtures (rolled back): both students have a phone.
insert into public.user_phones (user_id, phone) values (current_setting('test.a_id')::uuid, '+213555123456')
  on conflict (user_id) do nothing;
insert into public.user_phones (user_id, phone) values (current_setting('test.b_id')::uuid, '+263771234567')
  on conflict (user_id) do nothing;
perform set_config('test.phone_a', (select phone from public.user_phones where user_id = current_setting('test.a_id')::uuid), true);
perform set_config('test.phone_b', (select phone from public.user_phones where user_id = current_setting('test.b_id')::uuid), true);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 1 (owner): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 2: Student A ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_rows('T2 Student A can read their own phone',
  $q$select 1 from public.user_phones where user_id = current_setting('test.a_id')::uuid$q$, 1);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 2: Student A: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 3: Student B ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_rows('T3 Student B can read their own phone',
  $q$select 1 from public.user_phones where user_id = current_setting('test.b_id')::uuid$q$, 1);
perform pg_temp.t_hidden('T4 Student B cannot read Student A phone',
  $q$select 1 from public.user_phones where user_id = current_setting('test.a_id')::uuid$q$);
perform pg_temp.t_noeffect('T5 Student B cannot change Student A phone',
  $q$update public.user_phones set phone = '+213000000000' where user_id = current_setting('test.a_id')::uuid$q$, '42501');
perform pg_temp.t_refused('T6 a wrong phone format is refused',
  $q$insert into public.user_phones (user_id, phone) values (current_setting('test.b_id')::uuid, '0555123456')
     on conflict (user_id) do update set phone = excluded.phone$q$, '23514');
perform pg_temp.t_refused('T7 Student B cannot add or overwrite a phone for Student A',
  $q$insert into public.user_phones (user_id, phone) values (current_setting('test.a_id')::uuid, '+213555000000')
     on conflict (user_id) do update set phone = excluded.phone$q$, '42501');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 3: Student B: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 4: the Governor of Student A wilaya ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.g_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_rows('T8 the Governor of A wilaya can read A phone',
  $q$select 1 from public.user_phones where user_id = current_setting('test.a_id')::uuid$q$, 1);
perform pg_temp.t_hidden('T9 the Governor cannot read Student B phone (other wilaya)',
  $q$select 1 from public.user_phones where user_id = current_setting('test.b_id')::uuid$q$);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 4: the Governor of Student A wilaya: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 5: the Educational Attache ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.t_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_rows('T10 the Educational Attache can read A phone',
  $q$select 1 from public.user_phones where user_id = current_setting('test.a_id')::uuid$q$, 1);
perform pg_temp.t_noeffect('T11 the Educational Attache cannot change A phone',
  $q$update public.user_phones set phone = '+213000000000' where user_id = current_setting('test.a_id')::uuid$q$, '42501');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 5: the Educational Attache: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 6 (owner): nothing was changed ----------
reset role;
do $$
begin
perform pg_temp.t_check('T12 no phone was changed by the attempts above',
  (select phone from public.user_phones where user_id = current_setting('test.a_id')::uuid) = current_setting('test.phone_a', true)
  and (select phone from public.user_phones where user_id = current_setting('test.b_id')::uuid) = current_setting('test.phone_b', true),
  'a phone was changed');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 6 (owner): nothing was changed: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- RESULT SUMMARY (this error is on purpose: it also undoes everything) ----------
reset role;
do $$
declare p int; f int; s int; lines text;
begin
  select count(*) filter (where line like 'PASS %'),
         count(*) filter (where line like 'FAIL %'),
         count(*) filter (where line like 'SKIP %')
    into p, f, s
  from pg_temp.test_results;
  select string_agg(line, E'\n' order by n) into lines from pg_temp.test_results;
  raise exception E'RESULT SUMMARY: % PASS, % FAIL, % SKIP\n%', p, f, s, coalesce(lines, '(no result lines)');
end $$;

rollback; -- only reached if the exception above did not stop the script
