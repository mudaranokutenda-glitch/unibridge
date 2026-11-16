-- Hardening of two existing functions. Safe to run twice. Run AFTER file 07.
begin;

alter function public.rate_transaction(uuid, integer, text) set search_path = public;

-- Same logic as before, plus: a fixed search path and a block check.
create or replace function public.match_request(p_request_id uuid)
returns transaction_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  r transaction_requests;
begin
  select * into r from transaction_requests where id = p_request_id for update;
  if r is null then
    raise exception 'Request not found';
  end if;
  if r.status != 'OPEN' then
    raise exception 'Request is no longer open';
  end if;
  if r.creator_id = auth.uid() then
    raise exception 'Cannot match your own request';
  end if;
  if exists (
    select 1 from user_blocks b
    where (b.blocker_id = r.creator_id and b.blocked_id = auth.uid())
       or (b.blocker_id = auth.uid() and b.blocked_id = r.creator_id)) then
    raise exception 'You cannot match with this user.';
  end if;

  update transaction_requests
    set status = 'MATCHED', matched_with_id = auth.uid(), updated_at = now()
    where id = p_request_id
    returning * into r;

  insert into notifications (user_id, type, content)
    values (r.creator_id, 'MATCH_FOUND', 'Someone matched with your request. Chat is now open.');

  return r;
end;
$$;

commit;