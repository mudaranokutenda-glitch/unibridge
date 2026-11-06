-- E1. Sliding posters on the home screen.
-- Run AFTER file 01. Safe to run again.
--
-- WHO CAN DO WHAT
--   everyone signed in : see posters that are active and between start and end date
--   attache / admin    : see all posters; add, edit, delete posters and images
--   everyone else      : cannot add, edit or delete
-- At most 4 active at once: each active poster needs its own position 1 to 4.
-- Bucket posters is PUBLIC (images only, max 5 MB): anyone with the link can
-- see an image. Never put personal documents in it.

begin;

create table if not exists public.posters (
  id         uuid primary key default gen_random_uuid(),
  title      text not null check (char_length(title) between 1 and 120),
  image_url  text not null,
  image_path text not null,
  link_url   text check (link_url is null or link_url ~ '^https?://'),
  starts_on  date not null default current_date,
  ends_on    date not null,
  position   int  not null check (position between 1 and 4),
  active     boolean not null default true,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);

-- Two active posters cannot share a position, so at most 4 are active.
create unique index if not exists posters_one_active_per_position
  on public.posters (position) where active;

alter table public.posters enable row level security;
revoke all on public.posters from anon;

drop policy if exists "posters: select" on public.posters;
create policy "posters: select"
on public.posters for select
to authenticated
using (
  public.is_staff()
  or (active and current_date between starts_on and ends_on)
);

drop policy if exists "posters: staff insert" on public.posters;
create policy "posters: staff insert"
on public.posters for insert
to authenticated
with check (public.is_staff());

drop policy if exists "posters: staff update" on public.posters;
create policy "posters: staff update"
on public.posters for update
to authenticated
using (public.is_staff())
with check (public.is_staff());

drop policy if exists "posters: staff delete" on public.posters;
create policy "posters: staff delete"
on public.posters for delete
to authenticated
using (public.is_staff());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('posters', 'posters', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "posters files: staff upload" on storage.objects;
create policy "posters files: staff upload"
on storage.objects for insert
to authenticated
with check (bucket_id = 'posters' and public.is_staff());

drop policy if exists "posters files: staff delete" on storage.objects;
create policy "posters files: staff delete"
on storage.objects for delete
to authenticated
using (bucket_id = 'posters' and public.is_staff());

commit;
