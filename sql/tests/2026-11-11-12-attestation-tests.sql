-- Tests for sql/2026-11-11-12-attestation-entry-date.sql
-- Replace STUDENT-A-ID (see README.md). Student A must have given document
-- consent and have NO attestation request in progress.
-- Nothing is saved: the file ends with rollback.

begin;

select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
begin
  begin
    insert into public.attestation_requests (user_id, passport_path)
    values ('STUDENT-A-ID', 'STUDENT-A-ID/test.pdf');
    raise notice 'FAIL T1 a request without the date of entry is refused';
  exception when others then
    raise notice 'PASS T1 a request without the date of entry is refused';
  end;

  begin
    insert into public.attestation_requests (user_id, entry_date)
    values ('STUDENT-A-ID', current_date - 100);
    raise notice 'FAIL T2 a request without the passport file is refused';
  exception when others then
    raise notice 'PASS T2 a request without the passport file is refused';
  end;

  begin
    insert into public.attestation_requests (user_id, passport_path, entry_date)
    values ('STUDENT-A-ID', 'STUDENT-A-ID/test.pdf', current_date + 30);
    raise notice 'FAIL T3 a date of entry in the future is refused';
  exception when others then
    raise notice 'PASS T3 a date of entry in the future is refused';
  end;

  begin
    insert into public.attestation_requests (user_id, passport_path, entry_date)
    values ('STUDENT-A-ID', 'STUDENT-A-ID/test.pdf', current_date - 100);
    raise notice 'PASS T4 a request with both is accepted';
  exception when others then
    raise notice 'FAIL T4 a request with both is accepted (consent given? another request open?): %', sqlerrm;
  end;
end $$;

rollback;
