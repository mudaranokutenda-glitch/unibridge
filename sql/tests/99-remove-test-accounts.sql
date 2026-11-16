-- Removes the test accounts table (and with it the four tester emails).
-- RUN THIS BEFORE LAUNCH. Safe to run twice. Run it in the Supabase SQL Editor.
--
-- It drops only the schema test_support. No user data, table or file of the app is touched.
-- After this, every test file stops at "run 00-test-accounts.sql first" until you run 00 again.

begin;

drop schema if exists test_support cascade;

commit;

select 'test_support removed' as result,
       to_regclass('test_support.accounts') is null as gone;
