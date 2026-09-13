-- ============================================================================
-- 009_performance_indexes_and_rpcs.sql
-- Performance hardening: indexes for the two tables that grow unboundedly
-- over time (audit_logs, questions — everything else in this schema is
-- either a fixed structural set of ~24 rows max, per CLAUDE.md's
-- phase/subject constraints, or already indexed by 005_indexes.sql) plus
-- two RPCs that replace client-side N+1/N-round-trip patterns with a
-- single server-side call. See docs/PERFORMANCE_AUDIT.md for the full
-- audit this migration comes out of.
-- ============================================================================

-- Supports keyset pagination ("...where created_at < :cursor order by
-- created_at desc") for the admin Audit Log screen, which previously
-- fetched a flat, ever-growing top-100 with no way to see older entries.
create index if not exists idx_audit_logs_created_at
  on public.audit_logs (created_at desc);

-- Same keyset pattern for the admin Review Questionable Questions screen,
-- and for ordering questions by recency generally as the question table
-- grows with real content.
create index if not exists idx_questions_created_at
  on public.questions (created_at desc);

-- ----------------------------------------------------------------------------
-- admin_dashboard_stats: replaces AdminRepository.getDashboardStats's
-- previous 5 separate queries (each pulling every matching row's full
-- columns to the client just to count them in Dart) with one round trip
-- that returns only the aggregate counts already computed by Postgres.
-- Runs as the calling user (security invoker), so the existing "admin
-- read all" RLS policies on papers/questions/profiles still gate what
-- each count actually sees — a non-admin caller gets counts scoped to
-- what they're allowed to read (i.e. published-only), never a bypass of
-- RLS to compute a "true" total. Only meaningful for admins, but never
-- unsafe for anyone else to call.
-- ----------------------------------------------------------------------------
create or replace function public.admin_dashboard_stats()
returns jsonb
language sql
security invoker
stable
set search_path = public
as $$
  select jsonb_build_object(
    'total_papers', (select count(*) from public.papers),
    'draft_papers', (select count(*) from public.papers where content_status = 'DRAFT'),
    'needs_review_papers', (select count(*) from public.papers where content_status = 'UNDER_REVIEW'),
    'verified_papers', (select count(*) from public.papers where content_status = 'VERIFIED'),
    'published_papers', (select count(*) from public.papers where content_status = 'PUBLISHED'),
    'archived_papers', (select count(*) from public.papers where content_status = 'ARCHIVED'),
    'missing_source_papers', (
      select count(*) from public.papers
      where content_status = 'DRAFT' and coalesce(source_file_url, '') = ''
    ),
    'published_by_phase_name', (
      select coalesce(jsonb_object_agg(ph.name, cnt), '{}'::jsonb)
      from (
        select p.phase_id, count(*) as cnt
        from public.papers p
        where p.content_status = 'PUBLISHED'
        group by p.phase_id
      ) x
      join public.phases ph on ph.id = x.phase_id
    ),
    'total_subjects', (select count(*) from public.subjects),
    'total_questions', (select count(*) from public.questions),
    'mcq_count', (select count(*) from public.questions where question_type = 'mcq'),
    'short_count', (select count(*) from public.questions where question_type = 'short'),
    'long_count', (select count(*) from public.questions where question_type = 'long'),
    'verified_question_count', (select count(*) from public.questions where quality_status = 'VERIFIED'),
    'questionable_count', (select count(*) from public.questions where quality_status = 'QUESTIONABLE'),
    'ocr_uncertain_count', (select count(*) from public.questions where quality_status = 'OCR_UNCERTAIN'),
    'paper_error_count', (select count(*) from public.questions where quality_status = 'PAPER_ERROR'),
    'answer_uncertain_count', (select count(*) from public.questions where quality_status = 'ANSWER_UNCERTAIN'),
    'total_users', (select count(*) from public.profiles)
  );
$$;

-- ----------------------------------------------------------------------------
-- admin_reorder_questions: replaces AdminRepository.reorderQuestions's
-- previous per-question update loop (N round trips for N questions) with
-- one atomic bulk update. Runs as the calling user (security invoker), so
-- the existing "questions: admin write" RLS policy still applies to the
-- update — a non-admin's call updates zero rows, exactly as before.
-- Row-level triggers on public.questions (invalidate_verification_on_
-- content_change, 006_admin_workflow.sql) still fire once per updated
-- row, so a reorder still correctly demotes a VERIFIED/PUBLISHED paper to
-- UNDER_REVIEW — this migration only changes how many round trips it
-- takes to get there, never what the update itself does.
-- ----------------------------------------------------------------------------
create or replace function public.admin_reorder_questions(
  p_question_ids uuid[],
  p_question_numbers integer[],
  p_display_orders integer[]
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if array_length(p_question_ids, 1) is distinct from array_length(p_question_numbers, 1)
     or array_length(p_question_ids, 1) is distinct from array_length(p_display_orders, 1) then
    raise exception 'admin_reorder_questions: id/number/order array lengths must match';
  end if;

  update public.questions q
  set question_number = u.question_number,
      display_order = u.display_order
  from unnest(p_question_ids, p_question_numbers, p_display_orders)
    as u(question_id, question_number, display_order)
  where q.id = u.question_id;
end;
$$;
