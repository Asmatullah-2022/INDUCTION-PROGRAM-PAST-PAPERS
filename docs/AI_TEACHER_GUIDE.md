# AI Teacher Guide

AI Teacher is an educational tutor built into the app — it helps teachers,
teacher aspirants, and students understand concepts and prepare for the
Induction Program exams. **It is not an examination authority.** It never
claims that AI-generated content is an official past paper, and it never
overwrites or contradicts the app's own verified content.

## Architecture

```
Flutter app (lib/features/ai_teacher/, lib/data/repositories/ai_teacher_repository.dart)
        ↓  (user's own Supabase session — never a provider key)
Supabase Edge Function: ai-teacher  (supabase/functions/ai-teacher/index.ts)
        ↓
Provider adapter (callAnthropic, ...)  ← selected by AI_PROVIDER
        ↓
AI provider (Anthropic today)
```

The Flutter app **never** talks to an AI provider directly and **never**
holds a provider API key or the Supabase service-role key. It only calls
`SupabaseService.client.functions.invoke('ai-teacher', ...)`
(`AiTeacherRepository.sendMessage`). Everything about *which* provider is
used, and with what credentials, lives entirely in the Edge Function's
environment — see "Provider abstraction" below.

## Provider abstraction

`supabase/functions/ai-teacher/index.ts` has a `callProvider(provider, ...)`
switch that dispatches to one adapter function per provider (currently
`callAnthropic`). To add a new provider:

1. Write a new adapter function with the same signature as `callAnthropic`
   (system prompt, user prompt, model, max tokens, timeout → response text).
2. Add a `case` for it in `callProvider`.
3. Set the `AI_PROVIDER` secret to the new case's name and add whatever
   API-key secret that provider needs.

**Nothing in Flutter or the database changes** — the app only ever sees
the function's structured JSON response (`content`, `contentKind`,
`disclaimer`), never the provider's raw API shape.

## Edge Function

`supabase/functions/ai-teacher/index.ts` (Deno). Request/response contract:

**Request** (`POST`, `Authorization: Bearer <user JWT>`):
```json
{
  "action": "explain_mcq",
  "message": "Why is B correct?",
  "language": "en",
  "conversationId": "optional-existing-conversation-uuid",
  "paperId": "optional-paper-uuid",
  "questionId": "optional-question-uuid"
}
```

`action` must be one of the values in `ALLOWED_ACTIONS` in the function
(mirrored in Flutter by the `AiTeacherAction` enum in
`lib/core/validation/ai_teacher_validation.dart` — the UI can only ever
send a value the backend recognizes).

**Response** (success):
```json
{
  "conversationId": "...",
  "messageId": "...",
  "content": "...",
  "contentKind": "AI_GENERATED_EXPLANATION_BASED_ON_VERIFIED",
  "disclaimer": "This explanation is AI-generated based on the app's verified content."
}
```

**Response** (failure): `{"error": "<code>", "message": "<user-facing text>"}`
with an appropriate HTTP status. Codes: `unauthorized` (401),
`invalid_request` (400), `rate_limited` (429), `provider_unavailable`
(503/500). The Flutter side maps every one of these through
`AiTeacherErrorMapper` (`lib/core/validation/ai_teacher_validation.dart`)
to a safe, generic message — raw provider errors, stack traces, and
credentials never reach the UI.

**What the function does, step by step:**

1. Authenticates the caller via their own JWT (`userClient.auth.getUser()`).
2. Validates the request shape and message length against
   `app_settings.ai_max_prompt_chars`.
3. Checks the caller's `ai_usage_daily` row against
   `app_settings.ai_daily_request_limit`, using a **service-role client
   only for this check** — `ai_usage_daily` has no client write policy
   (see "Rate limiting" below), so a user can never inflate their own quota.
4. If `questionId` was supplied, fetches that question **with the
   caller's own JWT** — RLS means a non-admin can only ever see a question
   under a `PUBLISHED` paper, so a draft/unverified question can never
   leak through the AI backend. This verified data becomes the prompt's
   "VERIFIED CONTEXT" block (see "Source priority" below).
5. Builds the system + user prompt and calls the configured provider.
6. Persists the user message and the assistant's reply under the caller's
   own conversation (RLS: owner-only), and best-effort increments the
   daily usage counter.
7. Returns the structured response above.

## Environment variables / secrets

Set as **Supabase Edge Function secrets** (`supabase secrets set ...`),
never as Flutter `--dart-define` values and never committed — see
`.env.example` for the full list and the exact command. Summary:

| Variable | Where | Purpose |
|---|---|---|
| `AI_PROVIDER` | Edge Function secret | Selects the provider adapter (`anthropic` today) |
| `AI_MODEL` | Edge Function secret | Model name passed to the provider |
| `ANTHROPIC_API_KEY` | Edge Function secret | The provider's own API key — never in Flutter |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | Edge Function secret (auto-provided by Supabase in most deployments) | Used exactly as `delete-account` already uses them |
| `ai_daily_request_limit`, `ai_max_prompt_chars`, `ai_max_output_tokens`, `ai_request_timeout_ms` | `app_settings` table rows (seeded in `007_ai_teacher.sql`) | Tunable without redeploying the function |

## Database migration

`supabase/migrations/007_ai_teacher.sql` adds:

- `ai_conversations` — one row per conversation, owned by `user_id`.
- `ai_messages` — one row per message, with `content_kind` constrained to
  exactly the five labels the product spec requires (see "Verified vs
  AI-generated content" below).
- `ai_usage_daily` — `(user_id, usage_date)` request counter. **Deliberately
  has no insert/update RLS policy for authenticated users** — only a
  service-role client (used solely inside the Edge Function) can write it,
  and users may only `select` their own row. This is what makes the rate
  limit real rather than advisory.
- Four `app_settings` rows for the tunable limits above.

`supabase/migrations/008_ai_teacher_practice_kind.sql` widens the
`content_kind` check constraint to add `AI_GENERATED_PRACTICE` (see "Quiz
/ similar-question generation" below) — apply it after `007` in every
environment, including ones that already ran `007` before this addition.

RLS: `ai_conversations` and `ai_messages` are owner-only (`auth.uid() =
user_id`, or via the parent conversation for messages) — see "Security"
below.

## Verified vs AI-generated content (the critical accuracy rule)

Every assistant message carries a `content_kind`, rendered as a small
label above the message bubble (`_MessageBubble` in
`lib/features/ai_teacher/ai_teacher_screen.dart`) — this labelling is
never skipped, never blank for a non-error assistant message:

| `content_kind` | Label shown | Secondary badge | When |
|---|---|---|---|
| `VERIFIED_ANSWER` | **VERIFIED ANSWER** | — | Reserved for a response composed entirely of the app's own verified fields (no AI text) — not currently produced by the Edge Function, since every model call is by definition AI-generated text, but modeled for a future "just show me the verified answer, no AI" action. |
| `AI_GENERATED_EXPLANATION_BASED_ON_VERIFIED` | **AI-GENERATED EXPLANATION BASED ON VERIFIED CONTENT** | — | The Edge Function found a real question via `questionId` (RLS-gated to PUBLISHED papers) and used its verified answer/options/explanation as context. |
| `AI_GENERATED_ANSWER` | **AI-GENERATED ANSWER** | **NEEDS REVIEW** | General question, no verified question context available — ungrounded AI text. |
| `AI_GENERATED_PRACTICE` | **AI-GENERATED PRACTICE** | **NEEDS REVIEW** | `make_quiz`/`similar_questions` — newly generated practice material, never a real past-paper question (see "Quiz / similar-question generation" below). |
| `GENERAL` | AI-GENERATED (generic fallback label) | — | Reserved for future non-question-related chat kinds. |

The secondary "NEEDS REVIEW" badge (`AiContentKind.needsReviewBadge` in
`lib/data/models/ai_message.dart`) is rendered under the primary label for
any content the app has no verified grounding for — it never appears
alongside `AI-GENERATED EXPLANATION BASED ON VERIFIED CONTENT`, since that
content is already grounded in a real question.

The system prompt itself additionally instructs the model (rule 8 in
"AI system instructions" below) never to phrase its own answer as if it
were the paper's printed answer, and to say "I'm not fully certain..."
when uncertain (rule 9) — the label is the structural guarantee; the
prompt is the model's own instruction to reinforce it in wording.

### Client-side discrepancy detection

`AiDiscrepancyDetector` (`lib/core/validation/ai_teacher_validation.dart`)
is a second, independent safety net on top of the label: when a question
was opened in MCQ context and the app knows its verified answer letter
(`AiTeacherContext.verifiedAnswer`, populated from `QuestionTile` — never
sent to the Edge Function, which always re-derives the verified answer
itself from the database), the chat screen scans the AI's response for
the system prompt's `Correct Answer is LETTER.` convention (rule 12
below). If the AI states a different letter than the app's own verified
answer, a separate warning bubble is shown:

> Potential discrepancy detected. The stored answer is marked VERIFIED.
> Please refer to the source paper or administrator verification.

This is a UX safety net over text already returned to the user, not a
security control — the database and RLS are what actually prevent a
verified answer from ever being overwritten. If the AI doesn't follow the
"Correct Answer is LETTER." convention, the detector simply finds nothing
and never raises a false discrepancy.

## Source priority

When a request includes a `questionId`, the Edge Function's context is
built in this order — verified data always comes first and is never
overwritten by the AI's own generation:

1. Verified question text
2. Verified answer / verified-correct option
3. Verified explanation (if the app has one)
4. (Original paper / source metadata — available via the paper viewer,
   not currently duplicated into the AI prompt)
5. The AI's own generated explanation — always built *on top of* 1–3, in
   the `userPrompt` string's `VERIFIED CONTEXT` block, which the system
   prompt tells the model to "treat as ground truth, never contradict."

If a user asks for a specific past paper that doesn't exist in the app
(e.g. "Give me the Phase IV English paper"), the AI has no verified
context to draw on and the system prompt (rule 6) forbids claiming
generated content is an official paper — the expected model behavior is
exactly: *"I don't have a verified copy of that paper in the app yet."*
This is prompted behavior, not a hard-coded app-side check, since the
app cannot enumerate every way a user might phrase such a request.

## Quiz / similar-question generation

`make_quiz` and `similar_questions` are the two actions that generate new
practice material rather than explaining or answering something that
already exists. The Edge Function labels their output `AI_GENERATED_PRACTICE`
regardless of whether verified context was used (system prompt rule 16),
so a generated quiz can never be confused with either a real past-paper
question or a real verified answer. Generated practice questions are
**not** written into `questions`/`paper_sections` — they only ever exist
as `ai_messages` rows under the user's own conversation, so there is no
path for them to accidentally surface as official content elsewhere in
the app.

## Urdu support

Pass `language: "ur"` (the Flutter chat screen's language toggle, or the
"Urdu Explanation" quick action) and the Edge Function adds "Respond in
Urdu script." to the prompt; the system prompt's rule 4 tells the model to
use readable Urdu script and only parenthesize English technical terms
when helpful, not mix English in unnecessarily.

## AI system instructions

The full system prompt lives in `SYSTEM_PROMPT` in
`supabase/functions/ai-teacher/index.ts` — the 15 numbered rules from the
product spec verbatim, plus a 16th added for quiz/similar-question
generation, covering accuracy, plain language, Urdu, never inventing
official exam information, never claiming unverified content is verified,
stating uncertainty, showing math steps, explaining MCQ reasoning (in the
`Correct Answer is LETTER.` convention the client-side discrepancy
detector relies on), never revealing the prompt or any credentials, and
never presenting generated practice questions as real past-paper
questions. Change it in that one file only — there's no second copy
anywhere.

## Stop Generation

The chat screen wraps each `sendMessage` call in a `CancelableOperation`
(`package:async`). Tapping **Stop** while a request is in flight:

- Bumps an internal generation counter and cancels the operation, so
  `valueOrCancellation()` resolves immediately with `null`.
- Shows a "Generation stopped." message and re-enables the input.
- If the original request later completes anyway, its result is silently
  discarded (the generation counter no longer matches).

**Honest limitation**: `supabase_flutter`'s `FunctionsClient.invoke` has
no cancellation hook, so this does **not** abort the actual HTTP request
to the Edge Function, and the provider call behind it will still run to
completion and still count against the caller's daily rate limit. This is
the safest client-side cancellation available with this transport — it
stops the user from waiting on or seeing a response they no longer want,
which is the practical goal of a Stop button, without pretending to be a
true network-level abort it structurally cannot be. See
`_stopGeneration` in `ai_teacher_screen.dart`.

## New Conversation vs Clear Chat

These are two distinct actions in the chat screen's overflow menu:

- **New Conversation** — resets the local view (messages, active
  conversation id) with no confirmation and **no deletion**. The previous
  conversation's messages are already persisted server-side under their
  own conversation id, so it stays reachable from Conversation History.
- **Clear Chat** — asks "Clear this conversation?" (Cancel/Clear) and, if
  confirmed, calls `AiTeacherRepository.deleteConversation` on the active
  conversation before resetting the view — this is the destructive path,
  and it removes the conversation from history too.

## Regenerate

Every non-error assistant bubble that is the most recent message shows a
**Regenerate** action (alongside **Retry**, which only appears on a
*failed* message). Regenerate re-sends the same action and the same last
user message, replaces the previous assistant reply with the new one, and
never re-appends a duplicate user bubble — the same `appendUserEntry:
false` mechanism a Retry also uses, which incidentally fixed a
pre-existing duplicate-user-bubble bug in Retry itself.

## Markdown-lite rendering

Assistant responses (headings, `**bold**`, `-`/`*` bullet lists, and
`1.`-style numbered lists) render through a small custom
`_MarkdownLiteText`/`_InlineBoldText` widget pair in
`ai_teacher_screen.dart`, not a full markdown package — deliberately
scoped to what AI Teacher responses actually use. No tables, links, code
fences, or LaTeX-style math rendering; math is still shown as the plain
step-by-step text the system prompt asks for (rule 11).

## Rate limiting / cost control

- **Per-user daily limit** (`ai_daily_request_limit`, default 20):
  enforced server-side via `ai_usage_daily`, which normal users can only
  read, never write — see "Database migration" above. Exceeding it returns
  `rate_limited` (429), rendered as a friendly retry-later message.
- **Max prompt size** (`ai_max_prompt_chars`, default 4000): checked both
  client-side (`AiPromptValidator`, fails fast) and server-side (the
  actual gate — a client bypassing the app entirely still can't send an
  oversized prompt).
- **Max output tokens** (`ai_max_output_tokens`, default 1024): passed to
  the provider as `max_tokens`.
- **Request timeout** (`ai_request_timeout_ms`, default 30000): enforced
  via `AbortController` around the provider call.
- All four are `app_settings` rows, adjustable without a redeploy.

## Privacy

- No password, API key, or service-role key is ever stored in
  `ai_messages`/`ai_conversations` — those tables hold only the
  conversation text itself.
- `ai_conversations`/`ai_messages` are protected by RLS: a user can only
  read/write/delete their own rows (`auth.uid() = user_id`, or via the
  parent conversation for messages) — see "Security" below for how this
  is verified.
- The Edge Function logs errors to Supabase's function logs
  (`console.error`) but never logs the full prompt/response content or
  any secret.

## Security

Verified by code review of `007_ai_teacher.sql` and
`supabase/functions/ai-teacher/index.ts` (the same standard applied to
every other RLS-dependent claim in this project — see CLAUDE.md "Testing
Rules" on why a live Supabase project is needed to *execute* an RLS test,
not just read the policy):

- [x] AI credentials (`ANTHROPIC_API_KEY`) exist only as an Edge Function
      secret — grep over `lib/` finds no provider key.
- [x] Flutter contains no secret AI key — `AiTeacherRepository` only ever
      calls `functions.invoke`, passing no credential of any kind.
- [x] The Supabase service-role key is never shipped in the app — used
      only inside the Edge Function's own environment, exactly like
      `delete-account`.
- [x] The Edge Function verifies authentication before doing anything
      else (`userClient.auth.getUser()`, returns 401 otherwise).
- [x] User conversation data uses RLS (`ai_conversations`/`ai_messages`
      owner-only policies in `007_ai_teacher.sql`).
- [x] Request limits are enforced (daily count + prompt length + output
      tokens + timeout, all described above).
- [x] Unauthorized users cannot access another user's AI conversations —
      enforced by the same RLS, not by any client-side filtering (a
      Flutter query for another user's conversation ID would return zero
      rows, not an error, at the database level).

## Testing

- `test/unit/ai_teacher_validation_test.dart` — pure logic, no backend:
  content-kind labelling (verified-vs-AI-generated, never mislabeled),
  `AiPromptValidator` (empty/oversized/exact-boundary prompts),
  `AiTeacherErrorMapper` (every error code including rate-limit and
  provider-unavailable, never leaking provider internals in the mapped
  message), and the quick-action enum's label/dbValue uniqueness.
- `test/widget/ai_teacher_screen_test.dart` — the chat screen against a
  fake `AiTeacherRepository` (no network): empty state, question-context
  mode (banner + quick actions), message send + verified/AI-generated
  labelling, a deterministic loading-state test (via a `Completer` so it
  never races), error state + retry (with the retry actually re-sending
  and succeeding), empty-input validation, language toggle, navigating to
  the screen via a real `GoRouter`, Stop Generation (including that a
  late response arriving after Stop is never displayed), New Conversation
  vs Clear Chat (confirmation dialog, and that deletion only happens once
  confirmed), Regenerate (replaces the previous answer without
  duplicating the user's message), the discrepancy-detection warning
  (both a mismatched and a matching case), and `AI-GENERATED PRACTICE` +
  `NEEDS REVIEW` labelling for a `make_quiz` response.
- **Not covered by `flutter test`, and why**: true RLS enforcement
  (conversation isolation, unauthorized rejection) and end-to-end
  provider calls need a live Supabase project and a real
  `ANTHROPIC_API_KEY` — neither exists in this sandbox. This mirrors every
  other RLS claim in the project (see `CLAUDE.md` "Testing Rules") and is
  restated here rather than assumed.

## Deployment

```bash
supabase functions deploy ai-teacher
supabase secrets set \
  AI_PROVIDER=anthropic \
  AI_MODEL=claude-sonnet-5 \
  ANTHROPIC_API_KEY=sk-ant-...
# Apply 007_ai_teacher.sql and 008_ai_teacher_practice_kind.sql the same
# way as every other migration, in order — see README.md "Supabase Setup".
```

No Flutter rebuild is needed to change the provider, model, or any of the
four tunable limits — only the Edge Function secrets or the `app_settings`
rows change.

## What is NOT yet built

- A response composed purely of verified fields with no AI text at all
  (`content_kind = VERIFIED_ANSWER`) — modeled in the schema/enum for
  forward compatibility, not produced by the current Edge Function, since
  every current action calls the model.
- True server-side/network-level cancellation of an in-flight request —
  see "Stop Generation" above for exactly what the current
  client-side-only implementation does and does not do.
- Streaming responses — the Edge Function returns one complete response
  per request, not a token stream; Stop Generation therefore abandons
  waiting for the whole response, not a partial one.
- Server-side quiz/similar-question structured output beyond plain text —
  `make_quiz`/`similar_questions` are valid actions the prompt handles
  today via the system prompt's instructions, labelled
  `AI_GENERATED_PRACTICE`, but the response is unstructured text, not a
  typed quiz object the UI could render as interactive cards.
- Full markdown (tables, links, code fences, LaTeX-style math) — only
  headings, bold, and bullet/numbered lists render specially; see
  "Markdown-lite rendering" above.
- Live end-to-end verification of the discrepancy detector or Stop
  Generation against a real provider response — both are covered by
  widget tests against a fake repository, not a live Anthropic call (no
  real `ANTHROPIC_API_KEY` in this sandbox — same limitation as
  everything else in "Testing" above).
