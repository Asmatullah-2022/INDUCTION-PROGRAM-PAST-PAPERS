# AI Teacher Architecture — Streaming Decision & Production Hardening

This document is the architecture/decision record for AI Teacher's
production-hardening pass. For the feature's original design (Edge
Function contract, database schema, provider abstraction, rate
limiting, testing) see `docs/AI_TEACHER_GUIDE.md` — this file only adds
what changed or was evaluated and deliberately not built in this pass.

## Current architecture (unchanged)

```
Flutter (AiTeacherScreen, AiTeacherRepository)
        |  functions.invoke('ai-teacher', ...) — awaits one full response
        v
Supabase Edge Function (ai-teacher/index.ts)
        |  one non-streaming fetch() to the provider
        v
Anthropic Messages API
```

Every request is request/response: the Flutter app sends one message,
waits, and receives one complete assistant reply. There is no
token-by-token delivery anywhere in this pipeline today.

## Response streaming — evaluated, not implemented

**Decision: do not implement streaming in this pass.** Documented here
per the explicit instruction not to fake it. Reasoning:

1. **The provider supports it.** Anthropic's Messages API accepts
   `"stream": true` and returns Server-Sent Events — this part is not
   the blocker.
2. **Supabase Edge Functions can relay a stream.** A Deno `Deno.serve`
   handler can return a `ReadableStream` response body — also not the
   blocker.
3. **The actual blocker is the Flutter side.** `AiTeacherRepository`
   talks to the Edge Function exclusively through
   `SupabaseService.client.functions.invoke(...)` — `supabase_flutter`'s
   `FunctionsClient.invoke` awaits and returns one complete
   `FunctionResponse`; it has no chunked/streaming read API. Consuming
   an SSE stream from Flutter would require bypassing `functions.invoke`
   entirely and making a raw authenticated `http.Client` request against
   the function's URL, reading the response body as a byte stream and
   parsing SSE frames by hand.
4. **That's a bigger, riskier change than this pass's budget allows to
   validate safely.** It touches the one code path this project has
   invested the most testing effort in (auth header construction,
   error-code mapping via `AiTeacherErrorMapper`, rate-limit/timeout
   handling, the Stop Generation cancellation logic added in the prior
   pass) — and it cannot be exercised end-to-end in this sandbox anyway
   (no live Supabase project, no real `ANTHROPIC_API_KEY`). Landing an
   unverified rewrite of the transport layer on the one hand while
   claiming it "works" on the other would violate this project's own
   standing rule against claiming untested things succeeded.

**What would be required to implement it properly, for whoever picks
this up with a live environment to validate against:**
- Replace `AiTeacherRepository.sendMessage`'s `functions.invoke` call
  with a raw `http.Client().send()` (or `package:http`'s streamed
  request) against
  `'$supabaseUrl/functions/v1/ai-teacher'`, forwarding the same
  `Authorization: Bearer <session token>` header `functions.invoke`
  builds today.
- Parse the SSE stream (`event:`/`data:` lines) into a `Stream<String>`
  of text deltas.
- Change `ai-teacher/index.ts` to pass `stream: true` to Anthropic and
  pipe its SSE stream through to the client instead of buffering the
  full response before returning.
- Update `AiTeacherScreen` to append incoming chunks to the current
  assistant bubble as they arrive, wire Stop Generation to actually
  close the stream (which *would* be a true abort, unlike today's
  abandonment — see below), and only persist/label the message once the
  stream completes (never save a partial chunk sequence as if it were
  the final answer).
- Re-run the full existing AI Teacher test suite against the new
  transport and add stream-specific tests (partial chunk arrival, a
  stream that errors mid-way, Stop actually closing the connection).

## Stop Generation — current behavior, unchanged this pass

Already implemented (prior session) as **client-side abandonment**, not
a true network-level abort — this is the direct consequence of §3 above:
since Flutter never holds a raw, cancellable connection to the Edge
Function (`functions.invoke` owns the whole request/response lifecycle),
there is nothing at the Flutter layer to actually close mid-flight.
`AiTeacherScreen._stopGeneration` wraps the pending call in a
`CancelableOperation`, and tapping Stop:
- Bumps a generation counter and cancels the operation, so the UI
  immediately stops waiting and shows "Generation stopped."
- Re-enables the input.
- Silently discards the eventual real response if it arrives later
  (guarded by the generation counter, so it can never overwrite a
  *newer* conversation state either — see "Duplicate/stale response
  prevention" below).

The underlying Edge Function call and the provider request behind it
are **not** aborted — they run to completion server-side and the daily
rate-limit counter still increments for that request. This was already
documented in `docs/AI_TEACHER_GUIDE.md` "Stop Generation" and remains
accurate; true cancellation is only possible with the raw-HTTP transport
described in the streaming section above (closing the underlying socket
actually does stop a stream mid-flight, which plain `functions.invoke`
cannot offer either way).

## Duplicate/stale response prevention

Already implemented (prior session), verified still correct this pass:
- Every send/regenerate call captures the notifier's generation counter
  at call time; if `_stopGeneration` (or a new send) bumps the counter
  before the in-flight call resolves, the old call's `finally` block
  detects the mismatch and skips updating `_isSending`/appending a
  result — so a stale response can never land on top of a newer
  conversation state.
- `_send`'s own re-entrancy: the loading state (`_isSending`) disables
  the send button and quick actions while a request is in flight, so a
  second tap cannot start a second concurrent request from the UI at
  all (`AiTeacherRepository.sendMessage` is never called twice
  concurrently for the same conversation from this screen).

## New Conversation vs Clear Chat

Already implemented as two separate actions (prior session) — see
`docs/AI_TEACHER_GUIDE.md` "New Conversation vs Clear Chat". Unchanged
this pass; re-verified via the existing widget tests
(`test/widget/ai_teacher_screen_test.dart`).

## Conversation history / RLS isolation

Already implemented (prior session): `ai_conversations`/`ai_messages`
are owner-only via RLS (`auth.uid() = user_id`, or via the parent
conversation for messages) — see `007_ai_teacher.sql`. No change this
pass. Live cross-user isolation testing still requires a real Supabase
project (see `docs/SECURITY_AUDIT.md` "RLS test preparation").

## VERIFIED_ANSWER: why this pass did not build an "AI-answer promotion"
## pipeline

The requesting brief for this pass asked for a lifecycle
("AI-generated → needs review → admin review → verified → published")
that would let an admin promote an AI Teacher response into a stored
`VERIFIED_ANSWER`. **This was not built, and building it as literally
specified would conflict with this project's own governing rules:**

- `CLAUDE.md` "AI Teacher Rules": *"Don't fabricate exam content through
  the AI path"* and the Edge Function's system prompt explicitly forbids
  the model from being treated as an authority on official content.
  Nothing in the AI Teacher pipeline ever writes to `questions`,
  `paper_sections`, or `question_options` — by design, not by omission.
  An "admin promotes an AI answer into the verified answer" feature
  would be the first path by which AI-authored text could end up stored
  as if it were exam content, which is exactly what every other rule in
  this project exists to prevent.
- `ai_messages.content_kind = VERIFIED_ANSWER` already exists in the
  schema, but reserved for a case where the response is composed
  **entirely of the app's own already-verified data** (no new AI
  authorship) — not for promoting AI-generated text into verified
  status. Nothing needed to change here; the value already means what
  it should.
- The *actual* verified-answer lifecycle for real exam content already
  exists, unrelated to AI Teacher: `questions.quality_status`
  (VERIFIED/QUESTIONABLE/PAPER_ERROR/OCR_UNCERTAIN/ANSWER_UNCERTAIN) +
  `questions.verification_status` (VERIFIED/PAPER_ANSWER_ERROR) +
  `papers.content_status` (DRAFT → UNDER_REVIEW → VERIFIED → PUBLISHED,
  gated server-side by `admin_transition_paper_status` — see
  `006_admin_workflow.sql`), edited through the existing Admin Question
  Form and reviewed through the existing Admin Review screen
  (`AdminReviewScreen`, now keyset-paginated — see
  `docs/PERFORMANCE_AUDIT.md`). An admin *may* use an AI Teacher
  explanation as personal reference while manually verifying/editing a
  question through that existing, unrelated screen — that already works
  today and requires no new code, because the human remains the one
  typing the verified answer into `questions.verified_answer`, exactly
  as CLAUDE.md's "Content Rules" already require.

See `docs/REMAINING_WORK_AUDIT.md` for how this is classified in the
overall production-readiness picture.
