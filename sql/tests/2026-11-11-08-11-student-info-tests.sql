-- Tests for sql/2026-11-11-08 (bank, passport number), 09 (contacts),
-- 10 (guide, help) and 11 (appointments).
-- Replace STUDENT-A-ID, STUDENT-B-ID, GOVERNOR-ID, ATTACHE-ID (see README.md).
-- Student A saves a bank account and a passport number INSIDE the test
-- (rolled back), so the "cannot read" checks for the others really test something.
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
  if t_id !~ re then
    raise exception 'SETUP PROBLEM: the id for the Educational Attache is not a valid uuid (%). Replace it with a real id from Table Editor > profiles.', t_id;
  end if;
  select p.role::text into r from public.profiles p where p.id = t_id::uuid;
  if not found then
    raise exception 'SETUP PROBLEM: the Educational Attache (%) does not exist in profiles', t_id;
  end if;
  if r not in ('attache', 'admin') then
    raise exception 'SETUP PROBLEM: the Educational Attache must have role attache or admin (it has %)', r;
  end if;
  if a_id::uuid = b_id::uuid then
    raise exception 'SETUP PROBLEM: Student A and Student B must be two different accounts';
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

-- ---------- Section 1 (owner): clear the way ----------
reset role;
do $$
begin
-- Student A may already have 3 active appointments: cancel them (rolled back).
update public.appointments set status = 'CANCELLED'
  where student_id = 'STUDENT-A-ID' and status in ('REQUESTED', 'PROPOSED', 'ACCEPTED');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 1 (owner): clear the way: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 2: Student A saves private data ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
declare aid uuid;
begin
perform pg_temp.t_works('T1a Student A can save a bank account',
  $q$insert into public.bank_accounts (user_id, account_number) values ('STUDENT-A-ID', '12345678901234567890')
     on conflict (user_id) do update set account_number = excluded.account_number$q$);
perform pg_temp.t_works('T1b Student A can save a passport number',
  $q$insert into public.passport_numbers (user_id, passport_number) values ('STUDENT-A-ID', 'AB123456')
     on conflict (user_id) do update set passport_number = excluded.passport_number$q$);
perform pg_temp.t_refused('T2 a bank account must be exactly 20 digits',
  $q$update public.bank_accounts set account_number = '1234' where user_id = 'STUDENT-A-ID'$q$, '23514');
perform pg_temp.t_refused('T3 a passport number must be 6-12 capital letters or digits',
  $q$update public.passport_numbers set passport_number = 'ab-12' where user_id = 'STUDENT-A-ID'$q$, '23514');
if exists (select 1 from public.student_records where user_id = 'STUDENT-A-ID') then
  perform pg_temp.t_refused('T4 gender must be MALE or FEMALE',
    $q$update public.student_records set gender = 'OTHER' where user_id = 'STUDENT-A-ID'$q$, '23514');
else
  perform pg_temp.t_skip('T4 gender must be MALE or FEMALE', 'Student A has no student record');
end if;
perform pg_temp.t_refused('T5 a student cannot add a staff contact',
  $q$insert into public.staff_contacts (kind, name, email) values ('attache', 'Fake', 'x@y.zz')$q$, '42501');
perform pg_temp.t_refused('T6 a student cannot add a question to Help',
  $q$insert into public.faqs (question, answer) values ('Q', 'A')$q$, '42501');
perform pg_temp.t_refused('T7 a student cannot add a guide item',
  $q$insert into public.guide_items (section_id, title) values ('BANK', 'Fake')$q$, '42501');
perform pg_temp.t_rows('T8 a student can read the 4 guide sections',
  $q$select 1 from public.guide_sections where id in ('POLICE', 'BANK', 'BOURSE', 'MEDICAL')$q$, 4);
begin
  insert into public.appointments (student_id, requested_at, reason)
  values ('STUDENT-A-ID', now() + interval '3 days', 'Test appointment (rolled back)')
  returning id into aid;
  perform set_config('test.apt', aid::text, true);
  perform pg_temp.t_record('PASS', 'T9 Student A can ask for an appointment');
exception when others then
  perform pg_temp.t_record('FAIL', 'T9 Student A can ask for an appointment', sqlstate || ' ' || sqlerrm);
end;
perform pg_temp.t_refused('T10 a student cannot create an ACCEPTED appointment',
  $q$insert into public.appointments (student_id, requested_at, reason, status)
     values ('STUDENT-A-ID', now() + interval '3 days', 'Trying to self-accept', 'ACCEPTED')$q$, '42501');
-- A student can read their own private data (control for the tests below).
perform pg_temp.t_rows('T10b Student A can read their own bank account',
  $q$select 1 from public.bank_accounts where user_id = 'STUDENT-A-ID'$q$, 1);
perform pg_temp.t_rows('T10c Student A can read their own passport number',
  $q$select 1 from public.passport_numbers where user_id = 'STUDENT-A-ID'$q$, 1);
perform pg_temp.t_rows('T10d Student A can see their own appointment',
  format('select 1 from public.appointments where id = %L', current_setting('test.apt', true)), 1);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 2: Student A saves private data: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 3: Student B must see none of it ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-B-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
perform pg_temp.t_hidden('T11 Student B cannot read A bank account',
  $q$select 1 from public.bank_accounts where user_id = 'STUDENT-A-ID'$q$);
perform pg_temp.t_hidden('T12 Student B cannot read A passport number',
  $q$select 1 from public.passport_numbers where user_id = 'STUDENT-A-ID'$q$);
perform pg_temp.t_hidden('T13 Student B cannot see A appointments',
  format('select 1 from public.appointments where student_id = %L', 'STUDENT-A-ID'));
perform pg_temp.t_refused('T14 a student cannot answer appointments as staff',
  format('select public.staff_answer_appointment(%L, %L, null, null)', current_setting('test.apt', true), 'ACCEPT'),
  'P0001', '%Only the Educational Attach%');
perform pg_temp.t_refused('T14b Student B cannot cancel Student A appointment',
  format('select public.student_answer_appointment(%L, %L)', current_setting('test.apt', true), 'CANCEL'),
  'P0001', '%not found%');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 3: Student B must see none of it: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 4: a Governor never sees the passport number, no direct bank read ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"GOVERNOR-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
perform pg_temp.t_hidden('T15 a Governor cannot read a passport number',
  $q$select 1 from public.passport_numbers where user_id = 'STUDENT-A-ID'$q$);
perform pg_temp.t_hidden('T16 a Governor cannot read bank accounts directly (only through the logged functions)',
  $q$select 1 from public.bank_accounts where user_id = 'STUDENT-A-ID'$q$);
perform pg_temp.t_hidden('T17 a Governor cannot see appointments',
  $q$select 1 from public.appointments$q$);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 4: a Governor never sees the passport number, no direct bank read: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 5: the Educational Attache ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"ATTACHE-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
perform pg_temp.t_hidden('T18 the attache cannot read bank accounts directly (only through the logged function)',
  $q$select 1 from public.bank_accounts where user_id = 'STUDENT-A-ID'$q$);
perform pg_temp.t_hidden('T19 the attache cannot read passport numbers directly (only through the logged function)',
  $q$select 1 from public.passport_numbers where user_id = 'STUDENT-A-ID'$q$);
perform pg_temp.t_rows('T20 the attache can see A appointment',
  format('select 1 from public.appointments where id = %L', current_setting('test.apt', true)), 1);
perform pg_temp.t_works('T21 the Educational Attache can add a contact',
  $q$insert into public.staff_contacts (kind, name, phone) values ('attache', 'Test attache', '+213555123456')$q$);
perform pg_temp.t_refused('T22 a Governor contact needs a wilaya',
  $q$insert into public.staff_contacts (kind, name, phone) values ('governor', 'No wilaya', '+213555123456')$q$, '23514');
perform pg_temp.t_works('T23 the attache can propose another time',
  format('select public.staff_answer_appointment(%L, %L, now() + interval ''5 days'', %L)',
         current_setting('test.apt', true), 'PROPOSE', 'Is this better?'));
perform pg_temp.t_check('T23b the appointment is now PROPOSED',
  (select status from public.appointments where id = current_setting('test.apt', true)::uuid) = 'PROPOSED',
  'wrong status');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 5: the Educational Attache: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
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
