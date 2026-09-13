-- ============================================================================
-- 007_ai_teacher.sql
-- AI Teacher: conversations, messages, per-user daily rate limiting, and
-- configurable limits in app_settings. The Flutter app never talks to an
-- AI provider directly — it only calls the `ai-teacher` Edge Function,
-- which is the only thing that reads AI_PROVIDER/AI_MODEL/the provider's
-- API key (all as Edge Function secrets, never in this database and
-- never in the Flutter app). See docs/AI_TEACHER_GUIDE.md.
-- ============================================================================

create table if not exists public.ai_conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'New Conversation',
  phase_id uuid references public.phases(id),
  subject_id uuid references public.subjects(id),
  paper_id uuid references public.papers(id),
  question_id uuid references public.questions(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ai_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.ai_conversations(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  -- content_kind is only meaningful for role = 'assistant':
  --   VERIFIED_ANSWER                              — the app's own verified data, not AI text
  --   AI_GENERATED_EXPLANATION_BASED_ON_VERIFIED    — AI text explaining verified content
  --   AI_GENERATED_ANSWER                           — AI text with no verified content behind it
  --   GENERAL                                       — general educational chat, no question context
  content_kind text check (
    content_kind in (
      'VERIFIED_ANSWER',
      'AI_GENERATED_EXPLANATION_BASED_ON_VERIFIED',
      'AI_GENERATED_ANSWER',
      'GENERAL'
    ) or content_kind is null
  ),
  action text,
  created_at timestamptz not null default now()
);

-- Per-user, per-day request counter — written only by the Edge Function's
-- service-role client (see below), never directly by a client, so a user
-- can never inflate or reset their own remaining quota.
create table if not exists public.ai_usage_daily (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null default current_date,
  request_count integer not null default 0,
  primary key (user_id, usage_date)
);

alter table public.ai_conversations enable row level security;
alter table public.ai_messages enable row level security;
alter table public.ai_usage_daily enable row level security;

create policy "ai_conversations: manage own" on public.ai_conversations
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "ai_messages: manage own via conversation" on public.ai_messages
  for all using (
    exists (
      select 1 from public.ai_conversations c
      where c.id = ai_messages.conversation_id and c.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.ai_conversations c
      where c.id = ai_messages.conversation_id and c.user_id = auth.uid()
    )
  );

-- Users may only ever READ their own usage row (e.g. to show "X requests
-- left today"); only the Edge Function's service-role client can write
-- it, since there is deliberately no insert/update policy here.
create policy "ai_usage_daily: read own" on public.ai_usage_daily
  for select using (auth.uid() = user_id);

create index if not exists idx_ai_conversations_user_id on public.ai_conversations (user_id);
create index if not exists idx_ai_messages_conversation_id on public.ai_messages (conversation_id);

drop trigger if exists set_updated_at_ai_conversations on public.ai_conversations;
create trigger set_updated_at_ai_conversations before update on public.ai_conversations
  for each row execute function public.set_updated_at();

-- Configurable AI Teacher limits — read by the Edge Function at request
-- time, so limits can be tuned from the database without redeploying the
-- function. Structure only (no exam content), safe to seed directly.
insert into public.app_settings (key, value) values
  ('ai_daily_request_limit', '20'),
  ('ai_max_prompt_chars', '4000'),
  ('ai_max_output_tokens', '1024'),
  ('ai_request_timeout_ms', '30000')
on conflict (key) do nothing;
