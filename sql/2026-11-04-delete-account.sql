-- Delete my account: what happens to a user's rows when their profile is deleted.
-- Run this once in the Supabase SQL Editor. It is safe to run again.
--
-- Before this file, deleting a user who ever made a request or sent a message
-- failed, because these foreign keys had no ON DELETE rule.
--
--   Own data  -> deleted with the user   (ON DELETE CASCADE)
--   Shared    -> kept for the other person, user becomes empty (ON DELETE SET NULL)
--   Reports about the user are kept, so nobody can wipe them by leaving.

begin;

-- ---------------------------------------------------------------
-- 1. Own data: deleted together with the profile
-- ---------------------------------------------------------------
alter table public.marketplace_listings
  drop constraint if exists marketplace_listings_seller_id_fkey,
  add constraint marketplace_listings_seller_id_fkey
    foreign key (seller_id) references public.profiles(id) on delete cascade;

alter table public.notifications
  drop constraint if exists notifications_user_id_fkey,
  add constraint notifications_user_id_fkey
    foreign key (user_id) references public.profiles(id) on delete cascade;

-- ---------------------------------------------------------------
-- 2. Shared history: kept, the deleted person becomes empty (null)
--    and the app shows "UniBridge user".
-- ---------------------------------------------------------------
alter table public.transaction_requests
  alter column creator_id drop not null,
  alter column matched_with_id drop not null,
  alter column dispute_opened_by drop not null;

alter table public.transaction_requests
  drop constraint if exists transaction_requests_creator_id_fkey,
  add constraint transaction_requests_creator_id_fkey
    foreign key (creator_id) references public.profiles(id) on delete set null,
  drop constraint if exists transaction_requests_matched_with_id_fkey,
  add constraint transaction_requests_matched_with_id_fkey
    foreign key (matched_with_id) references public.profiles(id) on delete set null,
  drop constraint if exists transaction_requests_dispute_opened_by_fkey,
  add constraint transaction_requests_dispute_opened_by_fkey
    foreign key (dispute_opened_by) references public.profiles(id) on delete set null;

alter table public.messages
  alter column sender_id drop not null;

alter table public.messages
  drop constraint if exists messages_sender_id_fkey,
  add constraint messages_sender_id_fkey
    foreign key (sender_id) references public.profiles(id) on delete set null;

alter table public.ratings
  alter column rater_id drop not null,
  alter column rated_user_id drop not null;

alter table public.ratings
  drop constraint if exists ratings_rater_id_fkey,
  add constraint ratings_rater_id_fkey
    foreign key (rater_id) references public.profiles(id) on delete set null,
  drop constraint if exists ratings_rated_user_id_fkey,
  add constraint ratings_rated_user_id_fkey
    foreign key (rated_user_id) references public.profiles(id) on delete set null;

-- ---------------------------------------------------------------
-- 3. Reports about a deleted user stay for the owner to review.
--    (Reports the deleted user made are still removed with them.)
-- ---------------------------------------------------------------
alter table public.user_reports
  alter column reported_id drop not null;

alter table public.user_reports
  drop constraint if exists user_reports_reported_id_fkey,
  add constraint user_reports_reported_id_fkey
    foreign key (reported_id) references auth.users(id) on delete set null;

commit;
