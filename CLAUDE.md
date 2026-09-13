# CLAUDE.md — Induction Program Past Papers

Instructions for any future Claude Code session (or human) maintaining this
project. Read this before making structural, database, or content changes.

## Project Purpose

An Android app (Flutter + Supabase) helping newly recruited KP government
teachers prepare for the Teacher Induction Program exams: original past
papers, verified answer keys, solved short/long questions, complete solved
papers, MCQ practice, bookmarks, and progress tracking.

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
  --url=... --service-key=...` (inserts as DRAFT) → human review → admin
  explicitly sets `content_status = 'PUBLISHED'`. Never publish content
  that hasn't passed through this pipeline.
- If a source paper for a phase/subject slot doesn't exist yet, leave it
  missing. Do not invent one. The correct UI/report language is "MISSING
  SOURCE PAPER — DO NOT PUBLISH", already implemented in the subject and
  original-paper-viewer screens.

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

## Testing Rules

- `flutter analyze` must report zero errors (info-level deprecation notices
  from third-party packages are acceptable; fix them opportunistically).
- `flutter test` must pass. Add unit tests for any new scoring/validation
  logic (see `test/unit/`), and extend `test/widget_test.dart` cautiously —
  it boots the real app shell, so keep any new assertions resilient to
  async auth/navigation timing (see existing `pump`/`pumpAndSettle` usage).
- `dart run scripts/validate_content.dart content` must exit 0 before any
  content import.

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
