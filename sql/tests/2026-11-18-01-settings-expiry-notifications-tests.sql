-- Tests for the four SQL files of 2026-11-18:
--   2026-11-18-01-notification-delete.sql  (a user deletes only their own notifications)
--   2026-11-18-02-app-settings.sql         (app_settings: everybody reads, the app cannot change)
--   2026-11-18-03-request-expiry.sql       (OPEN requests older than 48 hours are cancelled)
--   2026-11-18-04-attestation-dates.sql    (dates of the attestation tracker steps)
-- Needs the four test accounts: run 00-test-accounts.sql once first (see README.md).
-- Run the four SQL files first (in that order). The ATTACHE account can be an attache or admin.
-- Everything is done inside the test (rolled back): fake requests, notifications and an
-- attestation request are added, and the expiry function runs on the whole table inside the
-- test only. Nothing is saved: the result is shown as an error at the end (RESULT SUMMARY).

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
  if a_id = t_id then
    raise exception 'SETUP PROBLEM: the four accounts must be four different accounts, but Student A and the Educational Attache are the same account (%).', a_mail;
  end if;
  if b_id = t_id then
    raise exception 'SETUP PROBLEM: the four accounts must be four different accounts, but Student B and the Educational Attache are the same account (%).', b_mail;
  end if;
  perform set_config('test.a_id', a_id::text, true);
  perform set_config('test.b_id', b_id::text, true);
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

-- ---------- Setup check 2: this file needs the four new SQL files ----------
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'notifications'
                 and policyname = 'notifications_delete_own') then
    raise exception 'SETUP PROBLEM: run sql/2026-11-18-01-notification-delete.sql first (policy notifications_delete_own is missing).';
  end if;
  if to_regclass('public.app_settings') is null then
    raise exception 'SETUP PROBLEM: run sql/2026-11-18-02-app-settings.sql first (app_settings does not exist).';
  end if;
  if to_regprocedure('public.expire_open_requests()') is null then
    raise exception 'SETUP PROBLEM: run sql/2026-11-18-03-request-expiry.sql first (expire_open_requests() does not exist).';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public'
                 and table_name = 'attestation_requests' and column_name = 'reviewed_at') then
    raise exception 'SETUP PROBLEM: run sql/2026-11-18-04-attestation-dates.sql first (attestation_requests.reviewed_at is missing).';
  end if;
end $$;

-- ---------- E0 (owner): fixtures ----------
reset role;
do $$
declare rid uuid;
begin
-- (inside the test only) the two students have no other open request: a person can have 3 at most
update public.transaction_requests set status = 'CANCELLED'
where creator_id in (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid) and status::text = 'OPEN';
-- three notifications (two for Student A, one for Student B)
insert into public.notifications (user_id, type, content) values
  (current_setting('test.a_id')::uuid, 'MATCH_FOUND', 'zz del test A1'),
  (current_setting('test.a_id')::uuid, 'MATCH_FOUND', 'zz del test A2'),
  (current_setting('test.b_id')::uuid, 'MATCH_FOUND', 'zz del test B1');

-- requests: old and OPEN (49 h), younger and OPEN (30 h), brand new, old but MATCHED (60 h)
insert into public.transaction_requests (type, amount, currency, creator_id, created_at)
values ('SEND', 6101, 'USD', current_setting('test.a_id')::uuid, now() - interval '49 hours') returning id into rid;
perform set_config('test.r_old', rid::text, true);
insert into public.transaction_requests (type, amount, currency, creator_id, created_at)
values ('SEND', 6102, 'USD', current_setting('test.a_id')::uuid, now() - interval '30 hours') returning id into rid;
perform set_config('test.r_30h', rid::text, true);
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('SEND', 6103, 'USD', current_setting('test.b_id')::uuid) returning id into rid;
perform set_config('test.r_new', rid::text, true);
insert into public.transaction_requests (type, amount, currency, creator_id, matched_with_id, status, created_at)
values ('SEND', 6104, 'USD', current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid, 'MATCHED', now() - interval '60 hours') returning id into rid;
perform set_config('test.r_matched', rid::text, true);
-- Student B asks for the same amount, opposite type: the database suggests a match with the old request
insert into public.transaction_requests (type, amount, currency, creator_id)
values ('RECEIVE', 6101, 'USD', current_setting('test.b_id')::uuid);
exception when others then
  perform pg_temp.t_record('FAIL', 'E0 (owner): fixtures: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section A: Student A ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_rows('E1 a student sees their own notifications',
  $q$select 1 from public.notifications where content like 'zz del test A%'$q$, 2);
perform pg_temp.t_noeffect('E2 a student cannot delete another student notification',
  $q$delete from public.notifications where content = 'zz del test B1'$q$, '42501');
perform pg_temp.t_rowcount('E3 a student can delete their own notification (control)',
  $q$delete from public.notifications where content = 'zz del test A1'$q$, 1);
perform pg_temp.t_noeffect('E4 a student cannot delete emergency alerts (the alerts table)',
  $q$delete from public.alerts$q$, '42501');

perform pg_temp.t_works('E5 a student can read app_settings',
  $q$select 1 from public.app_settings$q$);
perform pg_temp.t_rows('E6 the parallel rate offset setting exists',
  $q$select 1 from public.app_settings where key = 'parallel_rate_offset'$q$, 1);
perform pg_temp.t_rows('E7 the request expiry setting exists',
  $q$select 1 from public.app_settings where key = 'request_expiry_hours'$q$, 1);
perform pg_temp.t_noeffect('E8 a student cannot change app_settings',
  $q$update public.app_settings set value = 99 where key = 'parallel_rate_offset'$q$, '42501');
perform pg_temp.t_refused('E9 a student cannot add a setting',
  $q$insert into public.app_settings (key, value) values ('zz_test', 1)$q$, '42501');
perform pg_temp.t_noeffect('E10 a student cannot delete a setting',
  $q$delete from public.app_settings where key = 'request_expiry_hours'$q$, '42501');

perform pg_temp.t_refused('E11 a student cannot run the expiry function',
  $q$select public.expire_open_requests()$q$, '42501');

-- A student cannot mark a request as EXPIRED (checked as the owner afterwards)
insert into public.transaction_requests (type, amount, currency, creator_id, cancel_reason)
values ('SEND', 6105, 'USD', current_setting('test.a_id')::uuid, 'EXPIRED');
begin
  update public.transaction_requests set cancel_reason = 'EXPIRED'
  where creator_id = current_setting('test.a_id')::uuid and amount = 6101;
exception when others then
  null; -- refused is fine too
end;
exception when others then
  perform pg_temp.t_record('FAIL', 'Section A: Student A: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section B: Student B ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_noeffect('E12 another student cannot delete my notification',
  $q$delete from public.notifications where content = 'zz del test A2'$q$, '42501');
perform pg_temp.t_works('E13 Student B can read app_settings',
  $q$select 1 from public.app_settings$q$);
perform pg_temp.t_noeffect('E14 a student cannot change the attestation step dates',
  $q$update public.attestation_requests set reviewed_at = now()$q$, '42501');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section B: Student B: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section anon: signed out ----------
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $$
begin
perform pg_temp.t_refused('E15 a signed-out user cannot delete notifications',
  $q$delete from public.notifications$q$, '42501');
perform pg_temp.t_hidden('E16 a signed-out user cannot read app_settings',
  $q$select 1 from public.app_settings$q$);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section anon: signed out: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section T: the Educational Attache (or admin) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.t_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_noeffect('E17 the attache cannot change app_settings from the app (by SQL only)',
  $q$update public.app_settings set value = 99 where key = 'parallel_rate_offset'$q$, '42501');
perform pg_temp.t_noeffect('E18 the attache cannot delete a student notification',
  $q$delete from public.notifications where content = 'zz del test A2'$q$, '42501');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section T: the Educational Attache (or admin): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- E19 (owner): deletes and the EXPIRED mark ----------
reset role;
do $$
begin
perform pg_temp.t_check('E19 only the own notification was deleted (A1 gone; A2 and B1 are still there)',
  not exists (select 1 from public.notifications where content = 'zz del test A1')
  and exists (select 1 from public.notifications where content = 'zz del test A2')
  and exists (select 1 from public.notifications where content = 'zz del test B1'),
  'the notifications left do not match');
perform pg_temp.t_check('E20 a student could not set cancel_reason (insert and update)',
  (select count(*) from public.transaction_requests
   where creator_id = current_setting('test.a_id')::uuid and amount in (6101, 6105) and cancel_reason is not null) = 0,
  'a cancel_reason was set by a student');
perform pg_temp.t_check('E21 the settings were not changed by the students',
  (select value from public.app_settings where key = 'parallel_rate_offset') is not null
  and (select count(*) from public.app_settings where key = 'zz_test') = 0
  and (select value from public.app_settings where key = 'request_expiry_hours') = 48,
  'a setting was changed (the expiry is expected to be 48)');
exception when others then
  perform pg_temp.t_record('FAIL', 'E19 (owner): deletes and the EXPIRED mark: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- E22 (owner): the expiry job function (48 hours) ----------
reset role;
do $$
declare n int; sug int;
begin
n := public.expire_open_requests();
perform pg_temp.t_check('E22 the function cancelled at least the old test request', n >= 1, 'it returned ' || n);
perform pg_temp.t_check('E23 an OPEN request older than 48 hours is CANCELLED with cancel_reason EXPIRED',
  (select status::text || '/' || coalesce(cancel_reason, '') from public.transaction_requests
   where id = current_setting('test.r_old')::uuid) = 'CANCELLED/EXPIRED',
  'status/reason: ' || coalesce((select status::text || '/' || coalesce(cancel_reason, '') from public.transaction_requests
   where id = current_setting('test.r_old')::uuid), 'row not found'));
perform pg_temp.t_check('E24 the cancelled request got its end date (ended_at)',
  (select ended_at from public.transaction_requests where id = current_setting('test.r_old')::uuid) is not null,
  'ended_at is empty');
perform pg_temp.t_check('E25 a request of 30 hours stays OPEN (limit 48)',
  (select status::text from public.transaction_requests where id = current_setting('test.r_30h')::uuid) = 'OPEN',
  'it is not OPEN');
perform pg_temp.t_check('E26 a brand new request stays OPEN',
  (select status::text from public.transaction_requests where id = current_setting('test.r_new')::uuid) = 'OPEN',
  'it is not OPEN');
perform pg_temp.t_check('E27 an old MATCHED request is never touched',
  (select status::text from public.transaction_requests where id = current_setting('test.r_matched')::uuid) = 'MATCHED',
  'it is not MATCHED');
select count(*) into sug from public.match_suggestions
  where current_setting('test.r_old')::uuid in (request_a, request_b);
if sug = 0 then
  perform pg_temp.t_skip('E28 pending match suggestions of an expired request are closed', 'no suggestion was created for the test request');
else
  perform pg_temp.t_check('E28 pending match suggestions of an expired request are closed',
    not exists (select 1 from public.match_suggestions
                where current_setting('test.r_old')::uuid in (request_a, request_b) and status = 'PENDING'),
    'a suggestion is still PENDING');
end if;
n := public.expire_open_requests();
perform pg_temp.t_check('E29 a second run cancels nothing more', n = 0, 'it cancelled ' || n);

-- the setting is used: 24 hours cancels the 30 hour request
update public.app_settings set value = 24 where key = 'request_expiry_hours';
n := public.expire_open_requests();
perform pg_temp.t_check('E30 with request_expiry_hours = 24 the 30 hour request is cancelled too',
  n >= 1 and (select status::text || '/' || coalesce(cancel_reason, '') from public.transaction_requests
              where id = current_setting('test.r_30h')::uuid) = 'CANCELLED/EXPIRED',
  'it returned ' || n);
perform pg_temp.t_check('E31 a new request is still OPEN with the 24 hour setting',
  (select status::text from public.transaction_requests where id = current_setting('test.r_new')::uuid) = 'OPEN',
  'it is not OPEN');
begin
  perform pg_temp.t_check('E32 the cron job expire-open-requests runs every 15 minutes',
    (select count(*) from cron.job where jobname = 'expire-open-requests' and schedule = '*/15 * * * *') = 1,
    'job missing or wrong schedule');
exception when others then
  perform pg_temp.t_skip('E32 the cron job expire-open-requests', 'cron.job could not be read: ' || sqlerrm);
end;
exception when others then
  perform pg_temp.t_record('FAIL', 'E22 (owner): the expiry job function (48 hours): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section B2: Student B after the expiry ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_rows('E33 an expired request is no longer in the open list',
  $q$select 1 from public.transaction_requests where status = 'OPEN' and id = current_setting('test.r_old')::uuid$q$, 0);
perform pg_temp.t_rows('E34 a request that is still open stays in the open list (control)',
  $q$select 1 from public.transaction_requests where status = 'OPEN' and id = current_setting('test.r_new')::uuid$q$, 1);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section B2: Student B after the expiry: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- E35 (owner): attestation dates ----------
reset role;
do $$
declare rid uuid;
begin
-- (inside the test only) Student B has no other open attestation request
delete from public.attestation_requests where user_id = current_setting('test.b_id')::uuid and status in ('PENDING', 'IN_REVIEW');
insert into public.attestation_requests (user_id, passport_path, entry_date)
values (current_setting('test.b_id')::uuid, (current_setting('test.b_id') || '/zz_dates.pdf'), date '2025-01-01') returning id into rid;
perform pg_temp.t_check('E35 a new request has Received (created_at) and no review date yet',
  (select created_at is not null and reviewed_at is null and rejected_at is null and issued_at is null
   from public.attestation_requests where id = rid), 'unexpected dates');
update public.attestation_requests set status = 'IN_REVIEW' where id = rid;
perform pg_temp.t_check('E36 IN_REVIEW sets reviewed_at',
  (select reviewed_at is not null and rejected_at is null from public.attestation_requests where id = rid),
  'reviewed_at is empty');
update public.attestation_requests set status = 'REJECTED', note = 'zz test note' where id = rid;
perform pg_temp.t_check('E37 REJECTED sets rejected_at (reviewed_at is kept)',
  (select rejected_at is not null and reviewed_at is not null and issued_at is null from public.attestation_requests where id = rid),
  'rejected_at is empty');
-- a second request goes straight to ISSUED (the review step is skipped: no review date)
insert into public.attestation_requests (user_id, passport_path, entry_date)
values (current_setting('test.b_id')::uuid, (current_setting('test.b_id') || '/zz_dates2.pdf'), date '2025-01-01') returning id into rid;
update public.attestation_requests set status = 'ISSUED', attestation_path = (current_setting('test.b_id') || '/zz_issued.pdf') where id = rid;
perform pg_temp.t_check('E38 ISSUED sets issued_at; a skipped review has no review date',
  (select issued_at is not null and reviewed_at is null and rejected_at is null from public.attestation_requests where id = rid),
  'unexpected dates');
exception when others then
  perform pg_temp.t_record('FAIL', 'E35 (owner): attestation dates: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
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
