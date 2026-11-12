-- Tests for sql/2026-11-11-14-governor-tools.sql
-- Replace STUDENT-A-ID, STUDENT-B-ID, GOVERNOR-ID (see README.md).
-- Student A has a student record in the Governor's wilaya; Student B in another.
-- Nothing is saved: the file ends with rollback.

begin;

-- ---------- A student ----------
select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  begin
    perform * from public.rep_bank_accounts();
    raise notice 'FAIL T1 a student cannot open the bank account list';
  exception when others then
    raise notice 'PASS T1 a student cannot open the bank account list';
  end;
  begin
    perform * from public.rep_results_tracker('2025-2026', 'S1');
    raise notice 'FAIL T2 a student cannot open the results tracker';
  exception when others then
    raise notice 'PASS T2 a student cannot open the results tracker';
  end;
  begin
    perform * from public.rep_students_without_record();
    raise notice 'FAIL T3 a student cannot open the list without a record';
  exception when others then
    raise notice 'PASS T3 a student cannot open the list without a record';
  end;
end $$;

-- ---------- The Governor ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"GOVERNOR-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare before_n int; after_n int; n int;
begin
  select count(*) into before_n from public.access_log;  -- 0 for a Governor (cannot read it)
  perform * from public.rep_bank_accounts();
  raise notice 'PASS T4 the Governor can open the bank account list of their wilaya';

  select count(*) into n from public.rep_bank_accounts() where user_id = 'STUDENT-B-ID';
  raise notice '% T5 the list never contains Student B (other wilaya)', case when n = 0 then 'PASS' else 'FAIL' end;
  select count(*) into n from public.rep_results_tracker('2025-2026', 'S1') where user_id = 'STUDENT-B-ID';
  raise notice '% T6 the results tracker never contains Student B', case when n = 0 then 'PASS' else 'FAIL' end;
  select count(*) into n from public.rep_students_without_record() where user_id = 'STUDENT-B-ID';
  raise notice '% T7 the list without a record never contains Student B', case when n = 0 then 'PASS' else 'FAIL' end;
  select count(*) into n from public.passport_numbers;
  raise notice '% T8 the Governor can never read passport numbers', case when n = 0 then 'PASS' else 'FAIL' end;
  select count(*) into n from public.attestation_requests;
  raise notice '% T9 the Governor can never read attestation requests (passports)', case when n = 0 then 'PASS' else 'FAIL' end;
end $$;

-- Back as the owner: the bank list views were logged.
reset role;
do $$
declare n int;
begin
  select count(*) into n from public.access_log
  where actor_id = 'GOVERNOR-ID' and kind = 'BANK_LIST_VIEWED' and created_at > now() - interval '1 minute';
  raise notice '% T10 each opening of the bank account list wrote an access_log row', case when n >= 2 then 'PASS' else 'FAIL' end;
end $$;

rollback;
