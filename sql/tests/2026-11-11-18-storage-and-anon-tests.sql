-- Security tests: private storage files and signed-out access.
-- Replace STUDENT-A-ID, STUDENT-B-ID, GOVERNOR-ID, ATTACHE-ID (see README.md).
-- As owner, fake file ROWS are added to storage.objects (rolled back; no real
-- file exists) for the buckets passports, academic-results, attestations and
-- chat-photos, all belonging to Student A. Then each person tries to see and
-- delete them.
-- By design (see the policies): the owner of a results file CAN delete it;
-- nobody can delete passports, attestations or chat photos; the attache CAN read
-- attestations (staff upload them) but never passports or results directly.
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

-- ---------- Section 1 (owner): fake files and fixtures ----------
reset role;
do $$
declare rq uuid;
begin
-- A throw-away request of Student A (CANCELLED, so the 3-open-requests limit
-- does not matter). Its id is the chat-photos folder.
insert into public.transaction_requests (type, amount, currency, creator_id, status)
values ('SEND', 8888, 'USD', 'STUDENT-A-ID', 'CANCELLED')
returning id into rq;
perform set_config('test.rq', rq::text, true);

insert into storage.objects (bucket_id, name) values
  ('passports',        'STUDENT-A-ID/zz_test_passport.pdf'),
  ('academic-results', 'STUDENT-A-ID/2025-2026/zz_test_results.pdf'),
  ('academic-results', 'STUDENT-A-ID/2025-2026/zz_test_delete_control.pdf'),
  ('attestations',     'STUDENT-A-ID/zz_test_attestation.pdf'),
  ('chat-photos',      rq::text || '/zz_test_photo.jpg');

-- Fixtures for the signed-out checks: every table has at least one row.
insert into public.bank_accounts (user_id, account_number) values ('STUDENT-A-ID', '11111111111111111111')
  on conflict (user_id) do nothing;
insert into public.passport_numbers (user_id, passport_number) values ('STUDENT-A-ID', 'ZZ123456')
  on conflict (user_id) do nothing;
insert into public.user_phones (user_id, phone) values ('STUDENT-A-ID', '+213555123456')
  on conflict (user_id) do nothing;
insert into public.document_consents (user_id, version)
select 'STUDENT-A-ID', 'test'
where not exists (select 1 from public.document_consents where user_id = 'STUDENT-A-ID');
insert into public.attestation_requests (user_id, passport_path, entry_date)
values ('STUDENT-A-ID', 'STUDENT-A-ID/zz_test.pdf', current_date - 100)
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
select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
perform pg_temp.t_rows('T1 Student A can see own passport file',
  $q$select 1 from storage.objects where bucket_id = 'passports' and name = 'STUDENT-A-ID/zz_test_passport.pdf'$q$, 1);
perform pg_temp.t_rows('T2 Student A can see own results file',
  $q$select 1 from storage.objects where bucket_id = 'academic-results' and name = 'STUDENT-A-ID/2025-2026/zz_test_results.pdf'$q$, 1);
perform pg_temp.t_rows('T3 Student A can see own attestation file',
  $q$select 1 from storage.objects where bucket_id = 'attestations' and name = 'STUDENT-A-ID/zz_test_attestation.pdf'$q$, 1);
perform pg_temp.t_rows('T4 Student A can see the photo of own request chat',
  format('select 1 from storage.objects where bucket_id = %L and name = %L', 'chat-photos', current_setting('test.rq') || '/zz_test_photo.jpg'), 1);
-- Nobody can delete passports, attestations, chat photos (no delete policy).
perform pg_temp.t_noeffect('T5 Student A cannot delete own passport, attestation or chat photo',
  $q$delete from storage.objects where bucket_id in ('passports', 'attestations', 'chat-photos') and name like '%zz\_test\_%'$q$);
-- By design a student can delete own results (control: proves the delete setting works,
-- so the 0-row results of the other people below are really decided by the policies).
perform pg_temp.t_rowcount('T6 (control) Student A can delete own results file, by design',
  $q$delete from storage.objects where bucket_id = 'academic-results' and name = 'STUDENT-A-ID/2025-2026/zz_test_delete_control.pdf'$q$, 1);
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 2: Student A (the owner of the files): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 3: Student B (a stranger) ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-B-ID","role":"authenticated"}', true);
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
  $q$insert into storage.objects (bucket_id, name) values ('passports', 'STUDENT-A-ID/zz_test_b.pdf')$q$, '42501');
perform pg_temp.t_refused('T11c Student B cannot add a file into A attestation folder',
  $q$insert into storage.objects (bucket_id, name) values ('attestations', 'STUDENT-A-ID/zz_test_b.pdf')$q$, '42501');
perform pg_temp.t_refused('T11d Student B cannot add a photo into a chat they are not in',
  format('insert into storage.objects (bucket_id, name) values (%L, %L)', 'chat-photos', current_setting('test.rq') || '/zz_test_b.jpg'), '42501');
exception when others then
  perform pg_temp.t_record('FAIL', 'Section 3: Student B (a stranger): stopped by an unexpected error', sqlstate || ' ' || sqlerrm);
end $$;

-- ---------- Section 4: the Governor of A wilaya ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"GOVERNOR-ID","role":"authenticated"}', true);
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
select set_config('request.jwt.claims', '{"sub":"ATTACHE-ID","role":"authenticated"}', true);
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
  $q$insert into storage.objects (bucket_id, name) values ('passports', 'STUDENT-A-ID/zz_test_t.pdf')$q$, '42501');
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
