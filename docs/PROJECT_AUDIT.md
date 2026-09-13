# Project Audit

A structural overview of the codebase — architecture, security, and
testing posture — as opposed to `docs/PRODUCTION_FEATURE_AUDIT.md`'s
feature-by-feature completeness pass. Read that file for "is X built";
read this one for "is the foundation sound."

## Architecture

Clean-ish layering, unchanged since the initial build and documented in
`CLAUDE.md`:

```
lib/core/        constants, theme, routing, errors, services, validation, utils
lib/data/        models (plain Dart, fromJson/toJson, no codegen) + repositories
lib/features/    one folder per feature; admin/ is the largest
lib/shared/      cross-feature widgets
```

Repositories are the only layer touching `SupabaseService.client` — no
screen calls Supabase directly. Pure business logic (validation, scoring,
filtering, reordering) lives in `lib/core/validation/` and
`lib/core/utils/`, deliberately kept free of any Supabase/Flutter
dependency so it's unit-testable without mocking a backend. This pattern
held through every feature added, including this session's reordering
work (`QuestionNumberingValidator`, `QuestionReorder`).

## Database

5 stored `papers.content_status` values, unchanged since
`001_initial_schema.sql`. `006_admin_workflow.sql` (added in the previous
session) layered a real state machine and quality gate on top via a
Postgres function (`admin_transition_paper_status`) and a trigger
(`invalidate_verification_on_content_change`) — both server-side, so a
client cannot bypass either by calling the API directly. No migration in
this session's reordering work was needed: `question_number` and
`display_order` already existed on `questions`, so reordering only ever
updates existing columns on existing rows — no id is ever recreated.

## Security posture

- RLS is enabled on all 13 content/user tables (verified by grep over
  `supabase/migrations/`).
- Every admin write is gated by `profiles.is_admin` server-side, both via
  RLS policies and, for paper status specifically, an independent
  re-validation inside `admin_transition_paper_status`.
- `SUPABASE_SERVICE_ROLE_KEY` appears nowhere under `lib/` (verified by
  grep) — it's only used in `scripts/import_content.dart` (run outside
  the app) and the `delete-account` Edge Function's server environment.
- No AI provider secret exists anywhere, because no AI integration exists
  yet — see `docs/PRODUCTION_FEATURE_AUDIT.md` "AI Teacher".
- `profiles.is_admin` cannot be self-escalated (dedicated trigger, not
  just an RLS `with check`).
- `audit_logs` is admin-read/insert-only.

Nothing found in this audit required weakening or required a fix — the
foundation from prior sessions holds.

## Testing posture

88 tests in `test/unit/` + `test/widget_test.dart`, all passing, all
running without a live backend (pure logic + one widget-boot smoke test).
What's covered:

- Practice scoring (`practice_result_test.dart`)
- Model JSON round-trips and the no-year-field guarantee (`models_test.dart`)
- Question-save validation and answer-discrepancy resolution (`question_validation_test.dart`)
- Paper status transitions, the quality gate, and status presentation labels (`paper_status_test.dart`)
- Admin paper search/filter/sort (`paper_filter_test.dart`)
- Numbering duplicate/gap detection (`question_numbering_test.dart`)
- Reorder-and-renumber, id preservation, multi-step reordering (`question_reorder_test.dart`)
- Bulk-import JSON validation — phase/subject slugs, year-field rejection, numbering, MCQ/answer/quality rules (`content_import_validation_test.dart`)

What's explicitly not covered by `flutter test`, and why: RLS/non-admin
rejection requires a live Supabase project to exercise for real — that's
a property of the migrations, verified by reading them, not by an
automated test in this repo. See `CLAUDE.md` "Testing Rules" for the same
statement, kept in one place rather than repeated inconsistently.

## What changed since the last audit

Question reordering, PDF export, Content Coverage, and — most recently —
the in-app bulk JSON importer (`/admin/import`, backed by
`ContentImportValidator`) plus `scripts/validate_content.dart`'s refactor
onto the app's own `AppConstants`/`QuestionNumberingValidator` instead of a
second hand-maintained copy of the same rules. See
`docs/PRODUCTION_FEATURE_AUDIT.md` for the full feature-by-feature list.
No prior feature was removed, rewritten, or had its behavior changed —
only additions, per the explicit "do not rebuild"
instruction.
