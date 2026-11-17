-- Tests for sql/2026-11-16-01-members.sql (Student space membership approval).
-- Needs the four test accounts: run 00-test-accounts.sql once first (see README.md).
-- Extra needs: the PROFILE wilaya of Student A is the Governor's wilaya, and the profile
-- wilaya of Student B is a different one (the membership request uses the profile wilaya).
-- The ATTACHE account can be an attache or your admin account.
-- Everything is done inside the test (rolled back): B's membership is reset, a contact, a
-- consent and fake file rows are added. Nothing is saved: the result is shown as an error
-- at the end (RESULT SUMMARY).

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

-- ---------- Setup check 2: this file needs sql/2026-11-16-01-members.sql and the right wilayas ----------
do $$
declare aw text; bw text; gw text;
begin
  if to_regprocedure('public.is_member()') is null then
    raise exception 'SETUP PROBLEM: run sql/2026-11-16-01-members.sql first (is_member() does not exist).';
  end if;
  select wilaya into aw from public.profiles where id = current_setting('test.a_id')::uuid;
  select wilaya into bw from public.profiles where id = current_setting('test.b_id')::uuid;
  select rep_wilaya into gw from public.profiles where id = current_setting('test.g_id')::uuid;
  if aw is distinct from gw then
    raise exception 'SETUP PROBLEM: the PROFILE wilaya of Student A (%) must equal the Governor rep_wilaya (%). The membership request uses the profile wilaya.', aw, gw;
  end if;
  if bw is null or bw = gw then
    raise exception 'SETUP PROBLEM: the PROFILE wilaya of Student B (%) must be set and different from the Governor wilaya (%).', bw, gw;
  end if;
end $$;

-- ---------- M1 (owner): the backfill ----------
reset role;
do $$
declare bf timestamptz; n int;
begin
perform pg_temp.t_check('M1 the four test accounts already exist as rows (backfill) and are APPROVED',
  (select count(*) from public.space_members
   where user_id in (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid, current_setting('test.g_id')::uuid, current_setting('test.t_id')::uuid) and status = 'APPROVED') = 4,
  'status of the four accounts: ' || coalesce((select string_agg(status, ', ') from public.space_members
   where user_id in (current_setting('test.a_id')::uuid, current_setting('test.b_id')::uuid, current_setting('test.g_id')::uuid, current_setting('test.t_id')::uuid)), 'no rows'));
select min(m.decided_at) into bf from public.space_members m
  where m.decided_by is null and m.status = 'APPROVED' and m.requested_at = m.decided_at;
if bf is null then
  perform pg_temp.t_skip('M2 every account that existed before the backfill has a row', 'no backfilled row found');
else
  select count(*) into n from public.profiles p join auth.users u on u.id = p.id
  where u.created_at < bf and not exists (select 1 from public.space_members m where m.user_id = p.id);
  perform pg_temp.t_check('M2 every account that existed before the backfill has a row (' || n || ' without)', n = 0,
    n || ' older account(s) have no space_members row');
end if;
perform pg_temp.t_check('M3 pending_members() returns no phone and no email column',
  pg_get_function_result('public.pending_members()'::regprocedure) !~* 'phone|email',
  pg_get_function_result('public.pending_members()'::regprocedure));
exception when others then
  perform pg_temp.t_record('FAIL', 'M1 (owner): the backfill: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M4 (owner): fixtures ----------
reset role;
do $$
begin
-- something to read in the Student space, and a consent for B (so the upload rules are not what refuses it)
insert into public.staff_contacts (kind, name, phone) values ('attache', 'zz members test', '+213555123456');
insert into public.document_consents (user_id, version)
select current_setting('test.b_id')::uuid, 'test'
where not exists (select 1 from public.document_consents where user_id = current_setting('test.b_id')::uuid);
insert into storage.objects (bucket_id, name) values ('guide', 'zz_members_test.pdf');
-- Student B asked to join and is waiting (PENDING)
insert into public.space_members (user_id, status, wilaya)
select current_setting('test.b_id')::uuid, 'PENDING', p.wilaya from public.profiles p where p.id = current_setting('test.b_id')::uuid
on conflict (user_id) do update
  set status = 'PENDING', wilaya = excluded.wilaya, requested_at = now(), decided_by = null, decided_at = null;
exception when others then
  perform pg_temp.t_record('FAIL', 'M4 (owner): fixtures: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section B1: Student B waits for approval (not a member) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_check('M5 a waiting student is not a member (is_member() is false)', not public.is_member(), 'is_member() is true');
perform pg_temp.t_hidden('M6 an unapproved student cannot read the staff contacts',
  $q$select 1 from public.staff_contacts$q$);
perform pg_temp.t_hidden('M7 an unapproved student cannot read the guide',
  $q$select 1 from public.guide_sections$q$);
perform pg_temp.t_hidden('M7b an unapproved student cannot read the guide items',
  $q$select 1 from public.guide_items$q$);
perform pg_temp.t_hidden('M8 an unapproved student cannot read Help (faqs)',
  $q$select 1 from public.faqs$q$);
perform pg_temp.t_hidden('M8b an unapproved student cannot open the guide files',
  $q$select 1 from storage.objects where bucket_id = 'guide'$q$);
perform pg_temp.t_refused('M9 an unapproved student cannot add a bank account',
  $q$insert into public.bank_accounts (user_id, account_number) values (current_setting('test.b_id')::uuid, '33333333333333333333')$q$, '42501');
perform pg_temp.t_refused('M10 an unapproved student cannot add a passport number',
  $q$insert into public.passport_numbers (user_id, passport_number) values (current_setting('test.b_id')::uuid, 'ZZ654321')$q$, '42501');
perform pg_temp.t_refused('M11 an unapproved student cannot ask for an appointment',
  $q$insert into public.appointments (student_id, requested_at, reason)
     values (current_setting('test.b_id')::uuid, now() + interval '3 days', 'members test')$q$, '42501');
perform pg_temp.t_refused('M12 an unapproved student cannot upload a passport file',
  $q$insert into storage.objects (bucket_id, name) values ('passports', (current_setting('test.b_id') || '/zz_members.pdf'))$q$, '42501');
perform pg_temp.t_refused('M12b an unapproved student cannot upload a results file',
  $q$insert into storage.objects (bucket_id, name) values ('academic-results', (current_setting('test.b_id') || '/2025-2026/zz_members.pdf'))$q$, '42501');
perform pg_temp.t_rows('M13 a student can read their own membership row',
  $q$select 1 from public.space_members where user_id = current_setting('test.b_id')::uuid$q$, 1);
perform pg_temp.t_hidden('M14 a student cannot read another student membership row',
  $q$select 1 from public.space_members where user_id = current_setting('test.a_id')::uuid$q$);
perform pg_temp.t_refused('M15 a student cannot add a membership row',
  $q$insert into public.space_members (user_id, status) values (current_setting('test.b_id')::uuid, 'APPROVED')$q$, '42501');
perform pg_temp.t_noeffect('M16 a student cannot change a membership row (approve themselves)',
  $q$update public.space_members set status = 'APPROVED' where user_id = current_setting('test.b_id')::uuid$q$, '42501');
perform pg_temp.t_noeffect('M17 a student cannot delete a membership row',
  $q$delete from public.space_members where user_id = current_setting('test.b_id')::uuid$q$, '42501');
perform pg_temp.t_refused('M18 a student cannot approve themselves with the function',
  $q$select public.decide_membership(current_setting('test.b_id')::uuid, true)$q$, 'P0001', '%Not allowed%');
perform pg_temp.t_refused('M19 a student cannot see the join requests',
  $q$select * from public.pending_members()$q$, 'P0001', '%Not allowed%');
perform pg_temp.t_works('M20 a waiting student can still read alerts (emergency alerts stay open)',
  $q$select 1 from public.alerts$q$);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section B1: Student B waits for approval (not a member): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section A1: Student A (existing account, approved by the backfill) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_check('M21 an existing student is a member after the backfill', public.is_member(), 'is_member() is false');
perform pg_temp.t_rows('M22 a member can read the staff contacts (the test contact)',
  $q$select 1 from public.staff_contacts where name = 'zz members test'$q$, 1);
perform pg_temp.t_rows('M22b a member can open the guide files',
  $q$select 1 from storage.objects where bucket_id = 'guide' and name = 'zz_members_test.pdf'$q$, 1);
perform pg_temp.t_refused('M23 a student cannot approve another student',
  $q$select public.decide_membership(current_setting('test.b_id')::uuid, true)$q$, 'P0001', '%Not allowed%');
perform pg_temp.t_hidden('M24 a student cannot read another student membership row',
  $q$select 1 from public.space_members where user_id = current_setting('test.b_id')::uuid$q$);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section A1: Student A (existing account, approved by the backfill): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M25 (owner): Student A now waits for approval ----------
reset role;
do $$
begin
update public.space_members
set status = 'PENDING', requested_at = now(), decided_by = null, decided_at = null,
    wilaya = (select wilaya from public.profiles where id = current_setting('test.a_id')::uuid)
where user_id = current_setting('test.a_id')::uuid;
exception when others then
  perform pg_temp.t_record('FAIL', 'M25 (owner): Student A now waits for approval: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section G1: the Governor of Student A wilaya ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.g_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_check('M26 a Governor is a member (is_member() is true)', public.is_member(), 'is_member() is false');
perform pg_temp.t_rows('M27 the Governor sees the request of Student A (own wilaya)',
  $q$select 1 from public.pending_members() where user_id = current_setting('test.a_id')::uuid$q$, 1);
perform pg_temp.t_rows('M28 the Governor does not see the request of Student B (other wilaya)',
  $q$select 1 from public.pending_members() where user_id = current_setting('test.b_id')::uuid$q$, 0);
perform pg_temp.t_rows('M28b the Governor reads the membership row of Student A',
  $q$select 1 from public.space_members where user_id = current_setting('test.a_id')::uuid$q$, 1);
perform pg_temp.t_hidden('M28c the Governor cannot read the membership row of Student B (other wilaya)',
  $q$select 1 from public.space_members where user_id = current_setting('test.b_id')::uuid$q$);
perform pg_temp.t_refused('M29 a Governor of another wilaya cannot approve (Student B)',
  $q$select public.decide_membership(current_setting('test.b_id')::uuid, true)$q$, 'P0001', '%Not allowed%');
perform pg_temp.t_works('M30 a Governor can approve someone of their own wilaya (Student A)',
  $q$select public.decide_membership(current_setting('test.a_id')::uuid, true)$q$);
perform pg_temp.t_refused('M31 a request cannot be answered twice',
  $q$select public.decide_membership(current_setting('test.a_id')::uuid, false)$q$, 'P0001', '%already answered%');
perform pg_temp.t_refused('M31b nobody can decide about themselves (the Governor)',
  $q$select public.decide_membership(current_setting('test.g_id')::uuid, true)$q$, 'P0001', '%Not allowed%');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section G1: the Governor of Student A wilaya: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M32 (owner): the answer was saved and Student A was told ----------
reset role;
do $$
begin
perform pg_temp.t_check('M32 Student A is APPROVED, decided by the Governor',
  (select status from public.space_members where user_id = current_setting('test.a_id')::uuid) = 'APPROVED'
  and (select decided_by from public.space_members where user_id = current_setting('test.a_id')::uuid) = current_setting('test.g_id')::uuid
  and (select decided_at from public.space_members where user_id = current_setting('test.a_id')::uuid) is not null,
  'wrong status, decided_by or decided_at');
perform pg_temp.t_check('M33 Student A got a notification that the request was approved',
  exists (select 1 from public.notifications
          where user_id = current_setting('test.a_id')::uuid and type::text = 'MEMBERSHIP_UPDATE'
            and content like '%approved%' and created_at >= now()),
  'no MEMBERSHIP_UPDATE notification (is the enum value added? run the whole file)');
exception when others then
  perform pg_temp.t_record('FAIL', 'M32 (owner): the answer was saved and Student A was told: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section T1: the Educational Attache (or admin) approves anyone ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.t_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_rows('M34 the attache sees the request of Student B (any wilaya)',
  $q$select 1 from public.pending_members() where user_id = current_setting('test.b_id')::uuid$q$, 1);
perform pg_temp.t_works('M35 the attache can approve a student of any wilaya (Student B)',
  $q$select public.decide_membership(current_setting('test.b_id')::uuid, true)$q$);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section T1: the Educational Attache (or admin) approves anyone: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section B2: Student B is approved now (control: the rules open again) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_check('M36 an approved student is a member', public.is_member(), 'is_member() is false');
perform pg_temp.t_rows('M37 an approved student can read the staff contacts',
  $q$select 1 from public.staff_contacts where name = 'zz members test'$q$, 1);
perform pg_temp.t_works('M38 an approved student can add a bank account',
  $q$insert into public.bank_accounts (user_id, account_number) values (current_setting('test.b_id')::uuid, '33333333333333333333')
     on conflict (user_id) do update set account_number = excluded.account_number$q$);
perform pg_temp.t_works('M39 an approved student can upload a passport file',
  $q$insert into storage.objects (bucket_id, name) values ('passports', (current_setting('test.b_id') || '/zz_members.pdf'))$q$);
perform pg_temp.t_works('M40 an approved student can ask for an appointment',
  $q$insert into public.appointments (student_id, requested_at, reason)
     values (current_setting('test.b_id')::uuid, now() + interval '3 days', 'members test')$q$);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section B2: Student B is approved now (control: the rules open again): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M41 (owner): Student A was rejected just now ----------
reset role;
do $$
begin
update public.space_members
set status = 'REJECTED', decided_by = current_setting('test.g_id')::uuid, decided_at = now()
where user_id = current_setting('test.a_id')::uuid;
exception when others then
  perform pg_temp.t_record('FAIL', 'M41 (owner): Student A was rejected just now: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section A2: asking again ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_check('M41 a rejected student is not a member', not public.is_member(), 'is_member() is true');
perform pg_temp.t_refused('M42 a rejected student cannot ask again within 24 hours',
  $q$select public.request_membership()$q$, 'P0001', '%24 hours%');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section A2: asking again: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M43 (owner): the rejection is 25 hours old ----------
reset role;
do $$
begin
update public.space_members set decided_at = now() - interval '25 hours' where user_id = current_setting('test.a_id')::uuid;
perform set_config('test.notified_before',
  (select count(*) from public.notifications
   where user_id = current_setting('test.g_id')::uuid and type::text = 'MEMBERSHIP_UPDATE' and created_at >= now())::text, true);
exception when others then
  perform pg_temp.t_record('FAIL', 'M43 (owner): the rejection is 25 hours old: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section A3: Student A asks again ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
declare st text;
begin
st := public.request_membership();
perform pg_temp.t_check('M43 after 24 hours a rejected student can ask again (status PENDING)', st = 'PENDING', 'status ' || st);
st := public.request_membership();
perform pg_temp.t_check('M44 asking twice keeps ONE pending request', st = 'PENDING', 'status ' || st);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section A3: Student A asks again: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- M45 (owner): who was told, and what the text says ----------
reset role;
do $$
begin
perform pg_temp.t_check('M45 the Governor of the wilaya was told once (not twice)',
  (select count(*) from public.notifications
   where user_id = current_setting('test.g_id')::uuid and type::text = 'MEMBERSHIP_UPDATE' and created_at >= now())
  = current_setting('test.notified_before')::int + 1,
  'the Governor got a different number of notifications');
perform pg_temp.t_check('M46 the text has no personal data (no name of the student)',
  not exists (select 1 from public.notifications n join public.profiles p on p.id = current_setting('test.a_id')::uuid
              where n.user_id = current_setting('test.g_id')::uuid and n.type::text = 'MEMBERSHIP_UPDATE' and n.created_at >= now()
                and p.full_name is not null and length(trim(p.full_name)) > 2
                and n.content ilike '%' || trim(p.full_name) || '%'),
  'a notification contains the student name');
if exists (select 1 from public.profiles where id = current_setting('test.t_id')::uuid and role = 'attache') then
  perform pg_temp.t_check('M47 the attache was told too',
    exists (select 1 from public.notifications
            where user_id = current_setting('test.t_id')::uuid and type::text = 'MEMBERSHIP_UPDATE' and created_at >= now()),
    'the attache got no notification');
else
  perform pg_temp.t_skip('M47 the attache was told too', 'the ATTACHE account is an admin (only the attache role is notified)');
end if;
exception when others then
  perform pg_temp.t_record('FAIL', 'M45 (owner): who was told, and what the text says: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
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
