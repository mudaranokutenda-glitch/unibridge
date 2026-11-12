-- Tests for sql/2026-11-11-13-staff-tools.sql
-- Replace STUDENT-A-ID, STUDENT-B-ID, GOVERNOR-ID, ATTACHE-ID (see README.md).
-- Nothing is saved: the file ends with rollback.

begin;

-- ---------- A student ----------
select set_config('request.jwt.claims', '{"sub":"STUDENT-B-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare n int;
begin
  begin
    perform * from public.staff_search_students('a', null);
    raise notice 'FAIL T1 a student cannot search students';
  exception when others then
    raise notice 'PASS T1 a student cannot search students';
  end;
  begin
    perform public.staff_student_details('STUDENT-A-ID');
    raise notice 'FAIL T2 a student cannot open another student''s details';
  exception when others then
    raise notice 'PASS T2 a student cannot open another student''s details';
  end;
  begin
    perform * from public.students_per_wilaya();
    raise notice 'FAIL T3 a student cannot see the dashboard';
  exception when others then
    raise notice 'PASS T3 a student cannot see the dashboard';
  end;
  begin
    insert into public.alerts (title, message) values ('Fake', 'Fake alert');
    raise notice 'FAIL T4 a student cannot create an alert';
  exception when others then
    raise notice 'PASS T4 a student cannot create an alert';
  end;
  select count(*) into n from public.access_log;
  raise notice '% T5 a student cannot read the access log', case when n = 0 then 'PASS' else 'FAIL' end;
end $$;

-- ---------- A Governor ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"GOVERNOR-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare n int; w text;
begin
  begin
    perform public.staff_student_details('STUDENT-A-ID');
    raise notice 'FAIL T6 a Governor cannot open the staff details (bank + passport number)';
  exception when others then
    raise notice 'PASS T6 a Governor cannot open the staff details (bank + passport number)';
  end;
  select count(distinct wilaya) into n from public.students_per_wilaya();
  select rep_wilaya into w from public.profiles where id = 'GOVERNOR-ID';
  raise notice '% T7 the Governor''s dashboard shows only their own wilaya',
    case when n <= 1 and not exists (select 1 from public.students_per_wilaya() x where x.wilaya <> w)
    then 'PASS' else 'FAIL' end;
end $$;

-- ---------- The Educational Attaché ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"ATTACHE-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare before_n int; after_n int; d jsonb;
begin
  begin
    perform * from public.staff_search_students('', null);
    raise notice 'FAIL T8 an empty search is refused (no full list)';
  exception when others then
    raise notice 'PASS T8 an empty search is refused (no full list)';
  end;

  select count(*) into before_n from public.access_log where kind = 'STUDENT_DETAILS_VIEWED';
  d := public.staff_student_details('STUDENT-A-ID');
  select count(*) into after_n from public.access_log where kind = 'STUDENT_DETAILS_VIEWED';
  raise notice '% T9 opening a student''s details writes one access_log row',
    case when after_n = before_n + 1 then 'PASS' else 'FAIL' end;
  raise notice '% T10 the details include the bank account and passport number keys',
    case when d ? 'bank_account' and d ? 'passport_number' then 'PASS' else 'FAIL' end;
  raise notice '% T11 the attaché sees the dashboard',
    case when (select count(*) from public.students_per_wilaya()) >= 0 then 'PASS' else 'FAIL' end;
end $$;

rollback;
