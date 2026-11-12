-- Tests for sql/2026-11-11-06-new-request-push.sql and 07-match-suggestions.sql
-- Replace STUDENT-A-ID, STUDENT-B-ID and ATTACHE-ID (see README.md).
-- The test creates two requests (A sends 777 USD, B receives 777 USD), checks
-- the suggestion, accepts it as both, and checks the match.
-- At the start (owner, rolled back) it cancels the open requests of A and B,
-- removes their old suggestions and blocks, so the 3-open-requests limit and the
-- 24-hour rule cannot disturb it.
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
update public.transaction_requests set status = 'CANCELLED'
  where creator_id in ('STUDENT-A-ID', 'STUDENT-B-ID') and status::text = 'OPEN';
delete from public.match_suggestions
  where (user_a = 'STUDENT-A-ID' and user_b = 'STUDENT-B-ID') or (user_a = 'STUDENT-B-ID' and user_b = 'STUDENT-A-ID');
delete from public.user_blocks
  where (blocker_id = 'STUDENT-A-ID' and blocked_id = 'STUDENT-B-ID') or (blocker_id = 'STUDENT-B-ID' and blocked_id = 'STUDENT-A-ID');
-- Student B has a settings row with the switch ON (so T2 tests something).
insert into public.notification_settings (user_id, new_requests) values ('STUDENT-B-ID', true)
  on conflict (user_id) do update set new_requests = true;
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 1 (owner): clear the way: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 2: Student A ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
perform pg_temp.t_works('T1 Student A can switch off new request notifications',
  $q$insert into public.notification_settings (user_id, new_requests) values ('STUDENT-A-ID', false)
     on conflict (user_id) do update set new_requests = false$q$);
perform pg_temp.t_noeffect('T2 Student A cannot change Student B settings',
  $q$update public.notification_settings set new_requests = false where user_id = 'STUDENT-B-ID'$q$, '42501');
perform pg_temp.t_refused('T3 nobody can create a suggestion by hand',
  $q$insert into public.match_suggestions (request_a, request_b, user_a, user_b)
     values (gen_random_uuid(), gen_random_uuid(), 'STUDENT-A-ID', 'STUDENT-B-ID')$q$, '42501');
perform pg_temp.t_noeffect('T3b nobody can change a suggestion by hand',
  $q$update public.match_suggestions set status = 'MATCHED'$q$, '42501');
perform pg_temp.t_works('T3c Student A posts SEND 777 USD',
  $q$insert into public.transaction_requests (type, amount, currency, creator_id)
     values ('SEND', 777, 'USD', 'STUDENT-A-ID')$q$);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 2: Student A: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 3: Student B posts the opposite request ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-B-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
declare sid uuid; matched uuid;
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('RECEIVE', 777, 'USD', 'STUDENT-B-ID');
select id into sid from public.my_match_suggestions() where amount = 777 limit 1;
perform pg_temp.t_check('T4 a suggestion was created for the same amount and currency, opposite type',
  sid is not null, 'no suggestion found for Student B (is file 07 run?)');
if sid is null then return; end if;
matched := public.respond_match_suggestion(sid, true);
perform pg_temp.t_check('T5 one acceptance is not enough to match', matched is null, 'it matched after one acceptance');
perform set_config('test.sid', sid::text, true);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 3: Student B posts the opposite request: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 4: a third person (the Educational Attache) ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"ATTACHE-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
if coalesce(current_setting('test.sid', true), '') = '' then
  perform pg_temp.t_skip('T6-T7', 'no suggestion was created in section 3');
  return;
end if;
perform pg_temp.t_refused('T6 a third person cannot answer the suggestion',
  format('select public.respond_match_suggestion(%L, true)', current_setting('test.sid')),
  'P0001', '%not found%');
perform pg_temp.t_hidden('T7 a third person cannot see the suggestion',
  format('select 1 from public.match_suggestions where id = %L', current_setting('test.sid')));
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 4: a third person (the Educational Attache): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 5: Student A accepts: now it matches ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
declare matched uuid; st text; other uuid;
begin
if coalesce(current_setting('test.sid', true), '') = '' then
  perform pg_temp.t_skip('T8-T9', 'no suggestion was created in section 3');
  return;
end if;
matched := public.respond_match_suggestion(current_setting('test.sid')::uuid, true);
select status::text, matched_with_id into st, other from public.transaction_requests where id = matched;
perform pg_temp.t_check('T8 both accepted: the request is MATCHED with Student B',
  st = 'MATCHED' and other = 'STUDENT-B-ID', 'status ' || coalesce(st, 'null') || ', matched with ' || coalesce(other::text, 'null'));
perform pg_temp.t_refused('T9 a matched suggestion cannot be answered again',
  format('select public.respond_match_suggestion(%L, false)', current_setting('test.sid')),
  'P0001', '%closed%');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 5: Student A accepts: now it matches: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 6 (owner): the final state ----------
reset role;
do $$
begin
perform pg_temp.t_check('T10 Student B own request was cancelled (the exchange happens in one chat)',
  (select status::text from public.transaction_requests
   where creator_id = 'STUDENT-B-ID' and amount = 777 and currency::text = 'USD' order by created_at desc limit 1) = 'CANCELLED',
  'Student B request is not CANCELLED');
perform pg_temp.t_check('T11 Student B notification setting was not changed by Student A',
  (select new_requests from public.notification_settings where user_id = 'STUDENT-B-ID') = true,
  'it was changed');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 6 (owner): the final state: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
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
