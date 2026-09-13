# CLAUDE.md — Induction Program Past Papers

Instructions for any future Claude Code session (or human) maintaining this
project. Read this before making structural, database, or content changes.

## Project Purpose

An Android app (Flutter + Supabase) helping newly recruited KP government
teachers prepare for the Teacher Induction Program exams: original past
papers, verified answer keys, solved short/long questions, complete solved
papers, MCQ practice, bookmarks, and progress tracking.

For the admin content workflow specifically (how a paper moves from an
empty phase/subject slot to Published), see
`docs/ADMIN_CONTENT_GUIDE.md` (manual, in-app) and
`docs/CONTENT_IMPORT_GUIDE.md` (scripted JSON import) — this file states
the rules those guides must keep following, not the how-to.

## Architecture Rules

- Clean-ish layering: `lib/core` (constants, theme, routing, errors,
  services), `lib/data` (models, repositories, datasources), `lib/features`
  (one folder per feature), `lib/shared/widgets` (cross-feature UI).
- State management: Riverpod (`flutter_riverpod`). Navigation: `go_router`.
  Backend: `supabase_flutter`.
- Models are hand-written plain Dart classes with `fromJson`/`toJson` — no
  code generation (freezed/json_serializable) is used, to keep the build
  simple. Keep new models consistent with this style.
- Repositories are the only layer that talks to `SupabaseService.client`
  directly. Screens/widgets never call Supabase directly.
- Offline reads go through `CacheService` (SharedPreferences-backed JSON
  cache). Every repository read method should attempt network first, then
  fall back to cache on failure — see `PhaseRepository` for the pattern.
- Admin writes (`lib/data/repositories/admin_repository.dart`,
  `lib/features/admin/`) are kept separate from the read-only repositories
  normal users go through — admin screens never read/write via
  `PaperRepository` etc. Pure validation used by an admin write path
  belongs in `lib/core/validation/` (see `QuestionValidation`), not inline
  in the repository method, so it stays unit-testable without mocking
  Supabase — extend that pattern for new admin content rules rather than
  adding another inline check.

## Database Rules (see supabase/migrations/)

- Hierarchy is always: **phases -> subjects -> papers -> paper_sections ->
  questions -> question_options**.
- **NEVER add a year / academic_year / session_year column anywhere.** This
  is a hard constraint from the product spec — the app has no year-based
  organization at all. `scripts/validate_content.dart` actively rejects any
  content JSON containing such a field; do not weaken that check.
- Exactly 3 phases (`phase-2`, `phase-3`, `phase-4`) and 8 subjects are
  seeded structurally in `004_seed_structure.sql`. Do not add a 4th phase or
  a 9th subject without an explicit product decision — the whole app (home
  screen, practice setup, progress, admin dashboard) assumes this fixed set.
- `papers` has a `unique (phase_id, subject_id)` constraint — one paper per
  phase/subject slot (24 max). If a phase/subject legitimately needs more
  than one paper in the future, that's a schema change to discuss first,
  not something to route around client-side.
- `questions.original_marked_option` vs `questions.verified_answer` are
  deliberately separate columns — never collapse them. A tick on the
  original paper is never auto-accepted as the correct answer.
- `papers.content_status` stays exactly the 5 values from
  `001_initial_schema.sql` (`DRAFT`, `UNDER_REVIEW`, `VERIFIED`,
  `PUBLISHED`, `ARCHIVED`) — `006_admin_workflow.sql` adds workflow
  metadata (`verified_by`/`verified_at`/`verification_notes`) and
  behavior, not new status values. "Needs Review" and "Missing Source"
  are UI labels only (see `PaperStatusPresentation` in
  `lib/core/validation/paper_status.dart`) — never add them as stored
  strings; a DB migration to widen the check constraint is a bigger
  decision than a status-label rename and hasn't been made.
- Status changes MUST go through the `admin_transition_paper_status`
  Postgres function (`006_admin_workflow.sql`), never a raw
  `update papers set content_status = ...` from the client — that
  function is what enforces the state machine and the critical-error
  quality gate server-side. `AdminRepository.transitionPaperStatus` is
  the only sanctioned client-side entry point; keep it that way.
- Editing a section or question on a paper that is `VERIFIED` or
  `PUBLISHED` automatically demotes it to `UNDER_REVIEW` and clears its
  verification record — enforced by the
  `invalidate_verification_on_content_change` trigger on
  `paper_sections`/`questions`, not application code. Don't try to
  "fix" this by re-verifying in the same request; it's intentional (spec
  section 12: a modified verified question must never keep looking
  verified).

## Content Rules

- **No fake data, ever, in anything that ships.** No "Lorem ipsum", "Sample
  Question", "Demo Paper", "Test Answer" in migrations, seed data, or the
  `content/` directory. The only seeded rows are the 3 phases and 8
  subjects (structure, not exam content).
- Every question must carry a `quality_status`
  (VERIFIED/QUESTIONABLE/PAPER_ERROR/OCR_UNCERTAIN/ANSWER_UNCERTAIN). Any
  non-VERIFIED status requires a `quality_note` explaining why —
  `validate_content.dart` enforces this.
- Content flow: write source JSON under `content/phase_<N>/<subject>.json`
  → `dart run scripts/validate_content.dart content` (must pass with 0
  critical errors) → `dart run scripts/import_content.dart content
  --url=... --service-key=...` **or** the in-app **Admin → Import
  Content** screen (`/admin/import`, no service-role key needed — runs as
  the signed-in admin) → (either path inserts as DRAFT) → human review →
  admin explicitly sets `content_status = 'PUBLISHED'`. Never publish
  content that hasn't passed through this pipeline. Both import paths and
  the Section Editor's live check all validate numbering through the same
  `QuestionNumberingValidator` — don't add a fourth copy of that rule.
- If a source paper for a phase/subject slot doesn't exist yet, leave it
  missing. Do not invent one. The correct UI/report language is "MISSING
  SOURCE PAPER — DO NOT PUBLISH", already implemented in the subject and
  original-paper-viewer screens.

## AI Teacher Rules

- AI Teacher is an educational tutor, **never** an official examination
  authority. Its output must never be presented as an official verified
  answer unless it actually is one.
- The Flutter app is provider-agnostic by construction: it only calls
  `SupabaseService.client.functions.invoke('ai-teacher', ...)`. Never add
  a direct import of an LLM provider SDK/type under `lib/`, and never
  hardcode a provider name/model into Flutter code — provider/model
  selection lives entirely in the `ai-teacher` Edge Function's env vars
  (`AI_PROVIDER`, `AI_MODEL`). Adding a new provider means adding a new
  `callProvider` case in `supabase/functions/ai-teacher/index.ts`, not
  touching Flutter.
- `ai_messages.content_kind` is the single source of truth for
  verified-vs-AI-generated labeling (`VERIFIED_ANSWER` /
  `AI_GENERATED_EXPLANATION_BASED_ON_VERIFIED` / `AI_GENERATED_ANSWER` /
  `AI_GENERATED_PRACTICE` / `GENERAL`, DB CHECK-constrained). Never
  introduce a second, independent way to decide whether something is
  "verified" in the AI Teacher UI — always derive the label from this
  column via `AiContentKindX.label`, and the secondary "NEEDS REVIEW"
  badge via `AiContentKindX.needsReviewBadge`.
- `make_quiz`/`similar_questions` responses are always
  `AI_GENERATED_PRACTICE`, never `AI_GENERATED_ANSWER` — generated
  practice questions must never be written into `questions`/
  `paper_sections`; they only ever live as `ai_messages` rows.
- `AiDiscrepancyDetector` (client-side) and the system prompt's
  `Correct Answer is LETTER.` convention for MCQ explanations are a
  matched pair — if the convention's wording changes in the system
  prompt, update the detector's regex in the same change, or it will
  silently stop catching discrepancies.
- The Edge Function must fetch verified question/answer context through
  a JWT-scoped Supabase client (respecting RLS), never the service-role
  client — this is what structurally guarantees the AI is never handed
  DRAFT/UNDER_REVIEW content for a non-admin user.
- `ai_usage_daily` must keep having no authenticated insert/update RLS
  policy — only the Edge Function's service-role client may write it.
  Don't add a policy that would let a client inflate its own quota.
- Don't fabricate exam content through the AI path either: the system
  prompt (`SYSTEM_PROMPT` in `index.ts`) forbids the AI from claiming
  generated questions/answers are real Induction Program past-paper
  content, and that instruction must stay intact if the prompt is
  edited.

## Security Rules

- The Flutter app must only ever hold `SUPABASE_ANON_KEY` (passed via
  `--dart-define`, see `.env.example`). `SUPABASE_SERVICE_ROLE_KEY` must
  never be referenced from anywhere under `lib/`.
- All write access to official content tables (`papers`, `paper_sections`,
  `questions`, `question_options`, `phases`, `subjects`) is enforced by
  Postgres RLS requiring `profiles.is_admin = true` — see
  `002_rls.sql`. `AdminGuard` in the Flutter app is a UX convenience only,
  never the actual security boundary.
- Account deletion goes through the `delete-account` Edge Function
  (service-role key lives only in the function's server environment), not
  a client-side delete call.
- `profiles.is_admin` cannot be self-escalated by a user — enforced by the
  `prevent_self_admin_escalation` trigger, not just RLS `with check`.
- Publishing (or verifying) a paper with unresolved critical quality
  errors is blocked server-side by `paper_has_critical_errors` inside
  `admin_transition_paper_status` (`006_admin_workflow.sql`) — the
  Flutter UI's own `PaperQualityChecker` gating on the Review screen is a
  UX convenience mirroring the same rules, not the enforcement.
- Every admin content write should get an `audit_logs` row (see
  `AdminRepository._logAudit`, best-effort/non-blocking) or come from a
  trigger that writes one itself (`admin_transition_paper_status`,
  `invalidate_verification_on_content_change`). `audit_logs` is
  admin-read-only via RLS — don't expose it to normal users.

## Testing Rules

- `flutter analyze` must report zero errors (info-level deprecation notices
  from third-party packages are acceptable; fix them opportunistically).
- `flutter test` must pass. Add unit tests for any new scoring/validation
  logic (see `test/unit/`), and extend `test/widget_test.dart` cautiously —
  it boots the real app shell, so keep any new assertions resilient to
  async auth/navigation timing (see existing `pump`/`pumpAndSettle` usage).
- `dart run scripts/validate_content.dart content` must exit 0 before any
  content import.
- True "non-admin rejection" / RLS enforcement tests need a live Supabase
  project and aren't run by `flutter test` in this repo — that's covered
  by reading `002_rls.sql`/`006_admin_workflow.sql` directly, not by an
  automated test here. What *is* unit-tested without a backend: the pure
  logic in `lib/core/validation/` — `PaperStatusTransitions` (state
  machine), `PaperQualityChecker` (critical-error/warning detection,
  mirroring `paper_has_critical_errors`), `QuestionValidation`, and
  `PaperFilter` (search/filter/sort). Add to those files and their
  `test/unit/*_test.dart` counterparts for new admin content rules,
  rather than writing logic inline in a repository method or widget.

## UI Rules

- Material 3, deep teal/blue seed color (`AppTheme`). No years displayed
  anywhere in the UI, including admin screens.
- Quality-check UI: a quiet "Verified" chip for VERIFIED questions; a
  tappable warning chip (`QualityBadge`) for anything else, expanding to
  show `quality_note`. Don't add a second, competing quality-indicator
  pattern — reuse `QualityBadge`/`QuestionTile`.

## Play Store Rules

- `applicationId` (`com.asmatullahkhan.induction_program_past_papers`) is
  permanent — never change it.
- `compileSdk`/`targetSdk` follow `flutter.compileSdkVersion` /
  `flutter.targetSdkVersion` (currently 36 from the bundled Flutter Gradle
  plugin) rather than a hard-coded number, so upgrading Flutter keeps Play
  Store's target-API requirement satisfied automatically. Re-check this
  assumption before each release.
- Release signing reads `android/key.properties` (see
  `key.properties.example`); never commit a real keystore or
  `key.properties`.

## Do-Not-Do List

- Do not add a year/academic-year/session-year field or year-based
  navigation anywhere.
- Do not invent questions, options, or answers. Do not silently "correct" a
  question's wording — use `quality_status`/`quality_note` instead.
- Do not auto-publish content — publishing is always an explicit, separate
  admin action.
- Do not put `SUPABASE_SERVICE_ROLE_KEY` in the Flutter app, in
  `--dart-define`, or in any file under `lib/`.
- Do not bypass RLS from the client; do not add a client-side "isAdmin"
  check as the only gate for a write.
- Do not commit `.env`, `key.properties`, `*.jks`/`*.keystore`, or any real
  secret. Use the provided `.example` files.
- Do not add analytics or ads without also updating the Privacy Policy and
  Data Safety declaration in the same change (see spec sections 53–54).
