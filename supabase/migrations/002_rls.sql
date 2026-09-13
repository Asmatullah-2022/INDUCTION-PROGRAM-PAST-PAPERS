-- ============================================================================
-- 002_rls.sql
-- Row Level Security. Normal users may read published content and manage
-- only their own bookmarks/progress/practice attempts/profile. Only
-- profiles.is_admin = true may write official content tables.
-- ============================================================================

alter table public.profiles enable row level security;
alter table public.phases enable row level security;
alter table public.subjects enable row level security;
alter table public.papers enable row level security;
alter table public.paper_sections enable row level security;
alter table public.questions enable row level security;
alter table public.question_options enable row level security;
alter table public.bookmarks enable row level security;
alter table public.practice_attempts enable row level security;
alter table public.practice_answers enable row level security;
alter table public.user_progress enable row level security;
alter table public.app_settings enable row level security;
alter table public.audit_logs enable row level security;

-- Helper: is the current JWT's user an admin?
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce(
    (select is_admin from public.profiles where id = auth.uid()),
    false
  );
$$;

-- ---------------------------------------------------------------- profiles
create policy "profiles: read own" on public.profiles
  for select using (auth.uid() = id);

-- Users may update their own row, but is_admin escalation is blocked by the
-- prevent_self_admin_escalation trigger below (RLS with_check alone cannot
-- compare against the pre-update value of the same row).
create policy "profiles: update own" on public.profiles
  for update using (auth.uid() = id)
  with check (auth.uid() = id);

create policy "profiles: admin read all" on public.profiles
  for select using (public.is_admin());

create or replace function public.prevent_self_admin_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_admin is distinct from old.is_admin and not public.is_admin() then
    new.is_admin := old.is_admin;
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_self_admin_escalation on public.profiles;
create trigger prevent_self_admin_escalation
  before update on public.profiles
  for each row execute function public.prevent_self_admin_escalation();

-- ------------------------------------------------------------------ phases
create policy "phases: public read active" on public.phases
  for select using (is_active = true);

create policy "phases: admin write" on public.phases
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- subjects
create policy "subjects: public read active" on public.subjects
  for select using (is_active = true);

create policy "subjects: admin write" on public.subjects
  for all using (public.is_admin()) with check (public.is_admin());

-- ------------------------------------------------------------------ papers
-- Normal users may only ever see PUBLISHED papers. Admins see and manage all.
create policy "papers: public read published" on public.papers
  for select using (content_status = 'PUBLISHED');

create policy "papers: admin read all" on public.papers
  for select using (public.is_admin());

create policy "papers: admin write" on public.papers
  for all using (public.is_admin()) with check (public.is_admin());

-- ------------------------------------------------------------ paper_sections
create policy "paper_sections: public read for published papers" on public.paper_sections
  for select using (
    exists (
      select 1 from public.papers p
      where p.id = paper_sections.paper_id and p.content_status = 'PUBLISHED'
    )
  );

create policy "paper_sections: admin read all" on public.paper_sections
  for select using (public.is_admin());

create policy "paper_sections: admin write" on public.paper_sections
  for all using (public.is_admin()) with check (public.is_admin());

-- ------------------------------------------------------------------ questions
create policy "questions: public read for published papers" on public.questions
  for select using (
    exists (
      select 1 from public.paper_sections ps
      join public.papers p on p.id = ps.paper_id
      where ps.id = questions.paper_section_id and p.content_status = 'PUBLISHED'
    )
  );

create policy "questions: admin read all" on public.questions
  for select using (public.is_admin());

create policy "questions: admin write" on public.questions
  for all using (public.is_admin()) with check (public.is_admin());

-- ------------------------------------------------------------ question_options
create policy "question_options: public read for published papers" on public.question_options
  for select using (
    exists (
      select 1 from public.questions q
      join public.paper_sections ps on ps.id = q.paper_section_id
      join public.papers p on p.id = ps.paper_id
      where q.id = question_options.question_id and p.content_status = 'PUBLISHED'
    )
  );

create policy "question_options: admin read all" on public.question_options
  for select using (public.is_admin());

create policy "question_options: admin write" on public.question_options
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- bookmarks
create policy "bookmarks: manage own" on public.bookmarks
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------- practice_attempts
create policy "practice_attempts: manage own" on public.practice_attempts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ----------------------------------------------------------- practice_answers
create policy "practice_answers: manage own via attempt" on public.practice_answers
  for all using (
    exists (
      select 1 from public.practice_attempts a
      where a.id = practice_answers.attempt_id and a.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.practice_attempts a
      where a.id = practice_answers.attempt_id and a.user_id = auth.uid()
    )
  );

-- ------------------------------------------------------------- user_progress
create policy "user_progress: manage own" on public.user_progress
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- -------------------------------------------------------------- app_settings
create policy "app_settings: public read" on public.app_settings
  for select using (true);

create policy "app_settings: admin write" on public.app_settings
  for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- audit_logs
create policy "audit_logs: admin read" on public.audit_logs
  for select using (public.is_admin());

create policy "audit_logs: admin insert" on public.audit_logs
  for insert with check (public.is_admin());
