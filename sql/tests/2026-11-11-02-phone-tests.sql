-- Tests for sql/2026-11-11-01-no-student-id-at-signup.sql and 2026-11-11-02-phone.sql
-- Replace STUDENT-A-ID, STUDENT-B-ID, GOVERNOR-ID, ATTACHE-ID (see README.md).
-- Both students get a phone number inside the test (rolled back), so every
-- check really tests something. Nothing is saved: the result is shown as an
-- error at the end (RESULT SUMMARY), which also undoes everything.

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
insert into public.user_phones (user_id, phone) values ('STUDENT-A-ID', '+213555123456')
  on conflict (user_id) do nothing;
insert into public.user_phones (user_id, phone) values ('STUDENT-B-ID', '+263771234567')
  on conflict (user_id) do nothing;
perform set_config('test.phone_a', (select phone from public.user_phones where user_id = 'STUDENT-A-ID'), true);
perform set_config('test.phone_b', (select phone from public.user_phones where user_id = 'STUDENT-B-ID'), true);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 1 (owner): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 2: Student A ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
perform pg_temp.t_rows('T2 Student A can read their own phone',
  $q$select 1 from public.user_phones where user_id = 'STUDENT-A-ID'$q$, 1);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 2: Student A: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 3: Student B ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-B-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
perform pg_temp.t_rows('T3 Student B can read their own phone',
  $q$select 1 from public.user_phones where user_id = 'STUDENT-B-ID'$q$, 1);
perform pg_temp.t_hidden('T4 Student B cannot read Student A phone',
  $q$select 1 from public.user_phones where user_id = 'STUDENT-A-ID'$q$);
perform pg_temp.t_noeffect('T5 Student B cannot change Student A phone',
  $q$update public.user_phones set phone = '+213000000000' where user_id = 'STUDENT-A-ID'$q$, '42501');
perform pg_temp.t_refused('T6 a wrong phone format is refused',
  $q$insert into public.user_phones (user_id, phone) values ('STUDENT-B-ID', '0555123456')
     on conflict (user_id) do update set phone = excluded.phone$q$, '23514');
perform pg_temp.t_refused('T7 Student B cannot add or overwrite a phone for Student A',
  $q$insert into public.user_phones (user_id, phone) values ('STUDENT-A-ID', '+213555000000')
     on conflict (user_id) do update set phone = excluded.phone$q$, '42501');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 3: Student B: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 4: the Governor of Student A wilaya ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"GOVERNOR-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
perform pg_temp.t_rows('T8 the Governor of A wilaya can read A phone',
  $q$select 1 from public.user_phones where user_id = 'STUDENT-A-ID'$q$, 1);
perform pg_temp.t_hidden('T9 the Governor cannot read Student B phone (other wilaya)',
  $q$select 1 from public.user_phones where user_id = 'STUDENT-B-ID'$q$);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 4: the Governor of Student A wilaya: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 5: the Educational Attache ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"ATTACHE-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
perform pg_temp.t_rows('T10 the Educational Attache can read A phone',
  $q$select 1 from public.user_phones where user_id = 'STUDENT-A-ID'$q$, 1);
perform pg_temp.t_noeffect('T11 the Educational Attache cannot change A phone',
  $q$update public.user_phones set phone = '+213000000000' where user_id = 'STUDENT-A-ID'$q$, '42501');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 5: the Educational Attache: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 6 (owner): nothing was changed ----------
reset role;
do $$
begin
perform pg_temp.t_check('T12 no phone was changed by the attempts above',
  (select phone from public.user_phones where user_id = 'STUDENT-A-ID') = current_setting('test.phone_a', true)
  and (select phone from public.user_phones where user_id = 'STUDENT-B-ID') = current_setting('test.phone_b', true),
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
