-- Tests for sql/2026-11-11-01-no-student-id-at-signup.sql and 2026-11-11-02-phone.sql
-- Replace STUDENT-A-ID, STUDENT-B-ID, GOVERNOR-ID, ATTACHE-ID (see README.md).
-- Before: Student A has saved a phone number in the app.
-- Nothing is saved: the file ends with rollback.

begin;

-- ---------- As postgres (owner) ----------
do $$
begin
  raise notice '% T0 profiles.inscription_number may be NULL',
    case when not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'profiles'
        and column_name = 'inscription_number' and is_nullable = 'NO')
    then 'PASS' else 'FAIL' end;
  raise notice '% T1 phone format: +213555123456 ok, 0555123456 refused, +33612345678 refused',
    case when public.is_valid_phone('+213555123456')
          and public.is_valid_phone('+263771234567')
          and not public.is_valid_phone('0555123456')
          and not public.is_valid_phone('+33612345678')
          and not public.is_valid_phone('+2135551')
    then 'PASS' else 'FAIL' end;
  if not exists (select 1 from public.user_phones where user_id = 'STUDENT-A-ID') then
    raise notice 'SKIP T2-T6: Student A has no phone yet (save one in the app first)';
  end if;
end $$;

-- ---------- As Student B ----------
select set_config('request.jwt.claims', '{"sub":"STUDENT-B-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare n int;
begin
  select count(*) into n from public.user_phones where user_id = 'STUDENT-A-ID';
  raise notice '% T2 Student B cannot read Student A''s phone', case when n = 0 then 'PASS' else 'FAIL' end;

  update public.user_phones set phone = '+213000000000' where user_id = 'STUDENT-A-ID';
  get diagnostics n = row_count;
  raise notice '% T3 Student B cannot change Student A''s phone', case when n = 0 then 'PASS' else 'FAIL' end;

  begin
    insert into public.user_phones (user_id, phone) values ('STUDENT-B-ID', '0555123456')
    on conflict (user_id) do update set phone = excluded.phone;
    raise notice 'FAIL T4 a wrong phone format is refused';
  exception when others then
    raise notice 'PASS T4 a wrong phone format is refused';
  end;

  begin
    insert into public.user_phones (user_id, phone) values ('STUDENT-A-ID', '+213555000000');
    raise notice 'FAIL T5 Student B cannot add a phone for Student A';
  exception when others then
    raise notice 'PASS T5 Student B cannot add a phone for Student A';
  end;
end $$;

-- ---------- As the Governor of Student A's wilaya ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"GOVERNOR-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare n int;
begin
  select count(*) into n from public.user_phones where user_id = 'STUDENT-A-ID';
  raise notice '% T6 the Governor of A''s wilaya can read A''s phone', case when n = 1 then 'PASS' else 'FAIL (or SKIP if A has no phone)' end;
  select count(*) into n from public.user_phones where user_id = 'STUDENT-B-ID';
  raise notice '% T7 the Governor cannot read Student B''s phone (other wilaya)', case when n = 0 then 'PASS' else 'FAIL' end;
end $$;

-- ---------- As the Educational Attaché ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"ATTACHE-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare n int;
begin
  select count(*) into n from public.user_phones where user_id = 'STUDENT-A-ID';
  raise notice '% T8 the Educational Attaché can read A''s phone', case when n = 1 then 'PASS' else 'FAIL (or SKIP if A has no phone)' end;
  update public.user_phones set phone = '+213000000000' where user_id = 'STUDENT-A-ID';
  get diagnostics n = row_count;
  raise notice '% T9 the Educational Attaché cannot change A''s phone', case when n = 0 then 'PASS' else 'FAIL' end;
end $$;

rollback;
