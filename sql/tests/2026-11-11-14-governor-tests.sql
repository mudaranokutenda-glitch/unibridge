-- Tests for sql/2026-11-11-14-governor-tools.sql
-- Needs the four test accounts: run 00-test-accounts.sql once first (see README.md).
-- Student A has a student record in the Governor's wilaya; Student B is in another.
-- Inside the test (rolled back) both students get a bank account, A also a
-- passport number and an attestation request, so "never in the list" checks test something.
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
  if a_id = b_id then
    raise exception 'SETUP PROBLEM: the four accounts must be four different accounts, but Student A and Student B are the same account (%).', a_mail;
  end if;
  if a_id = g_id then
    raise exception 'SETUP PROBLEM: the four accounts must be four different accounts, but Student A and the Governor are the same account (%).', a_mail;
  end if;
  if b_id = g_id then
    raise exception 'SETUP PROBLEM: the four accounts must be four different accounts, but Student B and the Governor are the same account (%).', b_mail;
  end if;
  if not exists (select 1 from public.student_records where user_id = a_id) then
    raise exception 'SETUP PROBLEM: Student A (%) has no student record (save one in the app first).', a_mail;
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

-- ---------- Section 1 (owner): fixtures and log baseline ----------
reset role;
do $$
begin
insert into public.bank_accounts (user_id, account_number) values (current_setting('test.a_id')::uuid, '11111111111111111111')
  on conflict (user_id) do nothing;
insert into public.bank_accounts (user_id, account_number) values (current_setting('test.b_id')::uuid, '22222222222222222222')
  on conflict (user_id) do nothing;
insert into public.passport_numbers (user_id, passport_number) values (current_setting('test.a_id')::uuid, 'ZZ123456')
  on conflict (user_id) do nothing;
insert into public.document_consents (user_id, version)
select current_setting('test.a_id')::uuid, 'test'
where not exists (select 1 from public.document_consents where user_id = current_setting('test.a_id')::uuid);
insert into public.attestation_requests (user_id, passport_path, entry_date)
values (current_setting('test.a_id')::uuid, (current_setting('test.a_id') || '/zz_test.pdf'), current_date - 100)
on conflict do nothing;
perform set_config('test.before',
  (select count(*) from public.access_log where actor_id = current_setting('test.g_id')::uuid and kind = 'BANK_LIST_VIEWED')::text, true);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 1 (owner): fixtures and log baseline: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 2: a student ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_refused('T1 a student cannot open the bank account list',
  $q$select * from public.rep_bank_accounts()$q$, 'P0001', '%Not allowed%');
perform pg_temp.t_refused('T2 a student cannot open the results tracker',
  $q$select * from public.rep_results_tracker('2025-2026', 'S1')$q$, 'P0001', '%Not allowed%');
perform pg_temp.t_refused('T3 a student cannot open the list without a record',
  $q$select * from public.rep_students_without_record()$q$, 'P0001', '%Not allowed%');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 2: a student: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 3: the Governor ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.g_id')), true);
set local role authenticated;
do $$
begin
-- Calls of rep_bank_accounts() below: T4, T5, T5b = exactly 3 (checked in section 4).
perform pg_temp.t_works('T4 the Governor can open the bank account list of their wilaya',
  $q$select * from public.rep_bank_accounts()$q$);
perform pg_temp.t_rows('T5 the bank list never contains Student B (other wilaya)',
  $q$select 1 from public.rep_bank_accounts() where user_id = current_setting('test.b_id')::uuid$q$, 0);
perform pg_temp.t_rows('T5b the bank list contains Student A (control)',
  $q$select 1 from public.rep_bank_accounts() where user_id = current_setting('test.a_id')::uuid$q$, 1);
perform pg_temp.t_rows('T6 the results tracker never contains Student B',
  $q$select 1 from public.rep_results_tracker('2025-2026', 'S1') where user_id = current_setting('test.b_id')::uuid$q$, 0);
perform pg_temp.t_rows('T6b the results tracker contains Student A (control)',
  $q$select 1 from public.rep_results_tracker('2025-2026', 'S1') where user_id = current_setting('test.a_id')::uuid$q$, 1);
perform pg_temp.t_rows('T7 the list without a record never contains Student B',
  $q$select 1 from public.rep_students_without_record() where user_id = current_setting('test.b_id')::uuid$q$, 0);
perform pg_temp.t_hidden('T8 the Governor can never read passport numbers',
  $q$select 1 from public.passport_numbers$q$);
perform pg_temp.t_hidden('T9 the Governor can never read attestation requests (passports)',
  $q$select 1 from public.attestation_requests$q$);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 3: the Governor: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 4 (owner): the bank list views were logged ----------
reset role;
do $$
begin
perform pg_temp.t_check('T10 each opening of the bank account list wrote exactly one access_log row (3 openings)',
  (select count(*) from public.access_log where actor_id = current_setting('test.g_id')::uuid and kind = 'BANK_LIST_VIEWED')
    = current_setting('test.before')::int + 3,
  'expected 3 new BANK_LIST_VIEWED rows, before ' || current_setting('test.before'));
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 4 (owner): the bank list views were logged: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
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
