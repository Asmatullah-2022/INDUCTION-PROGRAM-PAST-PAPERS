# Final QA Report

Run results as of the latest changes (**N+1 query optimization, server-
side pagination, and database performance hardening**), on top of all
prior work: AI Teacher (see `docs/AI_TEACHER_GUIDE.md`), question
reordering + live numbering validation, PDF export, Content Coverage
screen, in-app bulk JSON import, and `scripts/validate_content.dart`'s
move onto shared validation. See `docs/PERFORMANCE_AUDIT.md` for the
full performance audit this pass comes out of,
`docs/PRODUCTION_FEATURE_AUDIT.md` for feature-completeness, and
`docs/PROJECT_AUDIT.md` for the architecture/security narrative.

## PERFORMANCE AUDIT

Full audit in `docs/PERFORMANCE_AUDIT.md`. Headline structural fact that
shaped the scope: `papers` is capped at **24 rows** by a database
constraint (`unique(phase_id, subject_id)`, 3 phases × 8 subjects —
`CLAUDE.md` "Database Rules"), so the papers list was never a pagination
problem; the real N+1/growth risk was in per-section question fetching,
per-question reorder writes, admin dashboard counting, and the two
unboundedly-growing admin lists (Audit Log, Review Questionable
Questions).

**N+1 ISSUES FOUND: 3**
1. `PaperRepository.getSectionsWithQuestions` — one `questions` query
   per section.
2. `AdminRepository.getPaperContent` — the identical pattern, admin-side.
3. `AdminRepository.reorderQuestions` — one `UPDATE` per question (a
   write-side N+1, not a read).

**N+1 ISSUES FIXED: 3** (all of the above — see "FILES CHANGED" and
`docs/PERFORMANCE_AUDIT.md` §8 for exactly what changed in each).

**PAGINATED SCREENS:**
- Admin → Review Questionable Questions (new: keyset pagination, load
  more, pull to refresh)
- Admin → Audit Log (new: keyset pagination, load more, pull to
  refresh — previously a flat, un-paginated top-100)
- Search (new: offset-based "load more" — previously a flat top-50)

**Deliberately NOT paginated** (and why): the public/admin papers lists
(≤24 rows, structurally) and a single paper's question list (bounded by
what a real exam paper contains; the N+1 fix already collapsed its
network cost to two flat queries) — see `docs/PERFORMANCE_AUDIT.md` §5/§8.

**DATABASE INDEXES ADDED:**
- `idx_audit_logs_created_at` (desc) — supports the Audit Log's new
  keyset pagination.
- `idx_questions_created_at` (desc) — supports the Review Questionable
  Questions screen's new keyset pagination.

Everything else (`papers`/`paper_sections`/`questions`/`question_options`/
`bookmarks`/`practice_attempts`/`practice_answers`/`user_progress`
columns actually used in `where`/`order by` clauses, plus the two
trigram search indexes) was already indexed by `005_indexes.sql` — this
audit reviewed that file and found it already thorough for its scope.

## DATABASE MIGRATIONS

`supabase/migrations/009_performance_indexes_and_rpcs.sql` (new):
- The two indexes above.
- `admin_dashboard_stats()` — one SQL function returning a single
  `jsonb` object with every dashboard count, computed server-side,
  replacing 5 separate full-row-pulling queries. `security invoker`
  (existing "admin read all" RLS still applies per-count).
- `admin_reorder_questions(uuid[], integer[], integer[])` — one atomic
  `update ... from unnest(...)` replacing N per-question updates.
  `security invoker` (existing "questions: admin write" RLS still
  applies; the existing row-level verification-invalidation trigger
  still fires once per updated row, so a reorder still correctly demotes
  a VERIFIED/PUBLISHED paper — unchanged behavior, fewer round trips).

## FILES CHANGED

**New:**
- `supabase/migrations/009_performance_indexes_and_rpcs.sql`
- `lib/core/pagination/paginated_result.dart`
- `lib/core/pagination/pagination_state.dart`
- `lib/core/pagination/pagination_notifier.dart`
- `test/unit/pagination_notifier_test.dart`
- `docs/PERFORMANCE_AUDIT.md`

**Modified:**
- `lib/data/repositories/paper_repository.dart` — N+1 fix in
  `getSectionsWithQuestions`.
- `lib/data/repositories/admin_repository.dart` — N+1 fix in
  `getPaperContent`; `reorderQuestions` now calls the new RPC;
  `getDashboardStats` now calls the new RPC; `getQuestionableQuestions`
  replaced by keyset-paginated `getQuestionableQuestionsPage`;
  `getRecentAuditLogs` replaced by keyset-paginated `getAuditLogsPage`.
- `lib/data/repositories/search_repository.dart` — `search()` now takes
  `offset`/`limit` and returns a `PaginatedResult`.
- `lib/features/admin/admin_providers.dart` — new
  `AdminQuestionableQuestionsNotifier`/`adminQuestionableQuestionsProvider`
  (paginated); documented why `adminAllPapersProvider` stays unpaginated.
- `lib/features/admin/admin_review_screen.dart` — converted to the
  paginated provider, with scroll-triggered load-more and pull-to-refresh.
- `lib/features/admin/admin_audit_log_screen.dart` — new
  `AdminAuditLogNotifier`/`adminAuditLogProvider` (paginated); screen
  converted the same way.
- `lib/features/search/search_screen.dart` — added offset-based
  scroll-triggered load-more, guarded against concurrent calls.
- `docs/PRODUCTION_FEATURE_AUDIT.md` — "Performance" section updated
  from PARTIALLY COMPLETED to COMPLETED (with the one honest gap: no
  live-database verification).

## RLS/SECURITY IMPACT

**No RLS policy was weakened, bypassed, or reordered — actual result,
not a claim of live verification (none was possible in this sandbox):**

- Both new RPCs run `security invoker`, matching the existing choice for
  `admin_transition_paper_status` (`006_admin_workflow.sql`) — the
  calling user's own permissions apply, so the existing "admin read all"
  / "admin write" RLS policies on `papers`/`questions`/`profiles` still
  gate everything exactly as before. A non-admin calling
  `admin_dashboard_stats()` gets counts scoped to what they can already
  read (published-only); a non-admin calling `admin_reorder_questions`
  updates zero rows — same outcome as the code it replaced.
- The new keyset-pagination queries are plain `select()` calls through
  the same client and the same RLS policies — pagination changes how
  many rows come back per call, never which rows a caller is allowed to
  see. `audit_logs` is still admin-read-only.
- `MISSING_SOURCE`/`NEEDS_REVIEW` remain UI-derived labels, never stored
  statuses; nothing here touches `content_status` values or the
  `papers: public read published` policy.
- **Not verified live** (no Supabase project in this sandbox): that a
  genuine non-admin JWT calling either new RPC actually gets the
  RLS-scoped result described above, and that the new indexes are
  actually chosen by Postgres's query planner (`EXPLAIN ANALYZE`). Both
  are asserted from reading the migration SQL and the RLS policies it
  relies on — the same standard applied to every prior RLS claim in this
  project.

## TEST RESULTS

### flutter analyze

```
10 issues found.
```

Same 10 pre-existing `info`-level deprecation notices as every prior
session — **zero errors, zero warnings**, including across every file
touched this pass.

### flutter test

```
139 tests, all passing (0 failures)
```

131 carried over, plus 8 new in `test/unit/pagination_notifier_test.dart`
(a fake in-memory paginated source, no network): first page, next page
+ last page (fetching stops once `hasMore` is false, no duplicate
fetch), an empty first page (not an error), a `loadMore` already in
flight blocking a second concurrent call, concurrent `loadFirstPage`
calls sharing one in-flight request instead of double-fetching, a failed
first-page load surfacing an error and recovering on `refresh`, a failed
`loadMore` leaving already-loaded items untouched, and `refresh`
re-fetching from the start after pages were already loaded.

No existing test was modified or removed; all 131 prior tests pass
unchanged.

### scripts/validate_content.dart

```
No content files found under content. This is expected until verified
source papers are supplied — nothing to validate.
MISSING SOURCE PAPER — DO NOT PUBLISH.
```

Exit code 0. Unrelated to this pass, re-run to confirm it is still clean.

### Post-implementation scan

Grepped every file touched this pass for
`TODO|FIXME|stub|placeholder|not implemented|lorem ipsum|sample
question|demo paper|fake` — **zero matches**. No fake exam content, no
fabricated years/dates/marks, was introduced anywhere in this pass.

### Android build

**Not attempted, per explicit instruction not to pretend.** Unchanged
from every prior session — no Android SDK in this sandbox, and a prior
attempt to install one was blocked by the egress proxy. This pass
touches no Android configuration.

## REMAINING PERFORMANCE ISSUES

1. **Live database verification is not possible in this sandbox** — no
   Supabase project exists here. Round-trip counts, `EXPLAIN`-confirmed
   index usage, and RPC/RLS behavior under a real JWT are all asserted
   from code/migration review, not an executed run. See
   `docs/PERFORMANCE_AUDIT.md` §10.
2. **Real Phase II/III/IV source papers are still missing** — nothing
   fabricated this session either; every phase/subject slot remains
   Missing Source.
3. **Android AAB build remains unverified** — no Android SDK reachable
   in this sandbox.
4. **A single paper's question list has no pagination by design** (see
   "Deliberately NOT paginated" above) — revisit only if a real paper
   ever turns out to have an unusually large question count in practice.
5. Everything else the requesting brief listed as "after N+1/pagination"
   (VERIFIED_ANSWER production workflow, real content import readiness,
   live RLS/security testing, further PDF/download QA, Play Store
   release prep) was **not** started this pass — this pass was scoped
   entirely to N+1/pagination/database hardening per the stated priority.

**REAL SOURCE PAPERS ARE STILL REQUIRED. NO EXAM CONTENT WAS FABRICATED.**
