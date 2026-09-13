# Final QA Report

Run results as of the latest changes (**AI Teacher feature**, plus
carried-over work: question reordering + live numbering validation, PDF
export, Content Coverage screen, in-app bulk JSON import, and
`scripts/validate_content.dart`'s move onto shared validation). See
`docs/PRODUCTION_FEATURE_AUDIT.md` for feature-completeness and
`docs/PROJECT_AUDIT.md` for the architecture/security narrative. AI
Teacher specifics beyond this report live in `docs/AI_TEACHER_GUIDE.md`.

## WHAT WAS CHANGED

Implemented AI Teacher as a production-ready feature on top of the
existing Clean-ish architecture — no existing screens, models, or
repositories were rebuilt or replaced:

- A provider-agnostic backend: Flutter calls a new Supabase Edge Function
  (`ai-teacher`) via `functions.invoke`; the function calls an LLM
  provider through a small adapter (`callProvider`) so switching providers
  never touches Flutter code.
- Verified-vs-AI-generated content labeling, enforced structurally by a
  DB CHECK-constrained `content_kind` column, not just client-side text.
- Verified question/answer context is fetched through a JWT-scoped
  Supabase client so RLS (PUBLISHED-only) gates what the AI can ever see
  or use — never the service-role client.
- Per-user daily rate limiting, max prompt length, max output tokens, and
  request timeout, all configurable via the existing `app_settings` table
  without redeploying the function.
- A full chat UI (`AiTeacherScreen`) with quick actions, question-context
  mode, Urdu toggle, retry/copy/share/clear, empty/loading/error states,
  plus a conversation history screen.
- An "Ask AI Teacher about this question" entry point wired into
  `QuestionTile` (used from the Answer Key, Short Answers, Long Answers,
  and Complete Solution screens).
- A new bottom-navigation destination for AI Teacher.

## FILES CHANGED

**New:**
- `supabase/migrations/007_ai_teacher.sql`
- `supabase/functions/ai-teacher/index.ts`
- `lib/data/models/ai_message.dart`
- `lib/data/models/ai_conversation.dart`
- `lib/core/validation/ai_teacher_validation.dart`
- `lib/data/repositories/ai_teacher_repository.dart`
- `lib/features/ai_teacher/ai_teacher_context.dart`
- `lib/features/ai_teacher/ai_teacher_screen.dart`
- `lib/features/ai_teacher/ai_teacher_history_screen.dart`
- `test/unit/ai_teacher_validation_test.dart`
- `test/widget/ai_teacher_screen_test.dart`
- `docs/AI_TEACHER_GUIDE.md`

**Modified:**
- `lib/core/providers/repository_providers.dart` — registered
  `aiTeacherRepositoryProvider`.
- `lib/core/routing/app_router.dart` — added `/ai-teacher` and
  `/ai-teacher/history` routes.
- `lib/features/home/home_screen.dart` — added the AI Teacher
  bottom-navigation destination.
- `lib/shared/widgets/question_tile.dart` — added the optional `paperId`
  param and the "Ask AI Teacher" button.
- `lib/features/papers/answer_key_screen.dart`,
  `short_answers_screen.dart`, `long_answers_screen.dart`,
  `complete_solution_screen.dart` — pass `paperId` into `QuestionTile`.
- `.env.example` — documented the Edge Function secrets (`AI_PROVIDER`,
  `AI_MODEL`, `ANTHROPIC_API_KEY`) and the runtime-tunable limits.
- `docs/PRODUCTION_FEATURE_AUDIT.md` — AI Teacher moved from NOT
  IMPLEMENTED to COMPLETED, with honest caveats listed.

## DATABASE MIGRATIONS

`supabase/migrations/007_ai_teacher.sql` adds:

- `ai_conversations` (id, user_id, title, phase_id?, subject_id?,
  paper_id?, question_id?, created_at, updated_at) — owner-only RLS.
- `ai_messages` (id, conversation_id, role, content, content_kind,
  action, created_at) — `role` CHECK-constrained to `user`/`assistant`;
  `content_kind` CHECK-constrained to exactly `VERIFIED_ANSWER` /
  `AI_GENERATED_EXPLANATION_BASED_ON_VERIFIED` / `AI_GENERATED_ANSWER` /
  `GENERAL` or `null`; RLS scoped via the parent conversation's
  `user_id`.
- `ai_usage_daily` (user_id, usage_date, request_count; primary key
  `(user_id, usage_date)`) — **select-own RLS only, no insert/update
  policy for authenticated users**, so a user cannot write their own
  quota row; only the Edge Function's service-role client can.
- Seeds 4 `app_settings` rows (`ai_daily_request_limit`,
  `ai_max_prompt_chars`, `ai_max_output_tokens`,
  `ai_request_timeout_ms`) via `on conflict (key) do nothing`, so it is
  safe to run against a project that already has other `app_settings`
  rows.
- No year/academic-year column was added anywhere — consistent with the
  hard constraint in `CLAUDE.md`.

## EDGE FUNCTIONS

`supabase/functions/ai-teacher/index.ts` (new):

- Verifies the caller's Supabase auth session (`userClient.auth.getUser()`)
  before doing anything else; unauthenticated requests get a structured
  401 (`unauthorized`), never a raw stack trace.
- Validates `action` against an explicit allow-list and rejects empty or
  oversized `message` bodies (against `app_settings.ai_max_prompt_chars`).
- Enforces the per-user daily request limit before calling any provider,
  returning 429 (`rate_limited`) when exceeded.
- When `questionId` is supplied, fetches that question (and its options,
  verified answer, explanation) through the user's own JWT-scoped client
  — RLS means a non-admin only ever sees PUBLISHED-paper content, so the
  AI can never be handed draft/unverified data.
- Builds the provider prompt from: the system prompt (the 15-rule
  instruction set) + verified context (if any) + the requested action +
  language + the user's message.
- Calls the provider through `callProvider` (currently one adapter,
  `callAnthropic`, using `AbortController` for the configured timeout);
  any provider failure surfaces as a generic `provider_unavailable` error
  — no internal error text, model name, or key ever reaches the client.
- Computes `content_kind` from whether verified context was used, stores
  the user + assistant messages, best-effort increments the usage
  counter via the service-role client, and returns a structured JSON
  response (`conversationId`, `messageId`, `content`, `contentKind`,
  `disclaimer`).

## ENVIRONMENT VARIABLES REQUIRED

Set as **Supabase Edge Function secrets** (`supabase secrets set ...`),
never as Flutter `--dart-define` values — see `.env.example` and
`docs/AI_TEACHER_GUIDE.md`:

| Variable | Purpose |
|---|---|
| `AI_PROVIDER` | Selects the provider adapter (currently `anthropic`). |
| `AI_MODEL` | Model name passed to that provider. |
| `ANTHROPIC_API_KEY` | Provider API key — server-side only, never shipped in the app. |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | Standard Edge Function environment, same pattern as the existing `delete-account` function. |

Runtime-tunable (via the `app_settings` table, no redeploy needed):
`ai_daily_request_limit`, `ai_max_prompt_chars`, `ai_max_output_tokens`,
`ai_request_timeout_ms`.

No new Flutter build-time variable was added — the app never needs to
know which provider is configured.

## TEST RESULTS

### flutter analyze

```
10 issues found.
```

Same 10 pre-existing `info`-level deprecation notices as every prior
session (`RadioListTile.groupValue`/`onChanged`,
`supabase_flutter`'s `anonKey`, an unnecessary `photo_view` import) —
**zero errors, zero warnings**, including across all new AI Teacher
files.

### flutter test

```
117 tests, all passing (0 failures)
```

88 tests carried over, plus 29 new for this feature:

- `test/unit/ai_teacher_validation_test.dart` — 20 tests: content-kind
  labeling (verified-vs-AI-generated distinction, unrecognized/null
  falls back to `general` never to `VERIFIED ANSWER`), prompt validation
  (empty, oversized, exact-boundary), error-code/HTTP-status mapping
  (rate limit, provider failure, unauthorized, generic — never leaking
  provider internals into the message), and action-set integrity (unique
  db values, question-context vs general action sets).
- `test/widget/ai_teacher_screen_test.dart` — 9 tests: empty state,
  question-context mode (banner + relevant quick actions), message
  send-and-render for both a general AI answer and a verified-context
  explanation (explicitly asserting `VERIFIED ANSWER` never appears for
  an AI-generated explanation), a deterministic loading-state test using
  a `Completer`-based fake repository, failed-request + retry, empty-input
  validation, the language toggle, and navigation into `/ai-teacher`.

### scripts/validate_content.dart

```
No content files found under content. This is expected until verified
source papers are supplied — nothing to validate.
MISSING SOURCE PAPER — DO NOT PUBLISH.
```

Exit code 0. Unrelated to this feature, re-run to confirm it is still
clean before committing.

### Post-implementation scan

Grepped the new AI Teacher files (`lib/features/ai_teacher`,
`lib/data/models/ai_message.dart`, `lib/data/models/ai_conversation.dart`,
`lib/data/repositories/ai_teacher_repository.dart`,
`lib/core/validation/ai_teacher_validation.dart`,
`supabase/functions/ai-teacher`, `supabase/migrations/007_ai_teacher.sql`)
for `TODO|FIXME|stub|placeholder|not implemented|lorem ipsum|sample
question|demo paper|fake` — **zero matches**. No broken routes (both new
routes are registered in `app_router.dart` and exercised by the
navigation widget test); no fake exam content was introduced anywhere in
this feature.

### Android build

**Not attempted, per explicit instruction not to pretend.** Unchanged
from prior sessions — this sandbox has no Android SDK and a prior attempt
to install one was blocked by the egress proxy (`dl.google.com` rejected).
The AI Teacher feature adds no Android-specific configuration, so this
blocker is unrelated to and unaffected by this session's work.

## SECURITY STATUS

- `ANTHROPIC_API_KEY` and every other AI credential exist only as an Edge
  Function secret; grepped the entire diff for `sk-`, `ANTHROPIC`,
  `service_role` literals — none appear under `lib/`.
- The Flutter app never imports or references any provider SDK/type; it
  only calls `SupabaseService.client.functions.invoke('ai-teacher', ...)`.
- `SUPABASE_SERVICE_ROLE_KEY` is referenced only inside
  `supabase/functions/ai-teacher/index.ts` (server-side Deno runtime),
  and only to write `ai_usage_daily` — never to read or write
  conversations/messages, which go through the user-scoped client so RLS
  always applies.
- `ai_conversations`/`ai_messages` RLS is owner-only
  (`auth.uid() = user_id`, or via the parent conversation); no
  cross-user read/write path exists at the database layer.
- `ai_usage_daily` has no authenticated insert/update policy at all — a
  user cannot inflate or reset their own quota by calling the table
  directly, only by however many real requests they actually send.
- Verified-content retrieval for question context uses the user's own
  JWT-scoped client, so a non-admin can never cause the AI to be handed
  DRAFT/UNDER_REVIEW content — RLS filters it out before it ever reaches
  the prompt.
- Provider failures return a generic `provider_unavailable` code with no
  internal error text, model name, or key in the response body.
- **Not executed in this sandbox** (no live Supabase project, no real
  `ANTHROPIC_API_KEY`): an actual end-to-end provider call, and a live
  RLS-enforcement test (e.g. attempting cross-user conversation access
  against a real database). These are asserted from migration/function
  source review, consistent with how every other RLS claim in this
  project has been verified rather than exercised live.

## REMAINING BLOCKERS

1. **Real Phase II/III/IV source papers are still missing.** No exam
   content exists in the repository, and none was added or fabricated
   this session — every phase/subject slot remains Missing Source.
2. **Android AAB/APK build remains unverified** — this sandbox has no
   Android SDK and cannot reach `dl.google.com` to install one.
3. **Live Supabase RLS enforcement and live AI provider calls are
   untested** — this sandbox has no live Supabase project and no real
   provider API key; all security claims above are from code/migration
   review, not an executed test run.
4. **"Stop generation" is not implemented** — Dart `Future`s as used
   here aren't natively cancellable; a user can't interrupt an in-flight
   AI response.
5. **"New conversation" and "Clear chat" are one combined menu action**,
   not two separate UI affordances, in the current chat screen.
6. **`VERIFIED_ANSWER` content_kind is schema-supported but never
   currently produced** — the AI always frames its output as an
   explanation or an AI-generated answer; it never emits a bare
   "this is the verified answer, unexplained" message.

**REAL SOURCE PAPERS ARE STILL REQUIRED. NO EXAM CONTENT WAS FABRICATED.**
