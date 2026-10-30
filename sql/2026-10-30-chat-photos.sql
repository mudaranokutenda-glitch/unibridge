-- Chat photos: a private storage bucket + who may use it.
-- Run this once in the Supabase SQL Editor. It is safe to run again.
--
-- Files are saved as  <request_id>/<file name>
-- Only the creator or the matched user of that request may upload or view.
-- Nobody may update or delete (no policies for that = not allowed).

-- 1. The bucket: private, max 5 MB, only jpeg / png / webp.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-photos',
  'chat-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- 2. Upload: only the two people in the request named by the first folder.
drop policy if exists "chat photos: participants can upload" on storage.objects;
create policy "chat photos: participants can upload"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'chat-photos'
  and exists (
    select 1
    from public.transaction_requests r
    where r.id::text = (storage.foldername(name))[1]
      and (r.creator_id = auth.uid() or r.matched_with_id = auth.uid())
  )
);

-- 3. View: same rule.
drop policy if exists "chat photos: participants can view" on storage.objects;
create policy "chat photos: participants can view"
on storage.objects for select
to authenticated
using (
  bucket_id = 'chat-photos'
  and exists (
    select 1
    from public.transaction_requests r
    where r.id::text = (storage.foldername(name))[1]
      and (r.creator_id = auth.uid() or r.matched_with_id = auth.uid())
  )
);
