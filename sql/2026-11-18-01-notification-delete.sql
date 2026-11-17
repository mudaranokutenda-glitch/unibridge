-- Item 3: when a person opens a notification, the app deletes it from their inbox.
-- A user may delete ONLY their own notification rows. Nothing else changes:
--   * insert: still only the database functions and triggers (no policy for the app)
--   * update: unchanged (the app marks rows as read)
--   * select: unchanged (own rows only)
-- Emergency alerts are NOT in this table (they are in the alerts table), so they stay.
--
-- Run in the Supabase SQL Editor. Safe to run twice.
-- Undo: drop policy notifications_delete_own on public.notifications;
--       revoke delete on public.notifications from authenticated;

begin;

alter table public.notifications enable row level security;

grant delete on public.notifications to authenticated;
revoke delete on public.notifications from anon;

drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own on public.notifications
  for delete to authenticated
  using (user_id = auth.uid());

commit;
