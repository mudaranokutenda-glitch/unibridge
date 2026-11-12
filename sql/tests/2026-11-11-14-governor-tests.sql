-- Tests for sql/2026-11-11-14-governor-tools.sql
-- Replace STUDENT-A-ID, STUDENT-B-ID, GOVERNOR-ID (see README.md).
-- Student A has a student record in the Governor's wilaya; Student B is in another.
-- Inside the test (rolled back) both students get a bank account, A also a
-- passport number and an attestation request, so "never in the list" checks test something.
-- Nothing is saved: the result is shown as an error at the end (RESULT SUMMARY).

begin;

-- ---------- Setup check: runs first; stops with SETUP PROBLEM if an id is wrong ----------
do $$
declare
  a_id text := 'STUDENT-A-ID';
  b_id text := 'STUDENT-B-ID';
  g_id text := 'GOVERNOR-ID';
  t_id text := 'ATTACHE-ID';
  re constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  r text; a_wil text; b_wil text; g_wil text;
begin
  if a_id !~ re then
    raise exception 'SETUP PROBLEM: the id for Student A is not a valid uuid (%). Replace it with a real id from Table Editor > profiles.', a_id;
  end if;
  select p.role::text into r from public.profiles p where p.id = a_id::uuid;
  if not found then
    raise exception 'SETUP PROBLEM: Student A (%) does not exist in profiles', a_id;
  end if;
  if r <> 'student' then
    raise exception 'SETUP PROBLEM: Student A must have role student (it has %)', r;
  end if;
  if b_id !~ re then
    raise exception 'SETUP PROBLEM: the id for Student B is not a valid uuid (%). Replace it with a real id from Table Editor > profiles.', b_id;
  end if;
  select p.role::text into r from public.profiles p where p.id = b_id::uuid;
  if not found then
    raise exception 'SETUP PROBLEM: Student B (%) does not exist in profiles', b_id;
  end if;
  if r <> 'student' then
    raise exception 'SETUP PROBLEM: Student B must have role student (it has %)', r;
  end if;
  if g_id !~ re then
    raise exception 'SETUP PROBLEM: the id for the Governor is not a valid uuid (%). Replace it with a real id from Table Editor > profiles.', g_id;
  end if;
  select p.role::text into r from public.profiles p where p.id = g_id::uuid;
  if not found then
    raise exception 'SETUP PROBLEM: the Governor (%) does not exist in profiles', g_id;
  end if;
  if r <> 'rep' then
    raise exception 'SETUP PROBLEM: the Governor must have role rep (it has %)', r;
  end if;
  if a_id::uuid = b_id::uuid then
    raise exception 'SETUP PROBLEM: Student A and Student B must be two different accounts';
  end if;
  if not exists (select 1 from public.student_records where user_id = a_id::uuid) then
    raise exception 'SETUP PROBLEM: Student A has no student record (save one in the app first)';
  end if;
  a_wil := coalesce((select x.wilaya from public.student_records x where x.user_id = a_id::uuid),
                    (select p.wilaya from public.profiles p where p.id = a_id::uuid));
  select p.rep_wilaya into g_wil from public.profiles p where p.id = g_id::uuid;
  if a_wil is null then
    raise exception 'SETUP PROBLEM: Student A has no wilaya (profile or student record)';
  end if;
  if g_wil is distinct from a_wil then
    raise exception 'SETUP PROBLEM: the Governor rep_wilaya (%) must equal Student A wilaya (%)', g_wil, a_wil;
  end if;
  b_wil := coalesce((select x.wilaya from public.student_records x where x.user_id = b_id::uuid),
                    (select p.wilaya from public.profiles p where p.id = b_id::uuid));
  if b_wil is null then
    raise exception 'SETUP PROBLEM: Student B has no wilaya (profile or student record)';
  end if;
  if b_wil = g_wil then
    raise exception 'SETUP PROBLEM: Student B must be in a DIFFERENT wilaya from the Governor (both are %)', b_wil;
  end if;
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
insert into public.bank_accounts (user_id, account_number) values ('STUDENT-A-ID', '11111111111111111111')
  on conflict (user_id) do nothing;
insert into public.bank_accounts (user_id, account_number) values ('STUDENT-B-ID', '22222222222222222222')
  on conflict (user_id) do nothing;
insert into public.passport_numbers (user_id, passport_number) values ('STUDENT-A-ID', 'ZZ123456')
  on conflict (user_id) do nothing;
insert into public.document_consents (user_id, version)
select 'STUDENT-A-ID', 'test'
where not exists (select 1 from public.document_consents where user_id = 'STUDENT-A-ID');
insert into public.attestation_requests (user_id, passport_path, entry_date)
values ('STUDENT-A-ID', 'STUDENT-A-ID/zz_test.pdf', current_date - 100)
on conflict do nothing;
perform set_config('test.before',
  (select count(*) from public.access_log where actor_id = 'GOVERNOR-ID' and kind = 'BANK_LIST_VIEWED')::text, true);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 1 (owner): fixtures and log baseline: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 2: a student ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
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
select set_config('request.jwt.claims', '{"sub":"GOVERNOR-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
-- Calls of rep_bank_accounts() below: T4, T5, T5b = exactly 3 (checked in section 4).
perform pg_temp.t_works('T4 the Governor can open the bank account list of their wilaya',
  $q$select * from public.rep_bank_accounts()$q$);
perform pg_temp.t_rows('T5 the bank list never contains Student B (other wilaya)',
  $q$select 1 from public.rep_bank_accounts() where user_id = 'STUDENT-B-ID'$q$, 0);
perform pg_temp.t_rows('T5b the bank list contains Student A (control)',
  $q$select 1 from public.rep_bank_accounts() where user_id = 'STUDENT-A-ID'$q$, 1);
perform pg_temp.t_rows('T6 the results tracker never contains Student B',
  $q$select 1 from public.rep_results_tracker('2025-2026', 'S1') where user_id = 'STUDENT-B-ID'$q$, 0);
perform pg_temp.t_rows('T6b the results tracker contains Student A (control)',
  $q$select 1 from public.rep_results_tracker('2025-2026', 'S1') where user_id = 'STUDENT-A-ID'$q$, 1);
perform pg_temp.t_rows('T7 the list without a record never contains Student B',
  $q$select 1 from public.rep_students_without_record() where user_id = 'STUDENT-B-ID'$q$, 0);
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
  (select count(*) from public.access_log where actor_id = 'GOVERNOR-ID' and kind = 'BANK_LIST_VIEWED')
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
