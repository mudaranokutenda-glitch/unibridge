-- Tests for the hardening: sql 07 (24-hour rule, declined pairs, updated_at, closing
-- instead of an error), 11 (3 active appointments), 15 (blocked users cannot match)
-- and 17 (3 open requests).
-- Needs the four test accounts: run 00-test-accounts.sql once first (see README.md).
-- If a file was not run yet, its tests say SKIP "run file N first" (not a false FAIL).
-- Everything happens inside the test (rolled back): the open requests, suggestions,
-- blocks and active appointments of A and B are cleared at the start.
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
  if a_id = b_id then
    raise exception 'SETUP PROBLEM: the four accounts must be four different accounts, but Student A and Student B are the same account (%).', a_mail;
  end if;
  perform set_config('test.a_id', a_id::text, true);
  perform set_config('test.b_id', b_id::text, true);
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

-- ---------- Section 1 (owner): clear the way and check which files are run ----------
reset role;
do $$
begin
update public.transaction_requests set status = 'CANCELLED'
  where creator_id in (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid) and status::text = 'OPEN';
delete from public.match_suggestions
  where (user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid);
delete from public.user_blocks
  where (blocker_id = current_setting('test.a_id')::uuid and blocked_id = current_setting('test.b_id')::uuid) or (blocker_id = current_setting('test.b_id')::uuid and blocked_id = current_setting('test.a_id')::uuid);

update public.appointments set status = 'CANCELLED'
  where student_id = current_setting('test.a_id')::uuid and status in ('REQUESTED', 'PROPOSED', 'ACCEPTED');
perform set_config('test.f15', case when exists (select 1 from pg_proc where proname = 'match_request'
  and pg_get_functiondef(oid) ~* 'user_blocks') then 'yes' else 'no' end, true);
perform set_config('test.f17', case when exists (select 1 from pg_trigger
  where tgname = 'limit_open_requests' and not tgisinternal) then 'yes' else 'no' end, true);
perform set_config('test.f11', case when exists (select 1 from pg_trigger
  where tgname = 'limit_active_appointments' and not tgisinternal) then 'yes' else 'no' end, true);
perform set_config('test.f07a', case when exists (select 1 from pg_proc where proname = 'respond_match_suggestion'
  and pg_get_functiondef(oid) ~* 'updated_at') then 'yes' else 'no' end, true);
perform set_config('test.f07b', case when exists (select 1 from pg_proc where proname = 'suggest_match_for_new_request'
  and pg_get_functiondef(oid) ~* '24 hours') then 'yes' else 'no' end, true);
perform set_config('test.f07c', case when exists (select 1 from pg_proc where proname = 'respond_match_suggestion'
  and pg_get_functiondef(oid) !~* 'raise exception ''One of the requests') then 'yes' else 'no' end, true);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 1 (owner): clear the way and check which files are run: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M1 (owner): a request of Student A, then a block ----------
reset role;
do $$
declare rq uuid;
begin
if current_setting('test.f15') = 'yes' then
  insert into public.transaction_requests (type, amount, currency, creator_id)
  values ('SEND', 4242, 'USD', current_setting('test.a_id')::uuid) returning id into rq;
  perform set_config('test.rq1', rq::text, true);
  insert into public.user_blocks (blocker_id, blocked_id) values (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid);
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M1 (owner): a request of Student A, then a block: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M1: Student B tries to match (A blocked B) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
if current_setting('test.f15') = 'yes' then
  perform pg_temp.t_refused('E1 a blocked user cannot match (A blocked B)',
    format('select public.match_request(%L)', current_setting('test.rq1')), 'P0001', '%cannot match%');
else
  perform pg_temp.t_skip('E1 a blocked user cannot match', 'run file 15 first');
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M1: Student B tries to match (A blocked B): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M1 (owner): now B blocks A instead ----------
reset role;
do $$
begin
if current_setting('test.f15') = 'yes' then
  delete from public.user_blocks where blocker_id = current_setting('test.a_id')::uuid and blocked_id = current_setting('test.b_id')::uuid;
  insert into public.user_blocks (blocker_id, blocked_id) values (current_setting('test.b_id')::uuid, current_setting('test.a_id')::uuid);
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M1 (owner): now B blocks A instead: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M1: Student B tries to match (B blocked A) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
if current_setting('test.f15') = 'yes' then
  perform pg_temp.t_refused('E1b a user cannot match the request of someone they blocked',
    format('select public.match_request(%L)', current_setting('test.rq1')), 'P0001', '%cannot match%');
else
  perform pg_temp.t_skip('E1b', 'run file 15 first');
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M1: Student B tries to match (B blocked A): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M2 (owner): reset, then A blocks B ----------
reset role;
do $$
begin
update public.transaction_requests set status = 'CANCELLED'
  where creator_id in (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid) and status::text = 'OPEN';
delete from public.match_suggestions
  where (user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid);
delete from public.user_blocks
  where (blocker_id = current_setting('test.a_id')::uuid and blocked_id = current_setting('test.b_id')::uuid) or (blocker_id = current_setting('test.b_id')::uuid and blocked_id = current_setting('test.a_id')::uuid);

insert into public.user_blocks (blocker_id, blocked_id) values (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M2 (owner): reset, then A blocks B: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M2: Student A posts SEND 5252 ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('SEND', 5252, 'USD', current_setting('test.a_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M2: Student A posts SEND 5252: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M2: Student B posts RECEIVE 5252 ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('RECEIVE', 5252, 'USD', current_setting('test.b_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M2: Student B posts RECEIVE 5252: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M2 (owner): check ----------
reset role;
do $$
begin
perform pg_temp.t_rows('E2 two users who blocked each other are never suggested', $q$select 1 from public.match_suggestions where (user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid)$q$, 0);
exception when others then
  perform pg_temp.t_record('FAIL', 'M2 (owner): check: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M3 (owner): reset ----------
reset role;
do $$
begin
update public.transaction_requests set status = 'CANCELLED'
  where creator_id in (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid) and status::text = 'OPEN';
delete from public.match_suggestions
  where (user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid);
delete from public.user_blocks
  where (blocker_id = current_setting('test.a_id')::uuid and blocked_id = current_setting('test.b_id')::uuid) or (blocker_id = current_setting('test.b_id')::uuid and blocked_id = current_setting('test.a_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M3 (owner): reset: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M3: Student A posts SEND 5252 ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('SEND', 5252, 'USD', current_setting('test.a_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M3: Student A posts SEND 5252: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M3: Student B posts RECEIVE 5252 ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('RECEIVE', 5252, 'USD', current_setting('test.b_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M3: Student B posts RECEIVE 5252: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M3 (owner): a suggestion exists; now B blocks A ----------
reset role;
do $$
declare sid uuid;
begin
select id into sid from public.match_suggestions
  where status = 'PENDING'
    and ((user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid))
  limit 1;
perform pg_temp.t_check('E3a a suggestion is made for two users who have not blocked each other', sid is not null,
  'no suggestion was created (is file 07 run?)');
if sid is not null then
  perform set_config('test.sid3', sid::text, true);
  insert into public.user_blocks (blocker_id, blocked_id) values (current_setting('test.b_id')::uuid, current_setting('test.a_id')::uuid);
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M3 (owner): a suggestion exists; now B blocks A: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M3: Student A accepts ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
if coalesce(current_setting('test.sid3', true), '') <> '' and current_setting('test.f07c') = 'yes' then
  perform public.respond_match_suggestion(current_setting('test.sid3')::uuid, true);
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M3: Student A accepts: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M3: Student B accepts (but blocked A): the suggestion closes, no error ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
declare matched uuid;
begin
if coalesce(current_setting('test.sid3', true), '') = '' then
  perform pg_temp.t_skip('E3 blocked after the suggestion', 'no suggestion was created');
elsif current_setting('test.f07c') = 'no' then
  perform pg_temp.t_skip('E3 blocked after the suggestion', 'run the updated file 07 first');
else
  begin
    matched := public.respond_match_suggestion(current_setting('test.sid3')::uuid, true);
    perform pg_temp.t_check('E3 a blocked user cannot match: the call returns null (no error)', matched is null,
      'it matched although there is a block');
  exception when others then
    perform pg_temp.t_record('FAIL', 'E3 a blocked user cannot match: the call returns null (no error)',
      'it raised ' || sqlstate || ': ' || sqlerrm);
  end;
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M3: Student B accepts (but blocked A): the suggestion closes, no error: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M3 (owner): the suggestion is CLOSED and both requests are still OPEN ----------
reset role;
do $$
begin
if coalesce(current_setting('test.sid3', true), '') <> '' and current_setting('test.f07c') = 'yes' then
  perform pg_temp.t_check('E3b the suggestion was set to CLOSED (not left pending)',
    (select status from public.match_suggestions where id = current_setting('test.sid3')::uuid) = 'CLOSED',
    'status is ' || coalesce((select status from public.match_suggestions where id = current_setting('test.sid3')::uuid), 'null'));
  perform pg_temp.t_check('E3c both requests are still OPEN',
    (select count(*) from public.transaction_requests
     where creator_id in (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid) and amount = 5252 and status::text = 'OPEN') = 2,
    'a request is no longer OPEN');
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M3 (owner): the suggestion is CLOSED and both requests are still OPEN: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M4 (owner): reset ----------
reset role;
do $$
begin
update public.transaction_requests set status = 'CANCELLED'
  where creator_id in (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid) and status::text = 'OPEN';
delete from public.match_suggestions
  where (user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid);
delete from public.user_blocks
  where (blocker_id = current_setting('test.a_id')::uuid and blocked_id = current_setting('test.b_id')::uuid) or (blocker_id = current_setting('test.b_id')::uuid and blocked_id = current_setting('test.a_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M4 (owner): reset: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M4: Student A posts SEND 5252 (1st time) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('SEND', 5252, 'USD', current_setting('test.a_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M4: Student A posts SEND 5252 (1st time): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M4: Student B posts RECEIVE 5252 (1st time) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('RECEIVE', 5252, 'USD', current_setting('test.b_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M4: Student B posts RECEIVE 5252 (1st time): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M4 (owner): close that suggestion, cancel the requests ----------
reset role;
do $$
begin
perform pg_temp.t_rows('E4a the first suggestion of the pair exists', $q$select 1 from public.match_suggestions where (user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid)$q$, 1);
update public.match_suggestions set status = 'CLOSED'
  where (user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid);

update public.transaction_requests set status = 'CANCELLED'
  where creator_id in (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid) and status::text = 'OPEN';
exception when others then
  perform pg_temp.t_record('FAIL', 'M4 (owner): close that suggestion, cancel the requests: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M4: Student A posts SEND 5252 (2nd time) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('SEND', 5252, 'USD', current_setting('test.a_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M4: Student A posts SEND 5252 (2nd time): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M4: Student B posts RECEIVE 5252 (2nd time) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('RECEIVE', 5252, 'USD', current_setting('test.b_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M4: Student B posts RECEIVE 5252 (2nd time): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M4 (owner): no 2nd suggestion within 24 hours; after 25 hours there is one ----------
reset role;
do $$
begin
if current_setting('test.f07b') = 'yes' then
  perform pg_temp.t_rows('E4 the same pair is not suggested twice within 24 hours', $q$select 1 from public.match_suggestions where (user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid)$q$, 1);
else
  perform pg_temp.t_skip('E4 the same pair is not suggested twice within 24 hours', 'run the updated file 07 first');
end if;
-- Positive control: the old suggestion is 25 hours old (and not DECLINED).
update public.match_suggestions set created_at = now() - interval '25 hours'
  where (user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M4 (owner): no 2nd suggestion within 24 hours; after 25 hours there is one: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M4: Student A posts SEND 5252 (3rd time) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('SEND', 5252, 'USD', current_setting('test.a_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M4: Student A posts SEND 5252 (3rd time): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M4 (owner): control after 25 hours ----------
reset role;
do $$
begin
if current_setting('test.f07b') = 'yes' then
  perform pg_temp.t_rows('E4c (control) after 25 hours a new suggestion IS made', $q$select 1 from public.match_suggestions where (user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid)$q$, 2);
else
  perform pg_temp.t_skip('E4c', 'run the updated file 07 first');
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M4 (owner): control after 25 hours: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M5 (owner): the last suggestion was DECLINED 30 hours ago ----------
reset role;
do $$
begin
update public.match_suggestions set status = 'DECLINED', created_at = now() - interval '30 hours'
  where status = 'PENDING'
    and ((user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid));

update public.transaction_requests set status = 'CANCELLED'
  where creator_id in (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid) and status::text = 'OPEN';

perform set_config('test.pairs_before', (select count(*) from public.match_suggestions
  where (user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid))::text, true);
exception when others then
  perform pg_temp.t_record('FAIL', 'M5 (owner): the last suggestion was DECLINED 30 hours ago: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M5: Student A posts SEND 5252 (4th time) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('SEND', 5252, 'USD', current_setting('test.a_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M5: Student A posts SEND 5252 (4th time): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M5: Student B posts RECEIVE 5252 (4th time) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('RECEIVE', 5252, 'USD', current_setting('test.b_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M5: Student B posts RECEIVE 5252 (4th time): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M5 (owner): check ----------
reset role;
do $$
begin
perform pg_temp.t_check('E5 after a DECLINED suggestion the same pair is never suggested again (even after 24 hours)',
  (select count(*) from public.match_suggestions
   where (user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid))
  = current_setting('test.pairs_before')::int,
  'a new suggestion was made');
exception when others then
  perform pg_temp.t_record('FAIL', 'M5 (owner): check: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M6 (owner): reset (no history between A and B) ----------
reset role;
do $$
begin
update public.transaction_requests set status = 'CANCELLED'
  where creator_id in (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid) and status::text = 'OPEN';
delete from public.match_suggestions
  where (user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid);
delete from public.user_blocks
  where (blocker_id = current_setting('test.a_id')::uuid and blocked_id = current_setting('test.b_id')::uuid) or (blocker_id = current_setting('test.b_id')::uuid and blocked_id = current_setting('test.a_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M6 (owner): reset (no history between A and B): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M6: Student A posts SEND 6161 ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('SEND', 6161, 'USD', current_setting('test.a_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M6: Student A posts SEND 6161: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M6: Student B posts RECEIVE 6161 ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('RECEIVE', 6161, 'USD', current_setting('test.b_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'M6: Student B posts RECEIVE 6161: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M6 (owner): make both requests look 2 days old ----------
reset role;
do $$
declare sid uuid; ra uuid; rb uuid;
begin
select id, request_a, request_b into sid, ra, rb from public.match_suggestions
  where status = 'PENDING'
    and ((user_a = current_setting('test.a_id')::uuid and user_b = current_setting('test.b_id')::uuid) or (user_a = current_setting('test.b_id')::uuid and user_b = current_setting('test.a_id')::uuid))
  limit 1;
if sid is null then
  perform pg_temp.t_skip('E6', 'no suggestion was created');
else
  perform set_config('test.sid6', sid::text, true);
  perform set_config('test.ra6', ra::text, true);
  perform set_config('test.rb6', rb::text, true);
  update public.transaction_requests set updated_at = now() - interval '2 days' where id in (ra, rb);
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M6 (owner): make both requests look 2 days old: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M6: Student A accepts ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
if coalesce(current_setting('test.sid6', true), '') <> '' then
  perform public.respond_match_suggestion(current_setting('test.sid6')::uuid, true);
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M6: Student A accepts: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M6: Student B accepts: matched ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
declare matched uuid;
begin
if coalesce(current_setting('test.sid6', true), '') <> '' then
  matched := public.respond_match_suggestion(current_setting('test.sid6')::uuid, true);
  perform pg_temp.t_check('E6a both accepted: the call returns the matched request id', matched is not null, 'it returned null');
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M6: Student B accepts: matched: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M6 (owner): updated_at ----------
reset role;
do $$
begin
if coalesce(current_setting('test.sid6', true), '') <> '' then
  if current_setting('test.f07a') = 'yes' then
    perform pg_temp.t_check('E6 a suggested match moves BOTH requests to the top (updated_at is new)',
      (select min(updated_at) from public.transaction_requests
       where id in (current_setting('test.ra6')::uuid, current_setting('test.rb6')::uuid)) >= now() - interval '1 minute',
      'updated_at was not changed');
  else
    perform pg_temp.t_skip('E6 updated_at', 'run the updated file 07 first');
  end if;
  perform pg_temp.t_check('E6b the older request is MATCHED with the other student, the other one is CANCELLED',
    (select status::text from public.transaction_requests where id = current_setting('test.ra6')::uuid) = 'MATCHED'
    and (select status::text from public.transaction_requests where id = current_setting('test.rb6')::uuid) = 'CANCELLED',
    'wrong statuses after the match');
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M6 (owner): updated_at: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- L1 (owner): clear the open requests of A and B ----------
reset role;
do $$
begin
update public.transaction_requests set status = 'CANCELLED'
  where creator_id in (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid) and status::text = 'OPEN';
exception when others then
  perform pg_temp.t_record('FAIL', 'L1 (owner): clear the open requests of A and B: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- L1: Student A posts 3 open requests ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
declare i int;
begin
if current_setting('test.f17') = 'yes' then
  for i in 1..3 loop
    insert into public.transaction_requests (type, amount, currency, creator_id)
    values ('SEND', 7000 + i, 'USD', current_setting('test.a_id')::uuid);
  end loop;
  perform pg_temp.t_refused('E7 a 4th open request is refused, with a plain message',
    $q$insert into public.transaction_requests (type, amount, currency, creator_id)
       values ('SEND', 7004, 'USD', current_setting('test.a_id')::uuid)$q$, 'P0001', '%3 open requests%');
else
  perform pg_temp.t_skip('E7 a 4th open request is refused', 'run file 17 first');
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'L1: Student A posts 3 open requests: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- L1 (owner): A cancels one request ----------
reset role;
do $$
begin
update public.transaction_requests set status = 'CANCELLED'
  where creator_id = current_setting('test.a_id')::uuid and amount = 7003 and status::text = 'OPEN';
exception when others then
  perform pg_temp.t_record('FAIL', 'L1 (owner): A cancels one request: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- L1: A can post again; the limit is per person ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
if current_setting('test.f17') = 'yes' then
  perform pg_temp.t_works('E7b after cancelling one, Student A can post a new request',
    $q$insert into public.transaction_requests (type, amount, currency, creator_id)
       values ('SEND', 7005, 'USD', current_setting('test.a_id')::uuid)$q$);
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'L1: A can post again; the limit is per person: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- L1: Student B is not limited by A ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
if current_setting('test.f17') = 'yes' then
  perform pg_temp.t_works('E7c Student B can still post (the limit is per person)',
    $q$insert into public.transaction_requests (type, amount, currency, creator_id)
       values ('RECEIVE', 7006, 'USD', current_setting('test.b_id')::uuid)$q$);
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'L1: Student B is not limited by A: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- A1: Student A asks for 3 appointments ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
declare i int;
begin
if current_setting('test.f11') = 'yes' then
  for i in 1..3 loop
    insert into public.appointments (student_id, requested_at, reason)
    values (current_setting('test.a_id')::uuid, now() + (i + 2) * interval '1 day', 'Test appointment ' || i || ' (rolled back)');
  end loop;
  perform pg_temp.t_refused('E8 a 4th active appointment is refused, with a plain message',
    $q$insert into public.appointments (student_id, requested_at, reason)
       values (current_setting('test.a_id')::uuid, now() + interval '10 days', 'Test appointment 4 (rolled back)')$q$,
    'P0001', '%3 appointments%');
else
  perform pg_temp.t_skip('E8 a 4th active appointment is refused', 'run file 11 first');
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'A1: Student A asks for 3 appointments: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- A1 (owner): one appointment is declined (no longer active) ----------
reset role;
do $$
begin
update public.appointments set status = 'DECLINED'
  where id = (select id from public.appointments
              where student_id = current_setting('test.a_id')::uuid and status = 'REQUESTED'
              order by requested_at limit 1);
exception when others then
  perform pg_temp.t_record('FAIL', 'A1 (owner): one appointment is declined (no longer active): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- A1: Student A can ask again ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
if current_setting('test.f11') = 'yes' then
  perform pg_temp.t_works('E8b after one is declined, a new appointment is allowed',
    $q$insert into public.appointments (student_id, requested_at, reason)
       values (current_setting('test.a_id')::uuid, now() + interval '12 days', 'Test appointment 5 (rolled back)')$q$);
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'A1: Student A can ask again: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
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
