-- ============================================================================
-- 004_seed_structure.sql
-- Seeds ONLY the fixed structural rows: 3 phases and 8 subjects. This is
-- structure, not exam content, so it is safe to seed directly (unlike
-- papers/questions, which must come from the verified content importer —
-- see scripts/import_content.dart and CLAUDE.md "No Fake Data").
--
-- Do NOT add papers, paper_sections, questions, or question_options here.
-- ============================================================================

insert into public.phases (name, slug, display_order, is_active) values
  ('Phase II', 'phase-2', 1, true),
  ('Phase III', 'phase-3', 2, true),
  ('Phase IV', 'phase-4', 3, true)
on conflict (slug) do nothing;

insert into public.subjects (name, slug, display_order, is_active) values
  ('English', 'english', 1, true),
  ('Mathematics', 'mathematics', 2, true),
  ('General Science', 'general-science', 3, true),
  ('Islamiat / Nazra Quran', 'islamiat-nazra-quran', 4, true),
  ('Use of ICT in Education', 'ict-in-education', 5, true),
  ('Classroom Management and Assessment', 'classroom-management-assessment', 6, true),
  ('Educational Psychology', 'educational-psychology', 7, true),
  ('Curriculum and Instruction', 'curriculum-and-instruction', 8, true)
on conflict (slug) do nothing;
