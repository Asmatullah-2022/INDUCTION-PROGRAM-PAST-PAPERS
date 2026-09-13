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
| Unit/widget tests | COMPLETED — 20 unit tests (`ai_teacher_validation_test.dart`) covering labeling, prompt validation, error mapping, action sets; 9 widget tests (`ai_teacher_screen_test.dart`) covering empty/loading/error/retry states, question-context mode, and verified-vs-AI-generated labeling. |
| **Honest gaps** | "Stop generation" is not implemented (Dart `Future`s used here aren't natively cancellable). "New conversation" and "Clear chat" are one combined menu action, not two separate ones. `VERIFIED_ANSWER` is schema-supported but never actually produced by the current flow (the AI always explains/answers — it never emits a bare verified answer with no AI framing). Live provider calls and live Supabase RLS enforcement are **not executed** in this sandbox (no real `ANTHROPIC_API_KEY`, no live Supabase project) — this is asserted from code/migration review, the same way every other RLS claim in this project has been verified, not from a live end-to-end run. |

See `docs/AI_TEACHER_GUIDE.md` for the full architecture, environment variables, and deployment steps.

## PDF / export

| Area | Status |
|---|---|
| Original Paper PDF | COMPLETED — this is the uploaded source file itself, already viewable/shareable; nothing to "generate" |
| MCQ Answer Key PDF | COMPLETED (`PdfExportService`, export button on the Answer Key screen) |
| Solved Short Questions PDF | COMPLETED |
| Solved Long Questions PDF | COMPLETED |
| Complete Solved Paper PDF | COMPLETED |
| Generated PDFs show app name/phase/subject/title/section/questions/answers/verification status/generated date | COMPLETED — see `PdfExportService`, every field is read from `Paper`/`Question`, nothing invented |
| Real exam content in an exported PDF | BLOCKED BY MISSING SOURCE PAPERS — exporting works today; there's nothing real to export yet |

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

| Area | Status |
|---|---|
| Pagination on large lists | PARTIALLY COMPLETED — the admin paper list (max 24 rows) and practice question lists are small enough that client-side filtering (`PaperFilter`) is correct and simpler than server pagination; there is no true "load everything" list at a scale where this matters yet, because there is no content. Revisit if/when a phase/subject ever needs more than one paper or a subject accumulates hundreds of questions. |
| N+1 query pattern in `PaperRepository.getSectionsWithQuestions`/`AdminRepository.getPaperContent` (one query per section) | PARTIALLY COMPLETED — correct today because a paper has at most a handful of sections; worth a single joined query (`paper_sections` + `questions` + `question_options` in one round trip) if paper structures ever grow section-heavy. Not changed here — a real behavior change to a working query path is exactly the kind of "risky architectural rewrite" the brief said to avoid without a concrete need. |
| Offline cache for reads | COMPLETED |
| Startup cost | COMPLETED — splash screen is a fixed short delay, no eager loading of all content |

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
