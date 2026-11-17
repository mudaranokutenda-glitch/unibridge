-- Item 5: a small table of app settings.
--   parallel_rate_offset : DZD added to the parallel-market (black_market) buy and sell rates
--                          when the app SHOWS them ("Indicative rate (Annaba)"). Default -2.
--                          The stored rates and the bank/official rates are never changed.
-- (Item 6 adds request_expiry_hours to this table in its own file.)
--
-- WHO CAN DO WHAT
--   every signed-in user : read all rows
--   signed out (anon)    : nothing
--   the app (students, staff, admin in the app) : cannot insert, update or delete
--   the owner            : changes a value in the SQL Editor, for example
--       update public.app_settings set value = -3, updated_at = now() where key = 'parallel_rate_offset';
--
-- Run in the Supabase SQL Editor. Safe to run twice.
-- Undo: drop table public.app_settings;

begin;

create table if not exists public.app_settings (
  key        text primary key,
  value      numeric not null,
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;

revoke all on public.app_settings from public, anon, authenticated;
grant select on public.app_settings to authenticated;

drop policy if exists app_settings_read on public.app_settings;
create policy app_settings_read on public.app_settings
  for select to authenticated
  using (true);
-- No insert, update or delete policy: the app cannot change a setting.

insert into public.app_settings (key, value)
values ('parallel_rate_offset', -2)
on conflict (key) do nothing;

commit;

select key, value from public.app_settings order by key;
