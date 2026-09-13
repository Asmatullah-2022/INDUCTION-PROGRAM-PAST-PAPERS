-- ============================================================================
-- 001_initial_schema.sql
-- Induction Program Past Papers — core schema.
--
-- STRUCTURAL RULE: content is organized strictly as
--   phases -> subjects -> papers -> paper_sections -> questions -> answers
-- There is NO year / academic_year / session_year column anywhere in this
-- schema, and none must ever be added. See CLAUDE.md "No-Year Constraint".
-- ============================================================================

create extension if not exists "pgcrypto";

-- ----------------------------------------------------------------------------
-- profiles
-- One row per auth.users row. Created automatically by the
-- handle_new_user() trigger (see below) from auth signup metadata.
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null default '',
  mobile_number text,
  district text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- phases  (exactly 3 rows: Phase II, Phase III, Phase IV)
-- ----------------------------------------------------------------------------
create table if not exists public.phases (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  display_order integer not null default 0,
  is_active boolean not null default true
);

-- ----------------------------------------------------------------------------
-- subjects  (exactly 8 rows)
-- ----------------------------------------------------------------------------
create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  display_order integer not null default 0,
  is_active boolean not null default true
);

-- ----------------------------------------------------------------------------
-- papers  (up to 24 rows: 3 phases x 8 subjects). NO year column.
-- ----------------------------------------------------------------------------
create table if not exists public.papers (
  id uuid primary key default gen_random_uuid(),
  phase_id uuid not null references public.phases(id) on delete restrict,
  subject_id uuid not null references public.subjects(id) on delete restrict,
  title text not null,
  cadre text,
  total_marks integer,
  duration_minutes integer,
  source_file_url text,
  source_file_type text check (source_file_type in ('pdf', 'image') or source_file_type is null),
  content_status text not null default 'DRAFT'
    check (content_status in ('DRAFT','UNDER_REVIEW','VERIFIED','PUBLISHED','ARCHIVED')),
  verification_status text not null default 'DRAFT',
  version integer not null default 1,
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- At most one paper per (phase, subject) pair — the app's fixed 24-slot model.
  unique (phase_id, subject_id)
);

-- ----------------------------------------------------------------------------
-- paper_sections  (e.g. Section A / MCQs, Section B / Short, Section C / Long)
-- ----------------------------------------------------------------------------
create table if not exists public.paper_sections (
  id uuid primary key default gen_random_uuid(),
  paper_id uuid not null references public.papers(id) on delete cascade,
  section_name text not null,
  section_code text not null,
  marks integer,
  instructions text,
  display_order integer not null default 0
);

-- ----------------------------------------------------------------------------
-- questions
-- original_marked_option: what was ticked in the SUPPLIED paper (never
--   auto-trusted). verified_answer: the academically correct answer after
--   independent checking. verification_status flags a mismatch explicitly.
-- ----------------------------------------------------------------------------
create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  paper_section_id uuid not null references public.paper_sections(id) on delete cascade,
  question_number integer not null,
  question_type text not null check (question_type in ('mcq','short','long')),
  question_text text not null,
  marks integer,
  original_marked_option text,
  verified_answer text,
  verification_status text not null default 'VERIFIED'
    check (verification_status in ('VERIFIED','PAPER_ANSWER_ERROR')),
  explanation text,
  quality_status text not null default 'VERIFIED'
    check (quality_status in ('VERIFIED','QUESTIONABLE','PAPER_ERROR','OCR_UNCERTAIN','ANSWER_UNCERTAIN')),
  quality_note text,
  review_state text not null default 'DRAFT'
    check (review_state in ('DRAFT','OCR_EXTRACTED','AI_REVIEWED','HUMAN_REVIEWED','VERIFIED','PUBLISHED')),
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- question_options  (MCQ choices)
-- ----------------------------------------------------------------------------
create table if not exists public.question_options (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.questions(id) on delete cascade,
  option_label text not null,
  option_text text not null,
  is_verified_correct boolean not null default false,
  display_order integer not null default 0
);

-- ----------------------------------------------------------------------------
-- bookmarks
-- ----------------------------------------------------------------------------
create table if not exists public.bookmarks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null check (target_type in ('paper','mcq','short','long')),
  target_id uuid not null,
  created_at timestamptz not null default now(),
  unique (user_id, target_type, target_id)
);

-- ----------------------------------------------------------------------------
-- practice_attempts / practice_answers
-- ----------------------------------------------------------------------------
create table if not exists public.practice_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  phase_id uuid not null references public.phases(id),
  subject_id uuid not null references public.subjects(id),
  total_questions integer not null default 0,
  correct_count integer not null default 0,
  incorrect_count integer not null default 0,
  skipped_count integer not null default 0,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.practice_answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.practice_attempts(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  selected_option_label text,
  is_correct boolean not null default false,
  is_skipped boolean not null default false
);

-- ----------------------------------------------------------------------------
-- user_progress  (one row per user/phase/subject, aggregated)
-- ----------------------------------------------------------------------------
create table if not exists public.user_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  phase_id uuid not null references public.phases(id),
  subject_id uuid not null references public.subjects(id),
  attempted_count integer not null default 0,
  correct_count integer not null default 0,
  incorrect_count integer not null default 0,
  completed_papers_count integer not null default 0,
  updated_at timestamptz not null default now(),
  unique (user_id, phase_id, subject_id)
);

-- ----------------------------------------------------------------------------
-- app_settings  (simple key/value app configuration, admin-managed)
-- ----------------------------------------------------------------------------
create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- audit_logs  (content versioning / admin action trail)
-- ----------------------------------------------------------------------------
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id),
  action text not null,
  table_name text not null,
  record_id uuid,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- handle_new_user(): creates a profiles row from auth signup metadata.
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, mobile_number, district)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.email, ''),
    new.raw_user_meta_data->>'mobile_number',
    new.raw_user_meta_data->>'district'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- updated_at maintenance trigger, reused across tables.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_updated_at_papers on public.papers;
create trigger set_updated_at_papers before update on public.papers
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at_questions on public.questions;
create trigger set_updated_at_questions before update on public.questions
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at_profiles on public.profiles;
create trigger set_updated_at_profiles before update on public.profiles
  for each row execute function public.set_updated_at();
