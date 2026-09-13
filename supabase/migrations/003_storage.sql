-- ============================================================================
-- 003_storage.sql
-- Storage bucket for original paper files (PDFs / image scans). Public
-- read (papers are educational content meant to be viewed once published);
-- writes restricted to admins. Original files are never modified in place —
-- publishing a corrected scan means uploading a new object and updating
-- papers.source_file_url, keeping the paper's version/audit trail meaningful.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('original-papers', 'original-papers', true)
on conflict (id) do nothing;

create policy "original-papers: public read"
  on storage.objects for select
  using (bucket_id = 'original-papers');

create policy "original-papers: admin write"
  on storage.objects for insert
  with check (bucket_id = 'original-papers' and public.is_admin());

create policy "original-papers: admin update"
  on storage.objects for update
  using (bucket_id = 'original-papers' and public.is_admin());

create policy "original-papers: admin delete"
  on storage.objects for delete
  using (bucket_id = 'original-papers' and public.is_admin());

-- Expected storage path convention (enforced by the content importer, not
-- by the database): <bucket>/phase-<2|3|4>/<subject-slug>/original.<pdf|jpg|png>
-- e.g. original-papers/phase-4/english/original.pdf
