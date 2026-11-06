-- Live updates for the Requests tab (home screen).
-- The app listens to changes in transaction_requests. This only works if
-- realtime is switched on for that table.
--
-- Step 1. Check. If this returns one row, realtime is already on: STOP, do
-- not run step 2.
select tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
  and schemaname = 'public'
  and tablename = 'transaction_requests';

-- Step 2. Only if step 1 returned no row:
alter publication supabase_realtime add table public.transaction_requests;

-- Security: this does NOT change who can see what. Realtime follows the
-- same RLS rules as a normal select, so each user only receives changes
-- to requests they are already allowed to read.
