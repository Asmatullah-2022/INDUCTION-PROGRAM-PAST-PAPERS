-- ============================================================================
-- 006_admin_workflow.sql
-- Server-side admin verification workflow: adds verification metadata to
-- papers, a critical-error quality gate, a status-transition RPC that
-- enforces the state machine and the quality gate (never rely on the
-- Flutter UI alone — see CLAUDE.md "Security Rules"), and a trigger that
-- automatically demotes a paper out of VERIFIED/PUBLISHED whenever its
-- sections or questions change after verification, so a modified question
-- can never keep sitting under a stale VERIFIED/PUBLISHED paper.
--
-- Status vocabulary stays the one already defined in 001_initial_schema.sql
-- (DRAFT, UNDER_REVIEW, VERIFIED, PUBLISHED, ARCHIVED) — UNDER_REVIEW is
-- displayed to admins as "Needs Review". MISSING_SOURCE is NOT a stored
-- status: it is derived (content_status = 'DRAFT' and source_file_url is
-- null) and rendered as a badge — see PaperStatusPresentation in the app.
-- ============================================================================

alter table public.papers
  add column if not exists verified_by uuid references auth.users(id),
  add column if not exists verified_at timestamptz,
  add column if not exists verification_notes text;

-- ----------------------------------------------------------------------------
-- paper_has_critical_errors: the authoritative, server-side quality gate.
-- Mirrors (a subset of) lib/core/validation/paper_quality.dart so the same
-- rules are enforced even if a client bypasses the Flutter UI entirely.
-- ----------------------------------------------------------------------------
create or replace function public.paper_has_critical_errors(p_paper_id uuid)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_source_file_url text;
  v_section_count integer;
  v_empty_section_count integer;
  v_bad_question_count integer;
  v_duplicate_number_count integer;
begin
  select source_file_url into v_source_file_url from public.papers where id = p_paper_id;
  if v_source_file_url is null then
    return true; -- MISSING SOURCE PAPER — DO NOT PUBLISH
  end if;

  select count(*) into v_section_count from public.paper_sections where paper_id = p_paper_id;
  if v_section_count = 0 then
    return true;
  end if;

  select count(*) into v_empty_section_count
  from public.paper_sections ps
  where ps.paper_id = p_paper_id
    and not exists (select 1 from public.questions q where q.paper_section_id = ps.id);
  if v_empty_section_count > 0 then
    return true;
  end if;

  select count(*) into v_bad_question_count
  from public.questions q
  join public.paper_sections ps on ps.id = q.paper_section_id
  where ps.paper_id = p_paper_id
    and (
      coalesce(trim(q.question_text), '') = ''
      or (
        q.question_type in ('short', 'long')
        and coalesce(trim(q.verified_answer), '') = ''
      )
      or (
        q.question_type = 'mcq'
        and (
          (select count(*) from public.question_options qo where qo.question_id = q.id) < 2
          or (select count(*) from public.question_options qo
              where qo.question_id = q.id and qo.is_verified_correct) <> 1
        )
      )
    );
  if v_bad_question_count > 0 then
    return true;
  end if;

  select count(*) into v_duplicate_number_count
  from (
    select q.paper_section_id, q.question_number, count(*) as c
    from public.questions q
    join public.paper_sections ps on ps.id = q.paper_section_id
    where ps.paper_id = p_paper_id
    group by q.paper_section_id, q.question_number
    having count(*) > 1
  ) dup;
  if v_duplicate_number_count > 0 then
    return true;
  end if;

  return false;
end;
$$;

-- ----------------------------------------------------------------------------
-- admin_transition_paper_status: the only sanctioned way to change a
-- paper's content_status. Runs as the calling user (not security definer)
-- so the existing "papers: admin write" RLS policy still applies to the
-- UPDATE below — a non-admin's call simply updates zero rows.
-- ----------------------------------------------------------------------------
create or replace function public.admin_transition_paper_status(
  p_paper_id uuid,
  p_new_status text,
  p_notes text default null
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_current_status text;
begin
  select content_status into v_current_status from public.papers where id = p_paper_id;
  if v_current_status is null then
    raise exception 'Paper % not found', p_paper_id;
  end if;

  if p_new_status not in ('DRAFT','UNDER_REVIEW','VERIFIED','PUBLISHED','ARCHIVED') then
    raise exception 'Invalid status: %', p_new_status;
  end if;

  -- Allowed transitions (spec section 3 "Paper Cross-Check System" +
  -- CLAUDE.md verification workflow):
  --   DRAFT        -> UNDER_REVIEW, ARCHIVED
  --   UNDER_REVIEW -> DRAFT, VERIFIED, ARCHIVED
  --   VERIFIED     -> UNDER_REVIEW, PUBLISHED, ARCHIVED
  --   PUBLISHED    -> VERIFIED (unpublish), ARCHIVED
  --   ARCHIVED     -> DRAFT (restore)
  if not (
    (v_current_status = 'DRAFT' and p_new_status in ('UNDER_REVIEW', 'ARCHIVED'))
    or (v_current_status = 'UNDER_REVIEW' and p_new_status in ('DRAFT', 'VERIFIED', 'ARCHIVED'))
    or (v_current_status = 'VERIFIED' and p_new_status in ('UNDER_REVIEW', 'PUBLISHED', 'ARCHIVED'))
    or (v_current_status = 'PUBLISHED' and p_new_status in ('VERIFIED', 'ARCHIVED'))
    or (v_current_status = 'ARCHIVED' and p_new_status = 'DRAFT')
    or v_current_status = p_new_status
  ) then
    raise exception 'Cannot move a paper from % to %', v_current_status, p_new_status;
  end if;

  if p_new_status in ('VERIFIED', 'PUBLISHED') and public.paper_has_critical_errors(p_paper_id) then
    raise exception
      'Cannot move to % — this paper has unresolved critical quality errors (missing source, empty sections, incomplete MCQs, or duplicate question numbers).',
      p_new_status;
  end if;

  if p_new_status = 'VERIFIED' then
    update public.papers
    set content_status = 'VERIFIED',
        verification_status = 'VERIFIED',
        verified_by = auth.uid(),
        verified_at = now(),
        verification_notes = p_notes
    where id = p_paper_id;
  elsif v_current_status = 'VERIFIED' and p_new_status <> 'VERIFIED' then
    -- Leaving VERIFIED any other way than being re-verified clears the
    -- verification record — it no longer reflects the paper's current state.
    update public.papers
    set content_status = p_new_status,
        verification_status = p_new_status,
        verified_by = null,
        verified_at = null,
        verification_notes = p_notes
    where id = p_paper_id;
  else
    update public.papers
    set content_status = p_new_status,
        verification_status = p_new_status,
        verification_notes = coalesce(p_notes, verification_notes)
    where id = p_paper_id;
  end if;

  insert into public.audit_logs (actor_id, action, table_name, record_id, before_data, after_data)
  values (
    auth.uid(),
    'STATUS_TRANSITION',
    'papers',
    p_paper_id,
    jsonb_build_object('content_status', v_current_status),
    jsonb_build_object('content_status', p_new_status, 'notes', p_notes)
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- invalidate_verification_on_content_change: a modified VERIFIED/PUBLISHED
-- paper must never keep claiming to be verified. Runs as security definer
-- because it writes to papers/audit_logs as a side effect of a write the
-- triggering user was already permitted to make on paper_sections/questions.
-- ----------------------------------------------------------------------------
create or replace function public.invalidate_verification_on_content_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paper_id uuid;
  v_current_status text;
begin
  if tg_table_name = 'paper_sections' then
    v_paper_id := coalesce(new.paper_id, old.paper_id);
  else
    -- questions: resolve paper_id via its section, using OLD when the row
    -- was deleted (NEW is null on DELETE).
    select ps.paper_id into v_paper_id
    from public.paper_sections ps
    where ps.id = coalesce(new.paper_section_id, old.paper_section_id);
  end if;

  if v_paper_id is null then
    return coalesce(new, old);
  end if;

  select content_status into v_current_status from public.papers where id = v_paper_id;

  if v_current_status in ('VERIFIED', 'PUBLISHED') then
    update public.papers
    set content_status = 'UNDER_REVIEW',
        verification_status = 'UNDER_REVIEW',
        verified_by = null,
        verified_at = null,
        verification_notes = 'Automatically moved to Needs Review: content changed after verification.'
    where id = v_paper_id;

    insert into public.audit_logs (actor_id, action, table_name, record_id, before_data, after_data)
    values (
      auth.uid(),
      'AUTO_INVALIDATE_VERIFICATION',
      'papers',
      v_paper_id,
      jsonb_build_object('content_status', v_current_status),
      jsonb_build_object('content_status', 'UNDER_REVIEW')
    );
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists invalidate_verification_on_section_change on public.paper_sections;
create trigger invalidate_verification_on_section_change
  after insert or update or delete on public.paper_sections
  for each row execute function public.invalidate_verification_on_content_change();

drop trigger if exists invalidate_verification_on_question_change on public.questions;
create trigger invalidate_verification_on_question_change
  after insert or update or delete on public.questions
  for each row execute function public.invalidate_verification_on_content_change();
