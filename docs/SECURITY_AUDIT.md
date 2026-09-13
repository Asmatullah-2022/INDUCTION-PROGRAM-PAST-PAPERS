# Security Audit

Classification per area: **PASS** (verified by code/migration review),
**WARNING** (works but has a caveat worth knowing), **CRITICAL** (none
found). Everything here is a code-review finding, not a live penetration
test — this sandbox has no live Supabase project, so nothing below is
claimed as having been exercised against a real backend. See
`docs/PROJECT_AUDIT.md` for the wider architecture narrative this audit
sits inside.

## Supabase RLS

| Table | Status | Note |
|---|---|---|
| `phases`, `subjects` | PASS | Public read only when `is_active = true`; admin-only write. |
| `papers` | PASS | Public read only `content_status = 'PUBLISHED'`; admin read-all/write-all. `MISSING_SOURCE`/`NEEDS_REVIEW` are UI-derived, never stored, so there is no status value a policy could leak by name. |
| `paper_sections`, `questions`, `question_options` | PASS | Public read only via an `exists(...)` join back to a `PUBLISHED` paper; admin read-all/write-all. |
| `bookmarks`, `practice_attempts`, `practice_answers`, `user_progress` | PASS | Owner-only (`auth.uid() = user_id`, or via parent for `practice_answers`). |
| `profiles` | PASS | Read/update own row; admin read-all. `is_admin` cannot be self-escalated — enforced by `prevent_self_admin_escalation`, a trigger, not RLS `with check` alone (RLS can't compare against the pre-update value of the same row). |
| `app_settings` | PASS | Public read (by design — these are non-sensitive tunables like AI rate limits, never secrets), admin-only write. |
| `audit_logs` | PASS | Admin-read-only, admin-insert-only. Never exposed to normal users. |
| `ai_conversations`, `ai_messages` | PASS | Owner-only (direct `user_id`, or via parent conversation for messages). |
| `ai_usage_daily` | PASS | Read-own only, **no insert/update policy for authenticated users at all** — only the Edge Function's service-role client can write it, so a user cannot inflate or reset their own quota. |

**BLOCKED — LIVE TEST REQUIRED**: none of the above have been executed
against a live Supabase project with real anonymous/authenticated/admin
JWTs — see "RLS test preparation" below and `docs/
LIVE_SUPABASE_TEST_PLAN.md` for the exact tests to run once one exists.

## Authentication

- PASS — `AuthRepository` only ever uses `supabase_flutter`'s own
  session management; no custom token handling, no credential storage
  outside the SDK's own secure session persistence.
- PASS — Account deletion goes through the `delete-account` Edge
  Function; the service-role key it needs lives only in that function's
  server environment, never in the Flutter app.
- PASS — Password-reset deep link (`AndroidManifest.xml`) uses a private
  URL scheme (`com.asmatullahkhan.inductionprogrampastpapers://
  reset-password`) rather than an `https` App Link, so there's no
  `assetlinks.json`/domain-verification surface to misconfigure; the
  tradeoff (any app could in principle register the same custom scheme)
  is a WARNING common to this pattern, not specific to a mistake here —
  moving to a verified `https` App Link is the standard hardening step
  if this becomes a concern.

## Admin authorization

- PASS — every admin write is enforced by `profiles.is_admin = true` at
  the RLS layer (`002_rls.sql`), not by `AdminGuard` (a UX convenience —
  explicitly documented as such in `CLAUDE.md`). A non-admin calling any
  `AdminRepository` method directly (bypassing the Flutter UI entirely)
  would still be rejected server-side.
- PASS — paper status transitions and the critical-error publish gate
  are enforced inside `admin_transition_paper_status`/
  `paper_has_critical_errors` (`006_admin_workflow.sql`), not just by the
  Flutter UI's mirrored `PaperQualityChecker` — a client bypassing the
  UI cannot force an illegal transition or publish content with
  unresolved critical errors.
- PASS — the two new RPCs added for performance
  (`admin_dashboard_stats`, `admin_reorder_questions`,
  `009_performance_indexes_and_rpcs.sql`) both run `security invoker`,
  so the same RLS policies gate a non-admin caller exactly as before
  (zero rows updated / published-only counts) — see
  `docs/PERFORMANCE_AUDIT.md` §9 for detail.

## Storage policies

- PASS — original paper files live in the `original-papers` Storage
  bucket, uploaded only through `AdminRepository.uploadOriginalPaperFile`
  (admin-write RLS-gated the same way as any other admin content write).
  The resulting URL is a public read URL by design (original papers are
  meant to be publicly viewable once the paper is published) — this is
  intentional, not a leak: the same content is already public through
  the `papers`/`paper_sections`/`questions` read policies once
  `content_status = 'PUBLISHED'`.

## Edge Functions

| Function | Status | Note |
|---|---|---|
| `delete-account` | PASS | Service-role key used only inside the function's own server environment; authenticates the caller before deleting. |
| `ai-teacher` | PASS | Authenticates via the caller's own JWT before anything else (401 otherwise); validates action/message shape and length; rate-limits via a service-role client used **only** for the `ai_usage_daily` counter (which itself has no client write policy); fetches verified question context through the caller's own JWT-scoped client (RLS-gated to PUBLISHED papers for non-admins) rather than the service-role client; never returns raw provider error text/model name/credentials to the client. |

## AI endpoints / secrets

- PASS — `ANTHROPIC_API_KEY`, `AI_PROVIDER`, `AI_MODEL` are Edge
  Function secrets only. Grepped the repository for `sk-ant`,
  `ANTHROPIC_API_KEY\s*=\s*['"a-zA-Z0-9]`, and `service_role` — no real
  secret value appears anywhere under `lib/`, `supabase/`, or any
  committed doc (only variable-name references and the literal
  placeholder `sk-ant-...` in setup instructions).
- PASS — the Flutter app never imports a provider SDK/type; it only
  calls `SupabaseService.client.functions.invoke('ai-teacher', ...)`.
- PASS — `SUPABASE_SERVICE_ROLE_KEY` is referenced only inside
  `supabase/functions/*/index.ts` (server-side Deno runtime); grepped
  `lib/` for the literal string and found zero matches, confirming
  `CLAUDE.md`'s "Security Rules" constraint holds in the current tree.
- PASS — no secret is logged: the Edge Function's `console.error` on
  failure logs the error object, never the request body, prompt, or
  response content.

## Deep links

- PASS — the only registered deep link (`reset-password`) is
  narrowly scoped to Supabase Auth's password-reset flow; no other
  scheme/host is registered, so there's no broader deep-link attack
  surface (arbitrary navigation, intent injection) to audit.

## Account deletion

- PASS — routed through the `delete-account` Edge Function, not a
  client-side delete call, per `CLAUDE.md` "Security Rules".

## User data access

- PASS — every user-scoped table is read/written only through a
  `user_id`-filtered query on the client side **and** an owner-only RLS
  policy server-side (defense in depth: even a bug in the client-side
  filter cannot leak another user's row, because RLS would reject it).

## Content status leakage

- PASS — `MISSING_SOURCE` and `NEEDS_REVIEW` are UI presentation labels
  only (`PaperStatusPresentation`), derived from `content_status`/
  `source_file_url`, never stored strings. The public read policy checks
  the real stored value (`content_status = 'PUBLISHED'`), so a
  `DRAFT`/`UNDER_REVIEW` paper — regardless of what label the admin UI
  shows for it — can never appear in a normal user's query results.

## Download security

- PASS — the Downloads Manager (`DownloadsService`,
  `lib/features/downloads/`) is not a separate authorization path. Every
  file it saves is either (a) a PDF generated client-side from
  [Question]s the app already fetched under RLS (so if the caller
  couldn't read it, there's nothing to generate a PDF from in the first
  place), or (b) a PUBLISHED paper's own `source_file_url`, itself only
  ever populated for and only ever publicly readable for a published
  paper. `DownloadsService` holds no Supabase credentials, calls no
  privileged endpoint, and cannot itself decide what a user is allowed
  to see — it only persists bytes the rest of the app already
  legitimately obtained.
- PASS — no signed URL was needed: original paper files are intentionally
  public-read once a paper is `PUBLISHED` (see "Storage policies" above),
  so a plain `HttpClient` GET (the same mechanism the original-paper
  viewer already used) is sufficient and adds no new credential surface.
- PASS — downloaded files and their index (`DownloadRecord`s) live only
  in the device's own local app-documents directory and local
  SharedPreferences — never uploaded anywhere, never visible to any
  other user or admin.
- PASS — account deletion now also clears all downloaded files and the
  local cache (`AuthRepository.deleteAccount` → `DownloadsService.
  clearAll()`/`CacheService.clearAll()`), so nothing tied to a deleted
  account lingers on the device.

## RLS test preparation

Because no live Supabase project exists in this sandbox, the tests below
are **BLOCKED — LIVE TEST REQUIRED**, not performed — this is the exact
test plan for whoever has access to a real project to execute, per
role. See `docs/LIVE_SUPABASE_TEST_PLAN.md` for the full, expanded
per-area test matrix (including admin CRUD, answer verification, and
Storage access); the table below is the short summary.

| Role | Must be able to | Must NOT be able to |
|---|---|---|
| Anonymous (no session) | Nothing — every table requires at least an authenticated read for public content in this schema's current policies (re-check `phases`/`subjects`/`papers`/`paper_sections`/`questions`/`question_options`'s `for select` clauses use `using (...)` without an `auth.uid()` check, so confirm whether an anon key alone can read `PUBLISHED` content — this is expected/intended for a public browsing app, verify it isn't accidentally broader). | Read any `DRAFT`/`UNDER_REVIEW`/`VERIFIED`/`ARCHIVED` paper's content; read `audit_logs`; read another identity's `bookmarks`/`practice_attempts`/`user_progress`/`ai_conversations`. |
| Authenticated non-admin (teacher/aspirant/student — the app has no role distinction beyond `is_admin`) | Read `PUBLISHED` content; manage only their own `bookmarks`/`practice_attempts`/`practice_answers`/`user_progress`/`ai_conversations`/`ai_messages`; read their own `profiles` row and `ai_usage_daily` row. | Read/write any other user's rows in any of those tables; read `DRAFT`/`UNDER_REVIEW`/`VERIFIED`/`ARCHIVED` papers or their sections/questions/options; write to `papers`/`paper_sections`/`questions`/`question_options`/`phases`/`subjects`/`app_settings`; read/write `audit_logs`; write their own `ai_usage_daily` row directly; set `profiles.is_admin = true` on their own row. |
| Admin (`profiles.is_admin = true`) | Everything a non-admin can, plus: read/write all papers regardless of status; read/write sections/questions/options; call `admin_transition_paper_status`/`admin_reorder_questions`/`admin_dashboard_stats`; read `audit_logs`; write `app_settings`. | Self-escalate another admin flag maliciously (n/a — escalation protection is about *any* user, admin included, not being able to grant themselves admin via a path other than another admin's explicit action); bypass the critical-error publish gate (attempting to verify/publish a paper with unresolved critical errors via `admin_transition_paper_status` directly, not just through the UI, must still fail). |
| Storage (`original-papers` bucket) | Any authenticated request may read a published paper's file (public URL by design). Only admin may upload/overwrite. | A non-admin overwriting/deleting an original paper file. |

Suggested execution method once a project exists: `supabase` CLI's local
Postgres + `psql` with `set role authenticated; set request.jwt.claims =
'{"sub": "<test-user-uuid>"}';` per row above, or Supabase's own RLS
testing guidance (`supabase test db`) — either way, run each "must NOT"
row and confirm zero rows / a permission error, not just "no crash".

## Summary

**0 CRITICAL findings.** All WARNING items are either inherent tradeoffs
of a pattern already in use (custom-scheme deep link) or a testing gap
this sandbox cannot close (no live Supabase project) — neither is a
defect introduced by this pass.
