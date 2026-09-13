-- ============================================================================
-- 008_ai_teacher_practice_kind.sql
-- Widens ai_messages.content_kind to add AI_GENERATED_PRACTICE, used when
-- the AI Teacher generates practice material (make_quiz / similar_questions)
-- rather than explaining or answering a question. Kept distinct from
-- AI_GENERATED_ANSWER/AI_GENERATED_EXPLANATION_BASED_ON_VERIFIED so a
-- generated quiz can never be confused with either a real answer or a
-- real past-paper question in the UI (see docs/AI_TEACHER_GUIDE.md).
-- ============================================================================

alter table public.ai_messages drop constraint if exists ai_messages_content_kind_check;

alter table public.ai_messages add constraint ai_messages_content_kind_check check (
  content_kind in (
    'VERIFIED_ANSWER',
    'AI_GENERATED_EXPLANATION_BASED_ON_VERIFIED',
    'AI_GENERATED_ANSWER',
    'AI_GENERATED_PRACTICE',
    'GENERAL'
  ) or content_kind is null
);
