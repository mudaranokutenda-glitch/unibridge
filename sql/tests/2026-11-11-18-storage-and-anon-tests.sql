-- Security tests: private storage files and signed-out access.
-- Needs the four test accounts: run 00-test-accounts.sql once first (see README.md).
-- As owner, fake file ROWS are added to storage.objects (rolled back; no real
-- file exists) for the buckets passports, academic-results, attestations and
-- chat-photos, all belonging to Student A. Then each person tries to see and
-- delete them.
-- By design (see the policies): the owner of a results file CAN delete it;
-- nobody can delete passports, attestations or chat photos; the attache CAN read
-- attestations (staff upload them) but never passports or results directly.
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

-- ---------- Section 1 (owner): fake files and fixtures ----------
reset role;
do $$
declare rq uuid;
begin
-- A throw-away request of Student A (CANCELLED, so the 3-open-requests limit
-- does not matter). Its id is the chat-photos folder.
insert into public.transaction_requests (type, amount, currency, creator_id, status)
values ('SEND', 8888, 'USD', current_setting('test.a_id')::uuid, 'CANCELLED')
returning id into rq;
perform set_config('test.rq', rq::text, true);

insert into storage.objects (bucket_id, name) values
  ('passports',        (current_setting('test.a_id') || '/zz_test_passport.pdf')),
  ('academic-results', (current_setting('test.a_id') || '/2025-2026/zz_test_results.pdf')),
  ('academic-results', (current_setting('test.a_id') || '/2025-2026/zz_test_delete_control.pdf')),
  ('attestations',     (current_setting('test.a_id') || '/zz_test_attestation.pdf')),
  ('chat-photos',      rq::text || '/zz_test_photo.jpg');

-- Fixtures for the signed-out checks: every table has at least one row.
insert into public.bank_accounts (user_id, account_number) values (current_setting('test.a_id')::uuid, '11111111111111111111')
  on conflict (user_id) do nothing;
insert into public.passport_numbers (user_id, passport_number) values (current_setting('test.a_id')::uuid, 'ZZ123456')
  on conflict (user_id) do nothing;
insert into public.user_phones (user_id, phone) values (current_setting('test.a_id')::uuid, '+213555123456')
  on conflict (user_id) do nothing;
insert into public.document_consents (user_id, version)
select current_setting('test.a_id')::uuid, 'test'
where not exists (select 1 from public.document_consents where user_id = current_setting('test.a_id')::uuid);
insert into public.attestation_requests (user_id, passport_path, entry_date)
values (current_setting('test.a_id')::uuid, (current_setting('test.a_id') || '/zz_test.pdf'), current_date - 100)
on conflict do nothing;
insert into public.staff_contacts (kind, name, phone) values ('attache', 'zz test contact', '+213555123456');
insert into public.guide_items (section_id, title) values ('BANK', 'zz test item');

-- The Storage API sets this when it deletes; without it Supabase refuses ALL
-- direct deletes on storage.objects, and the test would not look at our policies.
perform set_config('storage.allow_delete_query', 'true', true);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 1 (owner): fake files and fixtures: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 2: Student A (the owner of the files) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.a_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_rows('T1 Student A can see own passport file',
  $q$select 1 from storage.objects where bucket_id = 'passports' and name = (current_setting('test.a_id') || '/zz_test_passport.pdf')$q$, 1);
perform pg_temp.t_rows('T2 Student A can see own results file',
  $q$select 1 from storage.objects where bucket_id = 'academic-results' and name = (current_setting('test.a_id') || '/2025-2026/zz_test_results.pdf')$q$, 1);
perform pg_temp.t_rows('T3 Student A can see own attestation file',
  $q$select 1 from storage.objects where bucket_id = 'attestations' and name = (current_setting('test.a_id') || '/zz_test_attestation.pdf')$q$, 1);
perform pg_temp.t_rows('T4 Student A can see the photo of own request chat',
  format('select 1 from storage.objects where bucket_id = %L and name = %L', 'chat-photos', current_setting('test.rq') || '/zz_test_photo.jpg'), 1);
-- Nobody can delete passports, attestations, chat photos (no delete policy).
perform pg_temp.t_noeffect('T5 Student A cannot delete own passport, attestation or chat photo',
  $q$delete from storage.objects where bucket_id in ('passports', 'attestations', 'chat-photos') and name like '%zz\_test\_%'$q$);
-- By design a student can delete own results (control: proves the delete setting works,
-- so the 0-row results of the other people below are really decided by the policies).
perform pg_temp.t_rowcount('T6 (control) Student A can delete own results file, by design',
  $q$delete from storage.objects where bucket_id = 'academic-results' and name = (current_setting('test.a_id') || '/2025-2026/zz_test_delete_control.pdf')$q$, 1);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 2: Student A (the owner of the files): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 3: Student B (a stranger) ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.b_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_hidden('T7 Student B cannot see A passport file',
  $q$select 1 from storage.objects where bucket_id = 'passports' and name like '%zz\_test\_%'$q$);
perform pg_temp.t_hidden('T8 Student B cannot see A results file',
  $q$select 1 from storage.objects where bucket_id = 'academic-results' and name like '%zz\_test\_%'$q$);
perform pg_temp.t_hidden('T9 Student B cannot see A attestation file',
  $q$select 1 from storage.objects where bucket_id = 'attestations' and name like '%zz\_test\_%'$q$);
perform pg_temp.t_hidden('T10 Student B cannot see the photo of a chat they are not in',
  $q$select 1 from storage.objects where bucket_id = 'chat-photos' and name like '%zz\_test\_%'$q$);
perform pg_temp.t_noeffect('T11 Student B cannot delete any of them',
  $q$delete from storage.objects where name like '%zz\_test\_%'$q$);
perform pg_temp.t_refused('T11b Student B cannot add a file into A passport folder',
  $q$insert into storage.objects (bucket_id, name) values ('passports', (current_setting('test.a_id') || '/zz_test_b.pdf'))$q$, '42501');
perform pg_temp.t_refused('T11c Student B cannot add a file into A attestation folder',
  $q$insert into storage.objects (bucket_id, name) values ('attestations', (current_setting('test.a_id') || '/zz_test_b.pdf'))$q$, '42501');
perform pg_temp.t_refused('T11d Student B cannot add a photo into a chat they are not in',
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'chat-photos', current_setting('test.rq') || '/zz_test_b.jpg'), '42501');
perform pg_temp.t_hidden('T11e Student B cannot read test_support.accounts (the tester emails)',
  $q$select 1 from test_support.accounts$q$);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 3: Student B (a stranger): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 4: the Governor of A wilaya ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.g_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_hidden('T12 a Governor cannot see passport files',
  $q$select 1 from storage.objects where bucket_id = 'passports' and name like '%zz\_test\_%'$q$);
perform pg_temp.t_hidden('T13 a Governor cannot see attestation files',
  $q$select 1 from storage.objects where bucket_id = 'attestations' and name like '%zz\_test\_%'$q$);
perform pg_temp.t_hidden('T14 a Governor cannot see results files directly (only through the logged function)',
  $q$select 1 from storage.objects where bucket_id = 'academic-results' and name like '%zz\_test\_%'$q$);
perform pg_temp.t_hidden('T15 a Governor cannot see chat photos',
  $q$select 1 from storage.objects where bucket_id = 'chat-photos' and name like '%zz\_test\_%'$q$);
perform pg_temp.t_noeffect('T16 a Governor cannot delete any of them',
  $q$delete from storage.objects where name like '%zz\_test\_%'$q$);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 4: the Governor of A wilaya: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 5: the Educational Attache ----------
reset role;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('test.t_id')), true);
set local role authenticated;
do $$
begin
perform pg_temp.t_hidden('T17 the attache cannot read passport files directly (only through the logged function)',
  $q$select 1 from storage.objects where bucket_id = 'passports' and name like '%zz\_test\_%'$q$);
perform pg_temp.t_hidden('T18 the attache cannot read results files directly (only through the logged function)',
  $q$select 1 from storage.objects where bucket_id = 'academic-results' and name like '%zz\_test\_%'$q$);
perform pg_temp.t_rows('T19 the attache CAN read attestation files (staff upload them, by design)',
  $q$select 1 from storage.objects where bucket_id = 'attestations' and name like '%zz\_test\_%'$q$, 1);
perform pg_temp.t_hidden('T20 the attache cannot see chat photos',
  $q$select 1 from storage.objects where bucket_id = 'chat-photos' and name like '%zz\_test\_%'$q$);
perform pg_temp.t_noeffect('T21 the attache cannot delete any file',
  $q$delete from storage.objects where name like '%zz\_test\_%'$q$);
perform pg_temp.t_refused('T21b the attache cannot add a file into a student passport folder',
  $q$insert into storage.objects (bucket_id, name) values ('passports', (current_setting('test.a_id') || '/zz_test_t.pdf'))$q$, '42501');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 5: the Educational Attache: stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 6 (owner): the signed-out check is meaningful (no empty tables) ----------
reset role;
do $$
declare t text; n int;
begin
foreach t in array array['profiles', 'student_records', 'bank_accounts', 'passport_numbers',
                         'user_phones', 'attestation_requests', 'staff_contacts', 'guide_items'] loop
  execute format('select count(*) from public.%I', t) into n;
  if n = 0 then
    perform pg_temp.t_skip('T22 signed-out check on ' || t, 'the table is empty, so the check would prove nothing');
  end if;
end loop;
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 6 (owner): the signed-out check is meaningful (no empty tables): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 7: signed out (role anon) ----------
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $$
begin
perform pg_temp.t_hidden('T22a signed-out cannot read profiles', $q$select 1 from public.profiles$q$);
perform pg_temp.t_hidden('T22b signed-out cannot read student_records', $q$select 1 from public.student_records$q$);
perform pg_temp.t_hidden('T22c signed-out cannot read bank_accounts', $q$select 1 from public.bank_accounts$q$);
perform pg_temp.t_hidden('T22d signed-out cannot read passport_numbers', $q$select 1 from public.passport_numbers$q$);
perform pg_temp.t_hidden('T22e signed-out cannot read user_phones', $q$select 1 from public.user_phones$q$);
perform pg_temp.t_hidden('T22f signed-out cannot read attestation_requests', $q$select 1 from public.attestation_requests$q$);
perform pg_temp.t_hidden('T22g signed-out cannot read staff_contacts', $q$select 1 from public.staff_contacts$q$);
perform pg_temp.t_hidden('T22h signed-out cannot read guide_items', $q$select 1 from public.guide_items$q$);
perform pg_temp.t_hidden('T22i signed-out cannot read test_support.accounts (the tester emails)',
  $q$select 1 from test_support.accounts$q$);
perform pg_temp.t_hidden('T23 signed-out cannot see any private file',
  $q$select 1 from storage.objects where bucket_id in ('passports', 'academic-results', 'attestations', 'chat-photos')$q$);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 7: signed out (role anon): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
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
