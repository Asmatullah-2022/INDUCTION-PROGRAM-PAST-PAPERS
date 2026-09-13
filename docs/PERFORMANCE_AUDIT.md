# Performance Audit — N+1 Queries, Pagination, Database Hardening

An audit of every place the app loads phases/subjects/papers/sections/
questions/answers/bookmarks/practice questions/search results/admin
content/dashboard statistics, followed by the fixes actually implemented.
See `docs/PROJECT_AUDIT.md` for the wider architecture/security narrative
and `docs/PRODUCTION_FEATURE_AUDIT.md` for feature-completeness.

**A structural fact that shapes almost every decision below**: `papers`
has a `unique (phase_id, subject_id)` constraint and there are exactly 3
phases × 8 subjects (`CLAUDE.md` "Database Rules") — so the entire
`papers` table can never exceed **24 rows**, ever, by design. `phases`
(3) and `subjects` (8) are smaller still. Server-side pagination for
those three tables would add real complexity for zero real benefit, so
it was deliberately **not** added — see "Deliberately not paginated"
below. The tables that *do* grow unboundedly are `questions` (real exam
content, potentially hundreds of rows per paper across many papers),
`audit_logs` (one row per admin write, forever), and `profiles` (one row
per signed-up user) — the fixes below concentrate there.

## 1. Existing query flow (as found)

| Screen / flow | Repository method | Query shape |
|---|---|---|
| Subject → Papers list | `PaperRepository.getPapersForSubject` | 1 query, filtered to `PUBLISHED`, cached |
| Paper → Complete Solved Paper | `PaperRepository.getSectionsWithQuestions` | 1 query for sections, then **1 query per section** for questions (N+1) |
| Admin → Paper Review / quality check | `AdminRepository.getPaperContent` | Same N+1 shape as above, admin-side |
| Admin → all papers | `AdminRepository.getAllPapers` | 1 query, unfiltered (admin sees all statuses) — capped at 24 rows regardless |
| Admin → Section Editor reorder | `AdminRepository.reorderQuestions` | **1 UPDATE per question** in the reordered list (N round trips) |
| Admin → Dashboard | `AdminRepository.getDashboardStats` | **5 separate queries**, each pulling every matching row's full selected columns to the client just to `.length`/loop-count them in Dart |
| Admin → Review Questionable Questions | `AdminRepository.getQuestionableQuestions` | 1 query, **no limit at all** — every non-VERIFIED question in the database, unconditionally |
| Admin → Audit Log | `AdminRepository.getRecentAuditLogs` | 1 query, flat `limit(100)` — no way to see anything older than the most recent 100 actions, ever |
| Search | `SearchRepository.search` | 1 query, server-side `ilike` + join filter (already correct — see below), flat `limit(50)` |
| Practice mode | `PracticeRepository.getPracticeQuestions` | 1 query (server-filtered by phase/subject/PUBLISHED), shuffled/limited client-side after fetch |
| Bookmarks / Progress / Practice attempts | `BookmarkRepository` / `ProgressRepository` / `PracticeRepository` | Each is 1 query per operation, always scoped to the signed-in user (`user_id` filter, indexed) — no N+1, no unbounded growth per user |

## 2. N+1 queries found

1. **`PaperRepository.getSectionsWithQuestions`** — looped over every
   section of a paper and issued one `questions` query per section. A
   paper with 5 sections meant 6 round trips (1 + 5) to render the
   Complete Solved Paper screen.
2. **`AdminRepository.getPaperContent`** — the identical pattern,
   admin-side (Paper Review screen, `PaperQualityChecker`'s data source).
3. **`AdminRepository.reorderQuestions`** — not a *read* N+1, but the
   same shape on the write side: one `UPDATE` per question in the
   reordered section. Reordering a 30-question section meant 30 round
   trips.

No other per-record query-in-a-loop pattern was found. Every other
repository method either does a single filtered `select()` or a single
row-scoped write.

## 3. Queries already optimized (found, not changed)

- **Search** (`SearchRepository.search`) already runs entirely
  server-side: the `PUBLISHED`-only filter and the `ilike` text match
  both execute in Postgres via one `select()` with a nested
  `paper_sections!inner(...papers!inner(...))` filter — it was never
  downloading the question table and filtering it in Flutter. Backed by
  the `gin_trgm_ops` indexes already added in `005_indexes.sql`
  (`idx_questions_text_trgm`, `idx_questions_explanation_trgm`).
- **`PracticeRepository.getPracticeQuestions`** filters phase/subject/
  `PUBLISHED` server-side via the same nested-join pattern; only the
  final "which N of the matching MCQs" shuffle happens client-side,
  which is inherent to a random-practice-set feature, not a query
  inefficiency.
- **`PaperRepository.getPapersForSubject`** was already narrowly
  filtered (phase + subject + `PUBLISHED`) and cache-backed
  (`CacheService`), so a repeat visit doesn't re-hit the network at all
  until the cache is invalidated.
- Every user-scoped table (`bookmarks`, `practice_attempts`,
  `practice_answers`, `user_progress`) was already queried with an
  indexed `user_id` filter and no N+1 shape.

## 4. Missing indexes (found)

`005_indexes.sql` already covers `papers` (phase/subject/status,
composite), `paper_sections.paper_id`, `questions.paper_section_id`/
`question_type`/`quality_status`, `question_options.question_id`,
`bookmarks.user_id`(+target), `practice_attempts.user_id`,
`practice_answers.attempt_id`, `user_progress.user_id`, and the two
trigram indexes for search — this was a thorough pass already. What it
did **not** cover, because these access patterns didn't exist yet at the
time:

- `audit_logs.created_at` — needed for keyset pagination (`order by
  created_at desc` + `where created_at < :cursor`) once the Audit Log
  screen stopped being a flat top-100.
- `questions.created_at` — same reason, for the Review Questionable
  Questions screen's keyset pagination.

Added in `009_performance_indexes_and_rpcs.sql` — see "Changes actually
implemented" below.

**Deliberately not indexed further**: `profiles.is_admin` (the table is
one row per user; `is_admin()` already resolves via the primary key
`id`), and no column on `phases`/`subjects` (8 and 3 rows respectively —
a sequential scan of either is never measurably slower than an index
lookup).

## 5. Missing pagination (found)

- **Review Questionable Questions** — no limit at all. Fixed.
- **Audit Log** — a flat `limit(100)` with no way to page past it. Fixed.
- **Search** — a flat `limit(50)` with no "load more". Fixed (offset-based).
- **Papers lists (public and admin)** — no pagination, and **deliberately
  left that way** — see "Deliberately not paginated" below.
- **Questions within one paper** (Answer Key / Short / Long / Complete
  Solved Paper screens) — no pagination, and **deliberately left that
  way** — a single past paper realistically has tens of questions, not
  thousands; `ListView.builder` already virtualizes the rendered widgets
  regardless, and the N+1 fix in §2 already collapsed the network cost
  to two flat queries per paper. Adding cursor pagination to a
  single-paper fetch would add complexity (a "load more" mid-paper is
  also a poor reading experience for an exam paper) without a real
  performance problem to solve. If a genuinely huge paper ever
  materializes, this is the first place to revisit.

## 6. Expensive queries (found)

- **`AdminRepository.getDashboardStats`** was the most expensive query
  path in the app: 5 separate round trips, each transferring every
  matching row's selected columns to the client only to `.length`/loop
  them into a count in Dart. On an empty/small database this is
  invisible; with real content (hundreds of questions, many users) it
  means transferring hundreds of rows just to produce ~19 integers.
  Fixed via a single aggregating RPC — see below.

## 7. Recommended changes

1. Batch the sections→questions fetch into two flat queries (`inFilter`
   over all section ids) instead of one query per section.
2. Batch the question-reorder write into one atomic RPC instead of N
   updates.
3. Replace the 5-query, full-row-pulling dashboard stats with one RPC
   that returns only the aggregate counts.
4. Add keyset pagination (cursor = last row's `created_at`) to the two
   unboundedly-growing admin lists (Audit Log, Review Questionable
   Questions) and to Search (offset-based, since search ranking has no
   stable time-ordering to key off).
5. Add the two missing indexes those keyset queries actually use.
6. Introduce one small, reusable pagination core
   (`lib/core/pagination/`) instead of hand-rolling loading/error/
   duplicate-prevention state three separate times.
7. Do **not** add pagination to the papers list or to a single paper's
   question list — see §5.
8. Do **not** weaken any RLS policy to make any of the above faster —
   every fix below runs through the exact same RLS the app already had
   (see "RLS/security impact").

## 8. Changes actually implemented

### Database — `supabase/migrations/009_performance_indexes_and_rpcs.sql`

- `idx_audit_logs_created_at` and `idx_questions_created_at` (both
  `desc`), supporting the new keyset-pagination queries.
- `admin_dashboard_stats()` — one SQL function returning a single
  `jsonb` object with all ~19 counts, computed server-side. Runs
  `security invoker`, so the existing "admin read all" RLS policies on
  `papers`/`questions`/`profiles` still gate what each count actually
  sees (see "RLS/security impact").
- `admin_reorder_questions(uuid[], integer[], integer[])` — one
  `update ... from unnest(...)` statement that updates every reordered
  question's `question_number`/`display_order` in a single atomic
  statement. Also `security invoker`, so "questions: admin write" RLS
  still applies row-by-row exactly as before; the existing
  `invalidate_verification_on_content_change` row-level trigger still
  fires once per updated row, so a reorder still correctly demotes a
  VERIFIED/PUBLISHED paper to UNDER_REVIEW.

### Repository fixes

- `PaperRepository.getSectionsWithQuestions` and
  `AdminRepository.getPaperContent` — sections fetched once, then every
  section's questions fetched in **one** `inFilter('paper_section_id',
  [...])` query and grouped in Dart, instead of one query per section.
- `AdminRepository.reorderQuestions` — calls `admin_reorder_questions`
  once instead of looping `update()` per question.
- `AdminRepository.getDashboardStats` — calls `admin_dashboard_stats()`
  once and maps its `jsonb` result onto the existing, unchanged
  `AdminDashboardStats` model (no model or caller-facing shape change).
- `AdminRepository.getQuestionableQuestionsPage` /
  `AdminRepository.getAuditLogsPage` (new, replacing the old unbounded/
  flat-100 methods) — keyset pagination via `created_at`, fetching
  `limit + 1` rows to determine `hasMore` without a separate `count`
  query (the "N+1 rows" technique — one query answers both "here's the
  page" and "is there another page").
- `SearchRepository.search` — now takes `offset`/`limit` and returns a
  `PaginatedResult`, using the same `limit + 1` technique, so a "load
  more" fetches only the next page instead of re-running the whole query
  with an ever-larger limit.

### New pure-Dart pagination core — `lib/core/pagination/`

- `PaginatedResult<T>` — one fetched page: items, `hasMore`, and an
  opaque `nextCursor` string the caller passes back unmodified.
- `PaginationState<T>` — items so far, `isLoading` (first page) /
  `isLoadingMore` (next page) / `hasMore` / `error`, immutable.
- `PaginationNotifier<T>` — a Riverpod `Notifier<PaginationState<T>>`
  base class implementing `loadFirstPage`/`loadMore`/`refresh` once:
  auto-loads on `build()`, de-duplicates concurrent calls (an in-flight
  first-page future is shared rather than re-fetched; `loadMore` is a
  no-op while already loading or once `hasMore` is false), and never
  duplicates or drops items across pages. Concrete screens only
  implement `fetchPage(cursor, limit)` against their own repository —
  see `AdminQuestionableQuestionsNotifier` (`admin_providers.dart`) and
  `AdminAuditLogNotifier` (`admin_audit_log_screen.dart`).

### UI

- **Review Questionable Questions** and **Audit Log** screens: converted
  from a single `FutureProvider<List<T>>` to the paginated
  `NotifierProvider`/`PaginationState<T>` pair above — a scroll listener
  triggers `loadMore()` near the bottom, `RefreshIndicator` triggers
  `refresh()`, and a trailing spinner shows while `isLoadingMore`.
- **Search screen**: added a scroll-triggered `_loadMore()` using the
  new offset-based `search()`, guarded against concurrent calls
  (`if (_isLoadingMore || !_hasMore) return;`), appending results
  instead of duplicating them.
- **Papers list, admin papers list, single-paper question screens**: left
  as flat, unpaginated fetches — see §5 for why.

### Deliberately not paginated

Restating §5/§1's reasoning in one place, since it's the single biggest
scope decision in this audit: `phases` (3), `subjects` (8), and `papers`
(≤24, structurally) are small enough that "load everything" is the
*correct*, not merely acceptable, choice — the "first page loads
quickly, skeleton loading, pull to refresh, load more" requirements in
a typical performance brief exist to solve a problem this schema cannot
have. Building that machinery here would be complexity added for a
scenario the product's own database constraints (`CLAUDE.md` "Database
Rules") guarantee will never occur.

## 9. RLS/security impact

**No RLS policy was weakened, bypassed, or reordered.** Specifically:

- `admin_dashboard_stats()` and `admin_reorder_questions(...)` both run
  `security invoker` (the calling user's own permissions), the same
  choice already made for `admin_transition_paper_status` in
  `006_admin_workflow.sql` — so every existing "admin read all" / "admin
  write" policy on `papers`/`questions`/`profiles` still applies exactly
  as before. A non-admin calling `admin_dashboard_stats()` gets counts
  scoped to what they're allowed to read (i.e. published-only content),
  never a bypass that reveals draft/unpublished counts; a non-admin
  calling `admin_reorder_questions(...)` updates zero rows, exactly as
  the old per-row-update code already did.
- The keyset-pagination queries (`getAuditLogsPage`,
  `getQuestionableQuestionsPage`) are plain `select()` calls through the
  same client and the same RLS policies as before — `audit_logs` is
  still admin-read-only, `questions` still resolves through the existing
  "admin read all" / "public read for published papers" policies.
  Pagination only changes how many rows come back per call, never which
  rows a given caller is allowed to see.
- `MISSING_SOURCE` and `NEEDS_REVIEW` are UI-derived labels, not stored
  statuses (see `CLAUDE.md`) — nothing in this pass touches
  `content_status` values or the `papers: public read published` policy
  that keeps non-`PUBLISHED` papers out of any public-facing list.

**Not verified live** (no Supabase project in this sandbox): that
`admin_dashboard_stats()` and `admin_reorder_questions(...)` actually
produce zero-row/RLS-scoped results for a genuine non-admin JWT, and
that the new indexes are actually used by Postgres's query planner for
the keyset queries (`EXPLAIN`-verified). Both are asserted from reading
the migration SQL and the existing RLS policies it relies on, consistent
with every other RLS claim already documented in this project.

## 10. Test results

### flutter analyze

0 errors (10 pre-existing `info`-level notices, unchanged).

### flutter test

All tests passing, including 8 new tests in
`test/unit/pagination_notifier_test.dart` covering: first page, next
page, last page, empty result, concurrent `loadMore` prevention,
concurrent `loadFirstPage` prevention (deduped, not double-fetched),
error recovery on both first-page and load-more failures, and refresh
re-fetching from the start. These test the pure pagination *logic*
against a fake, in-memory paginated source — see the limitation note
below for what they intentionally don't and can't cover.

### What could not be verified without a live Supabase project

- That `getSectionsWithQuestions`/`getPaperContent` actually issue
  exactly 2 network round trips for a real multi-section paper (asserted
  from reading the code — a single `inFilter` query replaces what was a
  loop — not from an observed query count against a live database).
- That `admin_reorder_questions` and `admin_dashboard_stats` actually
  execute as one round trip against a real Postgres instance and return
  the expected shape (the RPC bodies were reviewed for correctness, not
  executed).
- That the new indexes are actually chosen by the query planner
  (`EXPLAIN ANALYZE`) rather than merely existing.
- Genuine RLS enforcement for a non-admin JWT against the two new RPCs.

These are the same category of limitation already documented for every
prior RLS/live-database claim in this project (see `CLAUDE.md` "Testing
Rules" and `docs/FINAL_QA_REPORT.md`) — asserted from code/migration
review, not from an executed run against a live environment.
