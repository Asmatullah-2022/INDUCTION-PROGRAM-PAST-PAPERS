# Production Feature Audit

A section-by-section pass over the entire codebase to classify every
feature area. Classifications:

- **COMPLETED** — built, wired into the app, `flutter analyze`/`flutter
  test` cover what's testable without a live backend or real content.
- **PARTIALLY COMPLETED** — a real, working implementation exists but is
  narrower than the full spec, with the gap noted.
- **NOT IMPLEMENTED** — no code for this exists in the repository. Stated
  plainly rather than implied by omission.
- **BLOCKED BY MISSING SOURCE PAPERS** — the code is ready; there is
  simply no real exam content to exercise it with, and none was
  fabricated to fill the gap.
- **BLOCKED BY ENVIRONMENT** — the sandbox this was built in cannot
  perform the step (no Android SDK, egress policy blocks the SDK
  download); the code itself has no known blocker.

This file reflects the codebase through the in-app bulk JSON import
feature (`/admin/import`) and the `scripts/validate_content.dart`
refactor onto shared validation. Re-run the greps below yourself if this
drifts — they're exactly how this audit was produced:

```bash
grep -rniE "TODO|FIXME|not yet built|coming soon|placeholder|stub" lib/
grep -rliE "ai.?teacher|chatgpt|openai|anthropic|gpt-|llm" lib/ pubspec.yaml
grep -rliE "pdf.*generat|generat.*pdf|printing" lib/ pubspec.yaml
```

## Core architecture

| Area | Status |
|---|---|
| Phase → Subject → Paper → Section → Question → Answer hierarchy | COMPLETED |
| No year/academic-year field anywhere | COMPLETED (enforced by `scripts/validate_content.dart` and code review) |
| Riverpod + go_router + Supabase | COMPLETED |
| Offline cache for phases/subjects/papers/questions | COMPLETED (`CacheService`, `SharedPreferences`-backed) |
| Material 3, light/dark mode | COMPLETED |

## Authentication & account

| Area | Status |
|---|---|
| Sign up / login / logout | COMPLETED |
| Forgot/reset password (incl. deep link) | COMPLETED |
| Change password | COMPLETED (reuses reset-password screen) |
| Account deletion | COMPLETED (`delete-account` Edge Function, service-role key stays server-side) |
| Session persistence | COMPLETED (supabase_flutter default) |

## Content browsing (normal users)

| Area | Status |
|---|---|
| Original paper viewer (PDF/image, zoom/pan/fullscreen/share) | COMPLETED |
| MCQ answer key | COMPLETED |
| Short/long solved answers | COMPLETED |
| Complete solved paper (search within paper) | COMPLETED |
| Quality-check badges + original-vs-verified answer discrepancy display | COMPLETED |
| Global search across published content | COMPLETED |
| Bookmarks (paper/MCQ/short/long, filterable) | COMPLETED |
| Practice mode (setup → session → scored result) | COMPLETED |
| Progress tracking by phase/subject | COMPLETED |
| Real exam content to browse | BLOCKED BY MISSING SOURCE PAPERS — every phase/subject slot is Missing Source; nothing was invented to fill it |

## Admin content management

| Area | Status |
|---|---|
| Create paper for a phase/subject slot | COMPLETED |
| Upload/replace original file to Storage | COMPLETED |
| Section CRUD | COMPLETED |
| Question CRUD (MCQ/short/long, MCQ options editor) | COMPLETED |
| Drag-to-reorder questions with auto-renumbering | COMPLETED (`ReorderableListView`, save/cancel/undo, unsaved-changes indicator) |
| Live duplicate/gap numbering detection | COMPLETED (`QuestionNumberingValidator`, shared with `PaperQualityChecker` and both importers, not duplicated) |
| Paper-level quality report (score, ✗ errors, ⚠ warnings) | COMPLETED |
| Status workflow (Draft→Needs Review→Verified→Published, +Archive/Restore) | COMPLETED, server-enforced (`admin_transition_paper_status` RPC) |
| Auto-invalidation of verification on content edit | COMPLETED (DB trigger, not app-level) |
| Search/filter/sort on Manage Papers | COMPLETED |
| Content Coverage screen (all 24 slots + status) | COMPLETED |
| Audit log | COMPLETED (write-side for admin actions + automatic transitions; read-only list screen) |
| Dashboard real counts (papers by status, subjects, questions, users) | COMPLETED |
| Bulk JSON import from the UI (vs. the scripted importer) | COMPLETED — **Admin → Import Content** (`/admin/import`), picks a JSON file, validates with `ContentImportValidator`, imports as the signed-in admin via RLS (no service-role key) |

## Content validation & import pipeline

| Area | Status |
|---|---|
| `scripts/validate_content.dart` (phase/subject/type/quality/MCQ/answer/marks/numbering/year-field checks) | COMPLETED |
| `scripts/import_content.dart` (JSON → DRAFT papers via PostgREST) | COMPLETED |
| Shared validation between Section Editor, Review screen, and the importer(s) | COMPLETED — `scripts/validate_content.dart` now imports `AppConstants` and `QuestionNumberingValidator` directly from the app package (`package:induction_program_past_papers/...`) for its phase/subject-slug sets, question-type/quality-status sets, and duplicate/gap detection, instead of a second hand-maintained copy; it also gained gap (missing-number) detection it previously lacked. `ContentImportValidator` (the in-app importer's validator) shares the same `AppConstants`/`QuestionNumberingValidator` too. All three surfaces — Section Editor, `PaperQualityChecker`, and both importers — now go through the same two files for numbering rules. |

## Verification workflow

| Area | Status |
|---|---|
| `verified_by` / `verified_at` / `verification_notes` | COMPLETED |
| Publish/Verify blocked server-side by critical errors | COMPLETED |
| Content change after verification demotes status automatically | COMPLETED |

## AI Teacher

| Area | Status |
|---|---|
| Provider-agnostic Edge Function (`supabase/functions/ai-teacher`) | COMPLETED — Flutter never talks to an LLM provider directly; it only calls the `ai-teacher` Edge Function via `functions.invoke`. Provider selection (`AI_PROVIDER`/`AI_MODEL`) and the API key are Edge Function secrets only; adding a new provider means adding a new `callProvider` case, not touching Flutter. |
| Verified-content retrieval for question context | COMPLETED — the function fetches `questionId` context through a JWT-scoped (not service-role) Supabase client, so Postgres RLS (PUBLISHED-only for non-admins) structurally prevents draft/unverified content from ever reaching the AI prompt. |
| "Verified" vs "AI-generated" labeling | COMPLETED — `ai_messages.content_kind` is a DB CHECK-constrained column (`VERIFIED_ANSWER` / `AI_GENERATED_EXPLANATION_BASED_ON_VERIFIED` / `AI_GENERATED_ANSWER` / `GENERAL`), mapped to the exact spec label strings and rendered above every assistant bubble. Verified by a widget test that asserts `VERIFIED ANSWER` is never shown for an AI-generated explanation. |
| Rate limiting / cost control | COMPLETED — `ai_usage_daily` has no client insert/update RLS policy at all, so only the Edge Function's service-role client can increment it; the daily limit, max prompt length, max output tokens, and timeout are all read from `app_settings` (runtime-tunable without redeploying). |
| Conversations/messages persistence + RLS | COMPLETED — `ai_conversations`/`ai_messages` are owner-only via RLS (`auth.uid() = user_id`, or via the parent conversation for messages); no cross-user access is possible at the database layer. |
| Chat UI (`AiTeacherScreen`) — send, retry, copy, share, clear, quick actions, Urdu toggle, question-context banner | COMPLETED |
| Question-context entry point (`Ask AI Teacher` on `QuestionTile`) | COMPLETED |
| No-fabrication guarding | COMPLETED structurally — the system prompt forbids inventing official exam content, and any question-context answer is grounded only in what RLS actually returns for that `questionId`; there is no path for the AI to answer as if it had a real paper it wasn't given. |
| Stop Generation | COMPLETED as a client-side-only cancellation (`CancelableOperation` in `ai_teacher_screen.dart`) — abandons waiting for/displaying an in-flight response. Does **not** abort the actual Edge Function/provider call (no cancellation hook in `supabase_flutter`'s functions client), which is disclosed in `docs/AI_TEACHER_GUIDE.md`, not glossed over. |
| New Conversation vs Clear Chat | COMPLETED as two separate menu actions — New Conversation resets the view with no confirmation and no deletion (the old conversation stays in history); Clear Chat asks "Clear this conversation?" and, only if confirmed, deletes the underlying conversation. |
| Regenerate | COMPLETED — re-sends the last user message/action and replaces the previous answer without duplicating the user's bubble; the same fix also resolved a pre-existing duplicate-user-bubble bug in Retry. |
| Verified content priority / discrepancy detection | COMPLETED client-side (`AiDiscrepancyDetector`) — when a question is opened in MCQ context, the chat screen compares the AI's stated `Correct Answer is LETTER.` against the app's own verified answer and shows a warning bubble on mismatch, without ever letting the AI overwrite the verified value anywhere. |
| Generated practice labeling | COMPLETED — `make_quiz`/`similar_questions` are labelled `AI_GENERATED_PRACTICE` (migration `008_ai_teacher_practice_kind.sql`), with a secondary "NEEDS REVIEW" badge, and are never persisted as real questions. |
| Markdown-lite rendering | COMPLETED for headings/bold/bullets/numbered lists via a small custom widget — no full markdown package added; no tables/links/code fences/math rendering. |
| Unit/widget tests | COMPLETED — 31 unit tests (`ai_teacher_validation_test.dart`) covering labeling, prompt validation, error mapping, action sets, practice-content/NEEDS-REVIEW rules, and the discrepancy detector; 16 widget tests (`ai_teacher_screen_test.dart`) covering empty/loading/error/retry states, question-context mode, verified-vs-AI-generated labeling, Stop Generation, New Conversation vs Clear Chat, Regenerate, discrepancy detection, and practice labeling. |
| **Honest gaps** | `VERIFIED_ANSWER` is schema-supported but never actually produced by the current flow (the AI always explains/answers — it never emits a bare verified answer with no AI framing). Stop Generation is UI-level abandonment only, not a true network abort. No streaming responses. Live provider calls and live Supabase RLS enforcement are **not executed** in this sandbox (no real `ANTHROPIC_API_KEY`, no live Supabase project) — this is asserted from code/migration review, the same way every other RLS claim in this project has been verified, not from a live end-to-end run. |

See `docs/AI_TEACHER_GUIDE.md` for the full architecture, environment variables, and deployment steps, and `docs/AI_TEACHER_ARCHITECTURE.md` for the streaming evaluation (not implemented — documented why) and why a VERIFIED_ANSWER "AI-answer promotion" pipeline was deliberately not built (see also `docs/REMAINING_WORK_AUDIT.md` §2–4).

## PDF / export

| Area | Status |
|---|---|
| Original Paper PDF | COMPLETED — this is the uploaded source file itself, already viewable/shareable; nothing to "generate" |
| MCQ Answer Key PDF | COMPLETED (`PdfExportService`, export button on the Answer Key screen) |
| Solved Short Questions PDF | COMPLETED |
| Solved Long Questions PDF | COMPLETED |
| Complete Solved Paper PDF | COMPLETED |
| Generated PDFs show app name/phase/subject/title/section/questions/answers/verification status/generated date | COMPLETED — see `PdfExportService`, every field is read from `Paper`/`Question`, nothing invented |
| Persistent Downloads Manager (save locally, list, Open/Share/Delete, duplicate prevention, missing-file detection) | COMPLETED — `lib/features/downloads/`, `DownloadsService`; see `docs/SECURITY_AUDIT.md` "Download security" and `docs/REMAINING_WORK_AUDIT.md` §15. |
| Real exam content in an exported PDF | BLOCKED BY MISSING SOURCE PAPERS — exporting/downloading works today; there's nothing real to export yet |

## Security

| Area | Status |
|---|---|
| RLS enabled on every content/user table | COMPLETED — `alter table ... enable row level security` on 13 tables in `002_rls.sql` |
| Admin writes gated server-side (not just client UI) | COMPLETED — `is_admin()` policies + `admin_transition_paper_status`/`paper_has_critical_errors` re-validate independent of the Flutter app |
| No service-role key in `lib/` | COMPLETED — verified by repository-wide grep, zero matches |
| No AI provider secret in `lib/` | N/A — no AI integration exists to leak a secret from |
| Account deletion | COMPLETED |
| Storage access secured | COMPLETED — public read (educational content), admin-only write via Storage policies |
| `profiles.is_admin` cannot self-escalate | COMPLETED — dedicated trigger, not just RLS `with check` |
| Audit trail protected from normal users | COMPLETED — `audit_logs` RLS is admin-read/insert only |

## Performance

See `docs/PERFORMANCE_AUDIT.md` for the full audit; summary below.

| Area | Status |
|---|---|
| N+1 query pattern in `PaperRepository.getSectionsWithQuestions`/`AdminRepository.getPaperContent` (one query per section) | COMPLETED — both now fetch every section's questions in one `inFilter` query instead of one query per section. |
| N+1 write pattern in `AdminRepository.reorderQuestions` (one UPDATE per question) | COMPLETED — replaced with a single atomic RPC (`admin_reorder_questions`, `009_performance_indexes_and_rpcs.sql`) via `update ... from unnest(...)`. |
| Admin dashboard stats (5 queries pulling full rows to count in Dart) | COMPLETED — replaced with one aggregating RPC (`admin_dashboard_stats`) returning only the computed counts. |
| Pagination on large/unbounded lists | COMPLETED for the two lists that actually grow unboundedly — Audit Log and Review Questionable Questions are now keyset-paginated (`lib/core/pagination/`, a reusable `PaginationNotifier<T>`), with scroll-triggered load-more and pull-to-refresh. Search gained offset-based "load more". |
| Pagination on the papers list / a single paper's question list | **Deliberately not implemented** — `papers` is structurally capped at 24 rows (`unique(phase_id, subject_id)`, 3 phases × 8 subjects) and a single paper's question count is bounded by what a real past paper actually contains; pagination there would add complexity with no dataset that could ever need it. See `docs/PERFORMANCE_AUDIT.md` §5/§8. |
| Missing indexes | COMPLETED — `idx_audit_logs_created_at`, `idx_questions_created_at` added (`009_performance_indexes_and_rpcs.sql`) to support the new keyset queries; everything else was already indexed in `005_indexes.sql`. |
| Offline cache for reads | COMPLETED |
| Startup cost | COMPLETED — splash screen is a fixed short delay, no eager loading of all content |
| **Honest gap** | Not verified against a live Postgres instance: actual round-trip counts, `EXPLAIN`-confirmed index usage, or RPC behavior under a real non-admin JWT. Asserted from code/migration review only — see `docs/PERFORMANCE_AUDIT.md` §10. |

## Play Store readiness

| Area | Status |
|---|---|
| `applicationId`, `compileSdk`/`targetSdk` (API 36 via Flutter's bundled default) | COMPLETED |
| Release signing config (reads `key.properties`, falls back to debug locally) | COMPLETED |
| Privacy policy / disclaimer / about screens | COMPLETED |
| Data Safety / content rating / store listing text | COMPLETED as documentation (`store_listing/README.md`) — these are Play Console forms to fill in, not app code |
| Actual release AAB/APK build | BLOCKED BY ENVIRONMENT — no Android SDK in this sandbox, and downloading one is blocked by the environment's egress policy (`dl.google.com` rejected). See `docs/FINAL_QA_REPORT.md`. |

## Testing

| Area | Status |
|---|---|
| Unit tests for scoring/validation/reorder/numbering/import logic | COMPLETED — 88 tests across `test/unit/`, all pure/no-network |
| Widget test (app boot) | COMPLETED |
| RLS/non-admin-rejection enforcement test | NOT IMPLEMENTED — needs a live Supabase project; covered by code review of `002_rls.sql`/`006_admin_workflow.sql` instead, called out explicitly in `CLAUDE.md` |
| Android build verification | BLOCKED BY ENVIRONMENT |
