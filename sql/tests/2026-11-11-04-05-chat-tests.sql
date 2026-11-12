-- Tests for sql/2026-11-11-03-cron-secret.sql, 04-chat-rules.sql and 05-chat-cleanup.sql
-- Replace STUDENT-A-ID and STUDENT-B-ID (see README.md).
-- Before: Student A and Student B have one MATCHED request together (any amount).
-- Nothing is saved: the file ends with rollback.

begin;

do $$
declare n int;
begin
  raise notice '% T1 the secret is stored in the Vault',
    case when exists (select 1 from vault.secrets where name = 'cron_secret') then 'PASS' else 'FAIL' end;
  raise notice '% T2 the nightly chat-cleanup job exists',
    case when exists (select 1 from cron.job where jobname = 'chat-cleanup') then 'PASS' else 'FAIL' end;
  raise notice '% T3 a DISPUTED request is never marked as ended',
    case when not exists (select 1 from public.transaction_requests
                          where status::text = 'DISPUTED' and ended_at is not null)
    then 'PASS' else 'FAIL' end;
end $$;

-- App users cannot read the secret.
select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare v text; rid uuid;
begin
  begin
    v := public.cron_secret();
    raise notice 'FAIL T4 a student cannot read the secret';
  exception when others then
    raise notice 'PASS T4 a student cannot read the secret';
  end;

  begin
    perform public.call_edge_function('chat-cleanup', '{}'::jsonb);
    raise notice 'FAIL T5 a student cannot start the clean-up';
  exception when others then
    raise notice 'PASS T5 a student cannot start the clean-up';
  end;

  select id into rid from public.transaction_requests
  where status::text = 'MATCHED'
    and ((creator_id = 'STUDENT-A-ID' and matched_with_id = 'STUDENT-B-ID')
      or (creator_id = 'STUDENT-B-ID' and matched_with_id = 'STUDENT-A-ID'))
  limit 1;

  if rid is null then
    raise notice 'SKIP T6-T7: no MATCHED request between A and B';
    return;
  end if;

  begin
    insert into public.messages (request_id, sender_id, type, content, attachment_url)
    values (rid, 'STUDENT-A-ID', 'LOCATION', 'test', 'https://maps.google.com');
    raise notice 'FAIL T6 a LOCATION message is refused';
  exception when others then
    raise notice 'PASS T6 a LOCATION message is refused';
  end;

  begin
    insert into public.messages (request_id, sender_id, type, content)
    values (rid, 'STUDENT-A-ID', 'TEXT', 'test message (rolled back)');
    raise notice 'PASS T7 a TEXT message is still allowed';
  exception when others then
    raise notice 'FAIL T7 a TEXT message is still allowed: %', sqlerrm;
  end;
end $$;

rollback;

-- T8 (by hand, in the app): after you rate a COMPLETED request, the chat shows
-- "This chat is closed." and there is no text box.
