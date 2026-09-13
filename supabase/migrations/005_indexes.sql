-- ============================================================================
-- 005_indexes.sql
-- Indexes to keep browsing and search fast as content grows.
-- ============================================================================

create extension if not exists pg_trgm;

create index if not exists idx_papers_phase_id on public.papers (phase_id);
create index if not exists idx_papers_subject_id on public.papers (subject_id);
create index if not exists idx_papers_content_status on public.papers (content_status);
create index if not exists idx_papers_phase_subject_status
  on public.papers (phase_id, subject_id, content_status);

create index if not exists idx_paper_sections_paper_id on public.paper_sections (paper_id);

create index if not exists idx_questions_paper_section_id on public.questions (paper_section_id);
create index if not exists idx_questions_question_type on public.questions (question_type);
create index if not exists idx_questions_quality_status on public.questions (quality_status);

create index if not exists idx_question_options_question_id on public.question_options (question_id);

create index if not exists idx_bookmarks_user_id on public.bookmarks (user_id);
create index if not exists idx_bookmarks_user_target on public.bookmarks (user_id, target_type);

create index if not exists idx_practice_attempts_user_id on public.practice_attempts (user_id);
create index if not exists idx_practice_answers_attempt_id on public.practice_answers (attempt_id);

create index if not exists idx_user_progress_user_id on public.user_progress (user_id);

-- Full-text search support for question_text and explanation.
create index if not exists idx_questions_text_trgm
  on public.questions using gin (question_text gin_trgm_ops);
create index if not exists idx_questions_explanation_trgm
  on public.questions using gin (explanation gin_trgm_ops);
