# Final QA Report

Run results as of the latest changes (**AI Teacher completion/hardening
pass**, on top of the AI Teacher feature added in the previous session,
plus carried-over work: question reordering + live numbering validation,
PDF export, Content Coverage screen, in-app bulk JSON import, and
`scripts/validate_content.dart`'s move onto shared validation). See
`docs/PRODUCTION_FEATURE_AUDIT.md` for feature-completeness and
`docs/PROJECT_AUDIT.md` for the architecture/security narrative. AI
Teacher specifics beyond this report live in `docs/AI_TEACHER_GUIDE.md`.

## WHAT WAS CHANGED

This pass closed out the AI Teacher gaps explicitly flagged as remaining
after the previous session (see that session's own blockers list below,
items 4–6) — no existing screen, model, or repository was rebuilt:

- **Stop Generation** — a real, working Stop button using
  `CancelableOperation` (`package:async`) that abandons an in-flight
  request: stops the UI from waiting on/displaying its result and
  re-enables input. Documented honestly as *not* a true network-level
  abort (no cancellation hook exists in `supabase_flutter`'s functions
  client), rather than claimed as full cancellation.
- **New Conversation vs Clear Chat**, split into two real, separate menu
  actions: New Conversation resets the view with no confirmation and no
  deletion (history is preserved); Clear Chat asks "Clear this
  conversation?" and only deletes the conversation once confirmed.
- **Regenerate** — re-sends the last user message/action and replaces
  the previous answer, without duplicating the user's own bubble; the
  same fix also resolved a pre-existing duplicate-user-bubble bug in
  Retry.
- **Verified content priority / discrepancy detection** — a client-side
  `AiDiscrepancyDetector` compares the AI's stated MCQ answer against the
  app's own verified answer (for a question opened in MCQ context) and
  shows an explicit warning bubble on mismatch, without ever letting the
  AI touch the verified value itself.
- **AI-generated practice labeling** — `make_quiz`/`similar_questions`
  responses are now labelled `AI_GENERATED_PRACTICE` (a new,
  migration-added `content_kind` value) with a secondary "NEEDS REVIEW"
  badge, keeping generated practice questions structurally distinct from
  both real answers and real past-paper questions; they are never
  written into `questions`/`paper_sections`.
- **Markdown-lite rendering** — headings, `**bold**`, and bullet/numbered
  lists now render specially in the chat, via a small custom widget (no
  new markdown dependency).

## FILES CHANGED

**New this pass:**
- `supabase/migrations/008_ai_teacher_practice_kind.sql`

**Modified this pass:**
- `pubspec.yaml` — added `async` (direct dependency; `CancelableOperation`
  for Stop Generation — it was already a transitive dependency, now used
  directly).
- `supabase/functions/ai-teacher/index.ts` — practice-action content-kind
  routing, the `Correct Answer is LETTER.` MCQ convention, a 16th system
  prompt rule for practice generation.
- `lib/data/models/ai_message.dart` — `AiContentKind.aiGeneratedPractice`,
  `needsReviewBadge`.
- `lib/core/validation/ai_teacher_validation.dart` — `AiDiscrepancyDetector`.
- `lib/features/ai_teacher/ai_teacher_context.dart` — added
  `verifiedAnswer` (client-side only, never sent to the backend).
- `lib/features/ai_teacher/ai_teacher_screen.dart` — Stop Generation, New
  Conversation vs Clear Chat, Regenerate, discrepancy notice,
  markdown-lite rendering, NEEDS REVIEW badge.
- `lib/shared/widgets/question_tile.dart` — passes the question's verified
  answer letter into `AiTeacherContext` for MCQ questions.
- `test/unit/ai_teacher_validation_test.dart` — 11 new tests.
- `test/widget/ai_teacher_screen_test.dart` — 7 new test groups.
- `docs/AI_TEACHER_GUIDE.md`, `CLAUDE.md`, `docs/PRODUCTION_FEATURE_AUDIT.md`
  — documented all of the above, including the honest limitations.

(Files from the prior AI Teacher session — the Edge Function itself,
migration `007`, the repository, models, screens, routes, nav entry,
`.env.example` — are unchanged in kind and are not re-listed here; see
that session's own record in `docs/PRODUCTION_FEATURE_AUDIT.md` and
`docs/AI_TEACHER_GUIDE.md` for the original set.)

## DATABASE MIGRATIONS

`supabase/migrations/008_ai_teacher_practice_kind.sql` (new): widens
`ai_messages.content_kind`'s check constraint to add
`AI_GENERATED_PRACTICE` alongside the four values `007_ai_teacher.sql`
already defined. Must be applied after `007`, including in environments
that already ran `007` before this addition — it only adds an allowed
value, it does not touch existing rows.

## EDGE FUNCTIONS

`supabase/functions/ai-teacher/index.ts` (modified, not rebuilt):

- `contentKind` computation now checks the action first:
  `make_quiz`/`similar_questions` → `AI_GENERATED_PRACTICE`, regardless
  of whether verified context was present; otherwise the existing
  verified-context-based logic is unchanged.
- System prompt rule 12 now asks the model to begin an MCQ explanation
  with the exact phrase `Correct Answer is <LETTER>.` — this is the
  convention the new client-side `AiDiscrepancyDetector` parses; if this
  wording changes, the detector's regex must change with it (documented
  in `CLAUDE.md`).
- A new system prompt rule 16 tells the model to present generated
  quizzes/similar questions clearly as practice, never as real
  past-paper questions.
- The disclaimer field returned to the client now has a third variant
  for practice content.

## SECURITY CHANGES

No new attack surface was introduced:

- `AiTeacherContext.verifiedAnswer` (the app's own verified MCQ answer
  letter) is read client-side only, from data the client already legally
  has (the question is already rendered on-screen in `QuestionTile`), and
  is **never sent to the Edge Function** — the backend continues to
  derive its own verified answer independently from the database via
  RLS. This keeps the "AI never overwrites verified content" guarantee
  entirely server-side and structural; the client-side discrepancy check
  is purely a UX warning layered on top of it, not a new trust boundary.
- The widened `content_kind` check constraint only adds an allowed value;
  it does not relax any RLS policy, and `ai_usage_daily` still has no
  authenticated insert/update policy.
- No new secret, credential, or logging of prompt/response content was
  introduced by Stop Generation, Regenerate, or the discrepancy detector
  — all three operate only on data already returned to the client in a
  prior, already-authenticated response.

## AI TEACHER FEATURES

See "WHAT WAS CHANGED" above for the six features completed this pass.
Combined with the prior session's work, AI Teacher now implements every
item in `docs/PRODUCTION_FEATURE_AUDIT.md`'s "AI Teacher" section except
the honestly-disclosed gaps: no `VERIFIED_ANSWER`-kind response is ever
produced (by design — every model call is AI-generated text), no true
network-level cancellation, and no response streaming.

## TEST RESULTS

### flutter analyze

```
10 issues found.
```

Same 10 pre-existing `info`-level deprecation notices as every prior
session (`RadioListTile.groupValue`/`onChanged`, `supabase_flutter`'s
`anonKey`, an unnecessary `photo_view` import) — **zero errors, zero
warnings**, including across every AI Teacher file touched this pass.
(One transient `unintended_html_in_doc_comment` info from a doc comment
using `<LETTER>` was hit and fixed during this pass by rewording the
comment — not present in the final run.)

### flutter test

```
131 tests, all passing (0 failures)
```

117 tests carried over from the prior AI Teacher session, plus 14 new
this pass:

- `test/unit/ai_teacher_validation_test.dart` — 11 new tests: `AI_GENERATED_PRACTICE`
  gets its own distinct label never confused with a real answer;
  `needsReviewBadge` is true only for ungrounded AI content
  (answer/practice) and false for verified-grounded or raw-verified
  content; `AiDiscrepancyDetector` flags a stated-answer mismatch, does
  not flag a match, is case-insensitive, and never flags when no clear
  statement is found.
- `test/widget/ai_teacher_screen_test.dart` — 7 new tests: Stop
  Generation (cancels the pending request, shows "Generation stopped.",
  and a late response arriving afterwards is never displayed); New
  Conversation resets the view with no confirmation and no deletion;
  Clear Chat shows a confirmation dialog and only deletes on confirm;
  Regenerate replaces the previous answer without duplicating the user's
  message; a mismatched AI-stated MCQ answer triggers the discrepancy
  notice; a matching one does not; a `make_quiz` response is labelled
  `AI-GENERATED PRACTICE` with a `NEEDS REVIEW` badge.

Two real widget-test bugs were found and fixed while adding these tests
(not just test tweaks — genuine issues in the new code or the harness
interaction):
1. `_InlineBoldText` initially built a bare `RichText`, which
   `find.text()` cannot match at all (it only inspects `Text` widgets) —
   every message-rendering assertion in the whole file broke the moment
   markdown-lite rendering was wired in. Fixed by using `Text.rich(...)`
   instead, which `find.text()` does support.
2. The "Make Quiz" quick-action chip is off-screen in the horizontally
   scrolling actions row at the test viewport width (the same
   virtualization issue previously hit and worked around for "Study
   Plan") — fixed by calling `tester.ensureVisible(...)` before tapping
   it, not by changing production code.

### scripts/validate_content.dart

```
No content files found under content. This is expected until verified
source papers are supplied — nothing to validate.
MISSING SOURCE PAPER — DO NOT PUBLISH.
```

Exit code 0. Unrelated to this pass, re-run to confirm it is still clean
before committing.

### Post-implementation scan

Grepped every AI Teacher file (`lib/features/ai_teacher`,
`lib/data/models/ai_message.dart`, `lib/data/models/ai_conversation.dart`,
`lib/data/repositories/ai_teacher_repository.dart`,
`lib/core/validation/ai_teacher_validation.dart`,
`supabase/functions/ai-teacher`, both AI Teacher migrations) for
`TODO|FIXME|stub|placeholder|not implemented|lorem ipsum|sample
question|demo paper|fake` — **zero matches**. No broken routes; no fake
exam content was introduced anywhere in this pass.

### Android build

**Not attempted, per explicit instruction not to pretend.** Unchanged
from every prior session — this sandbox has no Android SDK and a prior
attempt to install one was blocked by the egress proxy (`dl.google.com`
rejected). Nothing in this pass touches Android configuration, so this
blocker is unrelated to and unaffected by this session's work.

## DEPLOYMENT STATUS

**Not deployed — no live Supabase project or provider credentials exist
in this sandbox, so deployment was not attempted and is not claimed.**
All code is finished, validated locally (`flutter analyze`/`flutter
test`/`dart run scripts/validate_content.dart`), and ready to deploy.
Exact commands (unchanged from the prior session, migration `008` added):

```bash
supabase db push   # or apply 007_ai_teacher.sql then 008_ai_teacher_practice_kind.sql in order
supabase functions deploy ai-teacher
supabase secrets set \
  AI_PROVIDER=anthropic \
  AI_MODEL=claude-sonnet-5 \
  ANTHROPIC_API_KEY=sk-ant-...
```

See `docs/AI_TEACHER_GUIDE.md` "Deployment" for the full command and the
required Supabase environment secrets.

## SECURITY STATUS

- `ANTHROPIC_API_KEY` and every other AI credential exist only as an Edge
  Function secret; grepped the entire diff for `sk-`, `ANTHROPIC`,
  `service_role` literals — none appear under `lib/`.
- `AiTeacherContext.verifiedAnswer` (new this pass) never leaves the
  client, is never sent to the Edge Function, and is only ever read from
  data already displayed on-screen — see "SECURITY CHANGES" above.
- `SUPABASE_SERVICE_ROLE_KEY` is referenced only inside
  `supabase/functions/ai-teacher/index.ts` (server-side Deno runtime),
  and only to write `ai_usage_daily`.
- `ai_conversations`/`ai_messages` RLS is owner-only; the widened
  `content_kind` constraint added this pass does not touch any RLS
  policy.
- `ai_usage_daily` still has no authenticated insert/update policy.
- Provider failures return a generic `provider_unavailable` code with no
  internal error text, model name, or key in the response body.
- **Not executed in this sandbox** (no live Supabase project, no real
  `ANTHROPIC_API_KEY`): an actual end-to-end provider call, and a live
  RLS-enforcement test. Asserted from code/migration review, consistent
  with how every other RLS claim in this project has been verified.

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
4. **Stop Generation is UI-level abandonment, not a true network abort**
   — the Edge Function/provider call already in flight still completes
   server-side and still counts against the daily rate limit; only the
   client stops waiting for/displaying it. Documented, not hidden.
5. **No response streaming** — each request returns one complete
   response; there is no token-by-token display to interrupt mid-stream.
6. **`VERIFIED_ANSWER` content_kind is schema-supported but never
   currently produced** — the AI always frames its output as an
   explanation, an answer, or practice material; it never emits a bare
   "this is the verified answer, unexplained" message.
7. **N+1 query optimization, server-side pagination, and real
   VERIFIED_ANSWER production content workflow** (items the requesting
   session flagged as the next priorities after AI Teacher) were **not**
   started this pass — this pass was scoped entirely to completing AI
   Teacher itself, per the explicit "AI Teacher completion" priority-1
   instruction.

**REAL SOURCE PAPERS ARE STILL REQUIRED. NO EXAM CONTENT WAS FABRICATED.**
