-- Stage 2, items 6, 7 and 9. Chat rules enforced by the database.
-- Run AFTER 2026-11-11-03. Safe to run twice. Deletes nothing.
--
-- These are RESTRICTIVE rules: they are added ON TOP of the existing message
-- rules (both must allow it). The existing rules are not changed.
--
-- A person can send a NEW message only if:
--   * it is TEXT or IMAGE (location, documents, contacts... are refused;
--     old LOCATION messages stay and the app shows them as "[Location]"),
--   * they have not rated this transaction yet (after rating, the chat is
--     closed for them),
--   * the chat was not cleaned up (archived) after 30 days.
-- System messages written by the database functions are not affected.

begin;

alter table public.transaction_requests
  add column if not exists archived_at timestamptz;

drop policy if exists "messages: only text and photos" on public.messages;
create policy "messages: only text and photos"
on public.messages
as restrictive
for insert
to authenticated
with check (type::text in ('TEXT', 'IMAGE'));

drop policy if exists "messages: closed after my rating" on public.messages;
create policy "messages: closed after my rating"
on public.messages
as restrictive
for insert
to authenticated
with check (
  not exists (
    select 1 from public.ratings g
    where g.request_id = messages.request_id and g.rater_id = auth.uid()
  )
  and not exists (
    select 1 from public.transaction_requests r
    where r.id = messages.request_id and r.archived_at is not null
  )
);

commit;
