-- Tests for sql/2026-11-11-03-cron-secret.sql, 04-chat-rules.sql and 05-chat-cleanup.sql
-- Replace STUDENT-A-ID and STUDENT-B-ID (see README.md).
-- The test makes its own MATCHED request between A and B (rolled back).
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

-- ---------- Section 1 (owner) ----------
reset role;
do $$
declare rid uuid;
begin
perform pg_temp.t_check('T1 the secret is stored in the Vault',
  exists (select 1 from vault.secrets where name = 'cron_secret'), 'run file 03');
perform pg_temp.t_check('T2 the nightly chat-cleanup job exists',
  exists (select 1 from cron.job where jobname = 'chat-cleanup'), 'run file 05');
perform pg_temp.t_check('T3 no DISPUTED request has ended_at set (existing data)',
  not exists (select 1 from public.transaction_requests
              where status::text = 'DISPUTED' and ended_at is not null),
  'a DISPUTED request has ended_at');
-- ended_at is set on INSERT too: check each status with fresh rows.
insert into public.transaction_requests (type, amount, currency, creator_id, matched_with_id, status)
values ('SEND', 991, 'USD', 'STUDENT-A-ID', 'STUDENT-B-ID', 'DISPUTED');
insert into public.transaction_requests (type, amount, currency, creator_id, matched_with_id, status)
values ('SEND', 992, 'USD', 'STUDENT-A-ID', 'STUDENT-B-ID', 'COMPLETED');
perform pg_temp.t_check('T3b a new DISPUTED request has no ended_at',
  (select ended_at from public.transaction_requests where creator_id = 'STUDENT-A-ID' and amount = 991 and status::text = 'DISPUTED' limit 1) is null,
  'ended_at is set');
perform pg_temp.t_check('T3c a new COMPLETED request gets ended_at',
  (select ended_at from public.transaction_requests where creator_id = 'STUDENT-A-ID' and amount = 992 and status::text = 'COMPLETED' limit 1) is not null,
  'ended_at is empty');
-- The MATCHED request used below.
insert into public.transaction_requests (type, amount, currency, creator_id, matched_with_id, status)
values ('SEND', 999, 'USD', 'STUDENT-A-ID', 'STUDENT-B-ID', 'MATCHED')
returning id into rid;
perform set_config('test.rid', rid::text, true);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 1 (owner): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 2: Student A (before rating) ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
perform pg_temp.t_refused('T4 a student cannot read the secret',
  $q$select public.cron_secret()$q$, '42501');
perform pg_temp.t_refused('T5 a student cannot start the clean-up',
  $q$select public.call_edge_function('chat-cleanup', '{}'::jsonb)$q$, '42501');
perform pg_temp.t_refused('T6 a LOCATION message is refused',
  format($q$insert into public.messages (request_id, sender_id, type, content, attachment_url)
            values (%L, 'STUDENT-A-ID', 'LOCATION', 'test', 'https://maps.google.com')$q$,
         current_setting('test.rid')), '42501');
perform pg_temp.t_works('T7 a TEXT message is still allowed',
  format($q$insert into public.messages (request_id, sender_id, type, content)
            values (%L, 'STUDENT-A-ID', 'TEXT', 'test message (rolled back)')$q$,
         current_setting('test.rid')));
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 2: Student A (before rating): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 3 (owner): the request is completed ----------
reset role;
do $$
begin
update public.transaction_requests set status = 'COMPLETED' where id = current_setting('test.rid')::uuid;
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 3 (owner): the request is completed: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 4: Student A rates ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
begin
  perform public.rate_transaction(current_setting('test.rid')::uuid, 5, 'test rating (rolled back)');
  perform set_config('test.rated', 'yes', true);
exception when others then
  perform set_config('test.rated', 'no', true);
  perform pg_temp.t_skip('T8-T9 (rating)', 'could not rate the test request: ' || sqlstate || ' ' || sqlerrm);
end;
if current_setting('test.rated', true) = 'yes' then
  perform pg_temp.t_refused('T8 after rating, Student A cannot send a message (the chat is closed)',
    format($q$insert into public.messages (request_id, sender_id, type, content)
              values (%L, 'STUDENT-A-ID', 'TEXT', 'after rating')$q$, current_setting('test.rid')), '42501');
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 4: Student A rates: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 5: Student B has not rated yet ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-B-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
if current_setting('test.rated', true) = 'yes' then
  perform pg_temp.t_works('T9 Student B (who has not rated) can still send a message',
    format($q$insert into public.messages (request_id, sender_id, type, content)
              values (%L, 'STUDENT-B-ID', 'TEXT', 'B still writes')$q$, current_setting('test.rid')));
else
  perform pg_temp.t_skip('T9', 'no rating was made');
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 5: Student B has not rated yet: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 6 (owner): the chat is cleaned up (archived) ----------
reset role;
do $$
begin
update public.transaction_requests set archived_at = now() where id = current_setting('test.rid')::uuid;
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 6 (owner): the chat is cleaned up (archived): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 7: Student B after the clean-up ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-B-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
perform pg_temp.t_refused('T10 nobody can write in an archived chat',
  format($q$insert into public.messages (request_id, sender_id, type, content)
            values (%L, 'STUDENT-B-ID', 'TEXT', 'after archive')$q$, current_setting('test.rid')), '42501');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 7: Student B after the clean-up: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- T11 (by hand, in the app): after you rate a COMPLETED request, the chat shows
-- "This chat is closed." and there is no text box.

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
