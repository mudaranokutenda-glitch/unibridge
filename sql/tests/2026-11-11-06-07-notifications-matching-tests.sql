-- Tests for sql/2026-11-11-06-new-request-push.sql and 07-match-suggestions.sql
-- Replace STUDENT-A-ID and STUDENT-B-ID (see README.md). A and B must NOT
-- have blocked each other.
-- The test creates two requests (A sends 777 USD, B receives 777 USD), checks
-- the suggestion, accepts it as both, and checks the match.
-- Nothing is saved: the file ends with rollback.
-- (The push calls happen in the background and are also rolled back.)

begin;

-- ---------- Student A ----------
select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare n int;
begin
  insert into public.notification_settings (user_id, new_requests) values ('STUDENT-A-ID', false)
  on conflict (user_id) do update set new_requests = false;
  raise notice 'PASS T1 Student A can switch off new request notifications';

  update public.notification_settings set new_requests = true where user_id = 'STUDENT-B-ID';
  get diagnostics n = row_count;
  raise notice '% T2 Student A cannot change Student B''s settings', case when n = 0 then 'PASS' else 'FAIL' end;

  begin
    insert into public.match_suggestions (request_a, request_b, user_a, user_b)
    select r1.id, r2.id, 'STUDENT-A-ID', 'STUDENT-B-ID'
    from public.transaction_requests r1, public.transaction_requests r2 limit 1;
    raise notice 'FAIL T3 nobody can create a suggestion by hand';
  exception when others then
    raise notice 'PASS T3 nobody can create a suggestion by hand';
  end;

  insert into public.transaction_requests (type, amount, currency, creator_id)
  values ('SEND', 777, 'USD', 'STUDENT-A-ID');
end $$;

-- ---------- Student B posts the opposite request ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-B-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare n int; sid uuid; matched uuid;
begin
  insert into public.transaction_requests (type, amount, currency, creator_id)
  values ('RECEIVE', 777, 'USD', 'STUDENT-B-ID');

  select id into sid from public.my_match_suggestions() where amount = 777 limit 1;
  raise notice '% T4 a suggestion was created for the same amount and currency, opposite type',
    case when sid is not null then 'PASS' else 'FAIL (does A already have another open 777 USD request?)' end;
  if sid is null then return; end if;

  matched := public.respond_match_suggestion(sid, true);
  raise notice '% T5 one acceptance is not enough to match', case when matched is null then 'PASS' else 'FAIL' end;
  perform set_config('test.sid', sid::text, true);
end $$;

-- ---------- Another user cannot answer ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"ATTACHE-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare n int;
begin
  begin
    perform public.respond_match_suggestion(current_setting('test.sid', true)::uuid, true);
    raise notice 'FAIL T6 a third person cannot answer the suggestion';
  exception when others then
    raise notice 'PASS T6 a third person cannot answer the suggestion';
  end;
  select count(*) into n from public.match_suggestions where id = current_setting('test.sid', true)::uuid;
  raise notice '% T7 a third person cannot see the suggestion', case when n = 0 then 'PASS' else 'FAIL' end;
end $$;

-- ---------- Student A accepts: now it matches ----------
reset role;
select set_config('request.jwt.claims', '{"sub":"STUDENT-A-ID","role":"authenticated"}', true);
set local role authenticated;

do $$
declare matched uuid; st text; other uuid;
begin
  if current_setting('test.sid', true) is null or current_setting('test.sid', true) = '' then
    raise notice 'SKIP T8-T9 (no suggestion)';
    return;
  end if;
  matched := public.respond_match_suggestion(current_setting('test.sid', true)::uuid, true);
  select status::text, matched_with_id into st, other from public.transaction_requests where id = matched;
  raise notice '% T8 both accepted: the request is MATCHED with Student B',
    case when st = 'MATCHED' and other = 'STUDENT-B-ID' then 'PASS' else 'FAIL' end;
  begin
    perform public.respond_match_suggestion(current_setting('test.sid', true)::uuid, false);
    raise notice 'FAIL T9 a matched suggestion cannot be answered again';
  exception when others then
    raise notice 'PASS T9 a matched suggestion cannot be answered again';
  end;
end $$;

rollback;
