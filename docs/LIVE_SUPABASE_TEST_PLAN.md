# Live Supabase Test Plan

**NOT EXECUTED.** This sandbox has no live Supabase project — every test
below is a documented plan for whoever has access to a real project to
run, not a report of results. Do not treat anything in this document as
a passed test. This plan supersedes/expands the shorter matrix in
`docs/SECURITY_AUDIT.md` "RLS test preparation" with concrete per-area
test cases; keep both in sync if either changes.

## Roles this app actually has

The schema has exactly two access levels: **admin**
(`profiles.is_admin = true`) and **everyone else**. "Teacher",
"Aspirant", and "Student" are not distinct roles in the database or RLS
— they're just different kinds of authenticated non-admin users, and
every RLS policy treats them identically. The test plan below tests
"authenticated non-admin" once, not three times, because testing it
three times with three different profile rows would exercise identical
policy code paths — noted explicitly so this isn't mistaken for an
oversight.

## Setup for whoever runs this

1. A real Supabase project with all migrations (`001` through `009`)
   applied in order.
2. At least one test user promoted to `is_admin = true` (directly via
   SQL — there is no in-app path to self-promote, by design).
3. At least one ordinary (non-admin) test user.
4. At least one PUBLISHED paper, one DRAFT paper, and one UNDER_REVIEW
   paper with sections/questions — synthetic test fixtures are fine
   here (this is infrastructure testing, not exam content; label any
   test fixture clearly, e.g. "TEST FIXTURE — DO NOT PUBLISH", and
   never let it reach a real device build).
5. Either the Supabase CLI's local test tooling (`supabase test db`) or
   direct `psql` sessions with `set role authenticated; set
   request.jwt.claims = '{"sub": "<uuid>"}';` per test user.

## 1. Anonymous (no session)

| Test | Expected |
|---|---|
| Read `phases`/`subjects` | Allowed (public read, `is_active = true`) |
| Read a PUBLISHED paper + its sections/questions/options | Allowed |
| Read a DRAFT/UNDER_REVIEW/VERIFIED/ARCHIVED paper | **Denied** (zero rows) |
| Read any `bookmarks`/`practice_attempts`/`practice_answers`/`user_progress`/`ai_conversations`/`ai_messages` row | **Denied** |
| Read `audit_logs` | **Denied** |
| Read `ai_usage_daily` | **Denied** |
| Call `admin_dashboard_stats()`/`admin_reorder_questions(...)`/`admin_transition_paper_status(...)` | Either denied outright, or (since these run `security invoker`) executes but affects/returns nothing an anon session is allowed to see — confirm it's the latter, not an actual bypass. |
| Call the `ai-teacher` Edge Function | **401 Unauthorized** (no Authorization header / invalid session) |
| Call the `delete-account` Edge Function | **401 Unauthorized** |

## 2. Authenticated non-admin ("Teacher"/"Aspirant"/"Student" — identical policy path)

| Test | Expected |
|---|---|
| Read a PUBLISHED paper | Allowed |
| Read a DRAFT/UNDER_REVIEW/VERIFIED/ARCHIVED paper | **Denied** |
| Read another user's `bookmarks`/`practice_attempts`/`practice_answers`/`user_progress` | **Denied** (zero rows, not an error) |
| Insert/update/delete their **own** `bookmarks`/`practice_attempts`/`practice_answers`/`user_progress` | Allowed |
| Insert/update/delete **another user's** row in any of those tables | **Denied** |
| Read/write `papers`/`paper_sections`/`questions`/`question_options`/`phases`/`subjects`/`app_settings` | **Denied** for write; read only via the PUBLISHED-only policy |
| Read/insert `audit_logs` | **Denied** |
| Read own `profiles` row | Allowed |
| Update own `profiles.is_admin` to `true` | **Denied** — confirm the `prevent_self_admin_escalation` trigger silently reverts it rather than erroring loudly; check the resulting row, not just whether the UPDATE statement itself errored. |
| Read another user's `ai_conversations`/`ai_messages` | **Denied** |
| Insert/read own `ai_conversations`/`ai_messages` | Allowed |
| Read own `ai_usage_daily` row | Allowed |
| Insert/update own `ai_usage_daily` row directly (not via the Edge Function) | **Denied** — this is the rate-limit integrity check; confirm there is truly no policy that would let this succeed. |
| Call `admin_dashboard_stats()` | Executes (security invoker) but every count should reflect only what this user's RLS allows to see (e.g. `total_papers` reflecting only PUBLISHED papers, not the true total) — confirm the numbers, don't just confirm "no error". |
| Call `admin_reorder_questions(...)` on a real question id | Executes without error but the underlying `UPDATE` affects zero rows — confirm by re-reading the question afterward and seeing it unchanged. |
| Call `admin_transition_paper_status(...)` | Should fail or no-op — confirm which, and that no paper's `content_status` actually changes. |
| Call the `ai-teacher` Edge Function with a valid session | Succeeds, subject to rate limiting; a `questionId` for a DRAFT/UNDER_REVIEW paper should be silently treated as "no verified context found" (RLS on the read inside the function), not an error and not leaked content. |
| Call the `delete-account` Edge Function | Deletes only the calling user's own account/data; confirm via a subsequent login attempt that the account is gone, and that another test user's data is untouched. |
| Read Storage: a PUBLISHED paper's original file URL | Allowed (public bucket read, by design) |
| Upload/overwrite a Storage object in `original-papers` | **Denied** |

## 3. Admin (`profiles.is_admin = true`)

| Test | Expected |
|---|---|
| Read/write papers of every `content_status` | Allowed |
| Create/edit sections, questions, options | Allowed |
| Call `admin_transition_paper_status(...)` for every legal transition (`DRAFT→UNDER_REVIEW`, `UNDER_REVIEW→VERIFIED`, `VERIFIED→PUBLISHED`, etc.) | Allowed, and the transition matrix in `006_admin_workflow.sql` is enforced (an illegal jump, e.g. `DRAFT→PUBLISHED` directly, must still fail even for an admin). |
| Attempt to verify/publish a paper with an unresolved critical error (e.g. an MCQ with no correct option marked) | **Denied by `paper_has_critical_errors`**, even though the caller is an admin — this is the one case where admin status alone is not sufficient; confirm the gate holds. |
| Call `admin_reorder_questions(...)` on a real section's questions | Succeeds, and the paper's `invalidate_verification_on_content_change` trigger correctly demotes a VERIFIED/PUBLISHED paper to `UNDER_REVIEW` if it was reordering questions under one. |
| Call `admin_dashboard_stats()` | Returns the true, unfiltered counts across all statuses. |
| Read `audit_logs` | Allowed, and confirm every admin action above actually produced a row. |
| Upload/overwrite a Storage object in `original-papers` | Allowed. |
| Read another user's `bookmarks`/`practice_attempts`/`ai_conversations` | **Denied** — admin status does not grant blanket access to other users' personal data; only `profiles` has an explicit "admin read all" policy, and it should stay that way. Confirm this is still true after all migrations. |
| Self-escalate is a non-issue for an existing admin, but confirm a **second** admin cannot be silently created by any path other than a direct database action by an existing admin. |

## 4. Cross-cutting checks

- **MISSING_SOURCE never appears as real content**: confirm a DRAFT
  paper with no `source_file_url` is invisible to non-admin queries
  entirely (not returned with a "missing source" flag — it should not
  be returned at all, since it's not PUBLISHED).
- **NEEDS_REVIEW (UNDER_REVIEW) never appears in a public list**: same
  check, for a paper in `UNDER_REVIEW`.
- **A modified VERIFIED/PUBLISHED paper loses its verified status
  automatically**: as an admin, edit a question under a PUBLISHED
  paper, then confirm (a) the paper's `content_status` is now
  `UNDER_REVIEW`, (b) `verified_by`/`verified_at` are cleared, and (c) a
  non-admin can no longer see that paper at all until it's re-verified
  and re-published.
- **Performance**: with `EXPLAIN ANALYZE`, confirm the two new
  `009_performance_indexes_and_rpcs.sql` indexes
  (`idx_audit_logs_created_at`, `idx_questions_created_at`) are actually
  used by the keyset-pagination queries (`AdminRepository.
  getAuditLogsPage`/`getQuestionableQuestionsPage`), not sequentially
  scanned — see `docs/PERFORMANCE_AUDIT.md` §10 for why this couldn't be
  confirmed without a live database.

## Recording results

When this plan is actually executed, replace **NOT EXECUTED** at the
top of this document with the date and environment it was run against,
and mark each row above PASS/FAIL with a one-line note — do not delete
the row structure, so a future re-run has the same checklist to compare
against.
