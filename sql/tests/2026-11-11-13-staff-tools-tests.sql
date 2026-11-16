-- Tests for sql/2026-11-11-13-staff-tools.sql (search, details, dashboard, alerts)
-- Needs the four test accounts: run 00-test-accounts.sql once first (see README.md).
-- Nothing is saved: the result is shown as an error at the end (RESULT SUMMARY).

begin;

-- ---------- Setup check: finds the 4 accounts by email (test_support.accounts) and checks them ----------
-- Stops with one SETUP PROBLEM line if something is wrong; then no test runs.
do $$
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

-- ---------- Section 1 (owner): fixtures ----------
reset role;
do $$
begin
-- One access_log row and one alert exist, so "cannot read" checks test something.
insert into public.access_log (actor_id, actor_role, student_id, kind)
values (current_setting('test.t_id')::uuid, 'attache', current_setting('test.a_id')::uuid, 'RESULTS_OPENED');
insert into public.alerts (title, message) values ('Test alert (rolled back)', 'Test alert message');
perform set_config('test.gw', (select rep_wilaya from public.profiles where id = current_setting('test.g_id')::uuid), true);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 1 (owner): fixtures: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 2: a student ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_refused('T1 a student cannot search students',
  $q$select * from public.staff_search_students('ab', null)$q$, 'P0001', '%Not allowed%');
perform pg_temp.t_refused('T2 a student cannot open another student details',
  $q$select public.staff_student_details(current_setting('test.a_id')::uuid)$q$, 'P0001', '%Not allowed%');
perform pg_temp.t_refused('T3 a student cannot see the dashboard',
  $q$select * from public.students_per_wilaya()$q$, 'P0001', '%Not allowed%');
perform pg_temp.t_hidden('T5 a student cannot read the access log',
  $q$select 1 from public.access_log$q$);
-- alerts: a student can read, never write
perform pg_temp.t_rows('T6 a student can read alerts (the test alert)',
  $q$select 1 from public.alerts where title = 'Test alert (rolled back)'$q$, 1);
perform pg_temp.t_refused('T4 a student cannot create an alert',
  $q$insert into public.alerts (title, message) values ('Fake', 'Fake alert')$q$, '42501');
perform pg_temp.t_noeffect('T6b a student cannot change an alert',
  $q$update public.alerts set title = 'Changed'$q$, '42501');
perform pg_temp.t_noeffect('T6c a student cannot delete an alert',
  $q$delete from public.alerts$q$, '42501');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 2: a student: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 3: a Governor ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.g_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_refused('T7 a Governor cannot open the staff details (bank + passport number)',
  $q$select public.staff_student_details(current_setting('test.a_id')::uuid)$q$, 'P0001', '%Not allowed%');
perform pg_temp.t_works('T8 a Governor can open the dashboard',
  $q$select * from public.students_per_wilaya()$q$);
perform pg_temp.t_rows('T9 the Governor dashboard shows only their own wilaya',
  $q$select 1 from public.students_per_wilaya() x where x.wilaya is distinct from current_setting('test.gw')$q$, 0);
perform pg_temp.t_rows('T9b a Governor can read alerts',
  $q$select 1 from public.alerts where title = 'Test alert (rolled back)'$q$, 1);
perform pg_temp.t_refused('T9c a Governor cannot create an alert',
  $q$insert into public.alerts (title, message) values ('Fake', 'Fake alert')$q$, '42501');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 3: a Governor: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 4 (owner): access log before ----------
reset role;
do $$
begin
perform set_config('test.before',
  (select count(*) from public.access_log where kind = 'STUDENT_DETAILS_VIEWED')::text, true);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 4 (owner): access log before: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 5: the Educational Attache ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.t_id')), true);
set local role authenticated;
do $$
declare d jsonb;
begin
perform pg_temp.t_refused('T10 an empty search is refused (no full list)',
  $q$select * from public.staff_search_students('', null)$q$, 'P0001', '%2 letters%');
d := public.staff_student_details(current_setting('test.a_id')::uuid);
perform pg_temp.t_check('T11 the details include the bank account and passport number keys',
  d ? 'bank_account' and d ? 'passport_number', 'keys missing');
perform pg_temp.t_works('T12 the attache can see the dashboard',
  $q$select * from public.students_per_wilaya()$q$);
perform pg_temp.t_refused('T12b the attache cannot create an alert from the app (only the Edge Function can)',
  $q$insert into public.alerts (title, message) values ('Fake', 'Fake alert')$q$, '42501');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 5: the Educational Attache: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 6 (owner): the access log after ----------
reset role;
do $$
begin
perform pg_temp.t_check('T13 opening a student details wrote exactly one access_log row',
  (select count(*) from public.access_log where kind = 'STUDENT_DETAILS_VIEWED')
    = current_setting('test.before')::int + 1,
  'expected 1 new STUDENT_DETAILS_VIEWED row, before ' || current_setting('test.before'));
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 6 (owner): the access log after: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
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
