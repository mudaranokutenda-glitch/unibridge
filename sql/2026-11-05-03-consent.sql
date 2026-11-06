-- A3b. Consent before the first upload of a personal document.
-- Run AFTER 2026-11-05-01-roles.sql. Safe to run again.
--
-- One row per time a user accepts the consent text (with its version and
-- the date). Users can read only their own rows. Nobody can edit or delete
-- them from the app. They are deleted together with the account.
--
-- The upload rules for results and passports (files 04 and 05) check that
-- the user has a consent row. So the consent is enforced by the database,
-- not only by the app screen.

begin;

create table if not exists public.document_consents (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  version     text not null check (char_length(version) between 1 and 20),
  accepted_at timestamptz not null default now()
);

create index if not exists document_consents_user on public.document_consents (user_id);

alter table public.document_consents enable row level security;
revoke all on public.document_consents from anon;
revoke insert, update, delete on public.document_consents from authenticated;

drop policy if exists "consents: select own" on public.document_consents;
create policy "consents: select own"
on public.document_consents for select
to authenticated
using (user_id = auth.uid());

-- The only way to add a consent: as yourself, with today's date.
create or replace function public.give_document_consent(p_version text)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  t timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  insert into public.document_consents (user_id, version)
  values (auth.uid(), p_version)
  returning accepted_at into t;
  return t;
end;
$$;

-- Used by the storage rules: has the logged-in user given consent?
create or replace function public.has_document_consent()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.document_consents where user_id = auth.uid());
$$;

revoke execute on function public.give_document_consent(text) from public, anon;
grant execute on function public.give_document_consent(text) to authenticated;
revoke execute on function public.has_document_consent() from public;
grant execute on function public.has_document_consent() to anon, authenticated;

commit;
