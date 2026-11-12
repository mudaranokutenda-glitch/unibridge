-- Stage 5, items 22 and 23. Guide for new students, and Help (FAQ).
-- Run AFTER 2026-11-11-09. Safe to run twice. Deletes nothing.
--
-- WHO CAN DO WHAT
--   guide_sections, guide_items, faqs, bucket guide (PDF files)
--     every signed-in user : read (and open the PDFs, link valid 1 hour)
--     attache / admin      : add, change, delete
--     not signed in        : nothing
-- The guide holds general information only, never personal data.

begin;

-- ---------------------------------------------------------------
-- 1. Guide
-- ---------------------------------------------------------------
create table if not exists public.guide_sections (
  id         text primary key check (id ~ '^[A-Z_]{2,30}$'),
  title      text not null check (char_length(title) between 1 and 80),
  sort_order int  not null default 0
);

-- The four empty sections to fill in.
insert into public.guide_sections (id, title, sort_order) values
  ('POLICE', 'Police', 1),
  ('BANK', 'Bank', 2),
  ('BOURSE', 'Bourse', 3),
  ('MEDICAL', 'Medical', 4)
on conflict (id) do nothing;

create table if not exists public.guide_items (
  id         uuid primary key default gen_random_uuid(),
  section_id text not null references public.guide_sections(id) on delete cascade,
  title      text not null check (char_length(title) between 1 and 150),
  body       text not null default '' check (char_length(body) <= 10000),
  pdf_path   text check (pdf_path is null or pdf_path ~ '^[0-9a-f-]{36}\.pdf$'),
  sort_order int  not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists guide_items_section on public.guide_items (section_id, sort_order);

alter table public.guide_sections enable row level security;
alter table public.guide_items enable row level security;
revoke all on public.guide_sections, public.guide_items from anon;

drop policy if exists "guide sections: read" on public.guide_sections;
create policy "guide sections: read" on public.guide_sections
for select to authenticated using (true);
drop policy if exists "guide sections: staff write" on public.guide_sections;
create policy "guide sections: staff write" on public.guide_sections
for all to authenticated using (public.is_staff()) with check (public.is_staff());

drop policy if exists "guide items: read" on public.guide_items;
create policy "guide items: read" on public.guide_items
for select to authenticated using (true);
drop policy if exists "guide items: staff write" on public.guide_items;
create policy "guide items: staff write" on public.guide_items
for all to authenticated using (public.is_staff()) with check (public.is_staff());

drop trigger if exists guide_items_touch on public.guide_items;
create trigger guide_items_touch
before update on public.guide_items
for each row execute function public.touch_updated_at();

-- Private bucket for the guide PDFs (signed-in users only, PDF, max 10 MB).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('guide', 'guide', false, 10485760, array['application/pdf'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "guide files: read" on storage.objects;
create policy "guide files: read" on storage.objects
for select to authenticated
using (bucket_id = 'guide');

drop policy if exists "guide files: staff upload" on storage.objects;
create policy "guide files: staff upload" on storage.objects
for insert to authenticated
with check (bucket_id = 'guide' and public.is_staff()
            and array_length(storage.foldername(name), 1) is null);

drop policy if exists "guide files: staff delete" on storage.objects;
create policy "guide files: staff delete" on storage.objects
for delete to authenticated
using (bucket_id = 'guide' and public.is_staff());

-- ---------------------------------------------------------------
-- 2. Help: frequently asked questions
-- ---------------------------------------------------------------
create table if not exists public.faqs (
  id         uuid primary key default gen_random_uuid(),
  question   text not null check (char_length(question) between 1 and 300),
  answer     text not null check (char_length(answer) between 1 and 5000),
  sort_order int  not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.faqs enable row level security;
revoke all on public.faqs from anon;

drop policy if exists "faqs: read" on public.faqs;
create policy "faqs: read" on public.faqs
for select to authenticated using (true);
drop policy if exists "faqs: staff write" on public.faqs;
create policy "faqs: staff write" on public.faqs
for all to authenticated using (public.is_staff()) with check (public.is_staff());

drop trigger if exists faqs_touch on public.faqs;
create trigger faqs_touch
before update on public.faqs
for each row execute function public.touch_updated_at();

commit;
