-- D2 + D3. Private bucket for the PDFs and CSV files built by the
-- staff-reports Edge Function. Run AFTER file 01. Safe to run again.
--
-- WHO CAN DO WHAT
--   nobody from the app : list, open, upload or delete (no policies at all)
--   staff-reports       : writes the file and returns a link valid 1 hour
-- Each staff member's files are in <their id>/ and older ones are removed
-- every time they build a new one.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('compiled-results', 'compiled-results', false, 52428800,
        array['application/pdf', 'text/csv'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
