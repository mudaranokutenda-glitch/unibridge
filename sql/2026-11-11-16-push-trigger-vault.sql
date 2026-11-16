-- The push trigger reads the secret from the vault instead of having it written inside.
-- Run AFTER file 03. Safe to run twice.
begin;

create or replace function public.push_on_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.call_edge_function(
    'push-notification',
    jsonb_build_object('user_id', new.user_id, 'type', new.type, 'content', new.content)
  );
  return new;
end;
$$;

revoke execute on function public.push_on_notification() from public, anon, authenticated;

drop trigger if exists notifications_push on public.notifications;
create trigger notifications_push
after insert on public.notifications
for each row execute function public.push_on_notification();

commit;