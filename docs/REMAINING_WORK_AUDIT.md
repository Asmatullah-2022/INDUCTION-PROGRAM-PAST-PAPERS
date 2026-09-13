# Remaining Work Audit

Classifies every item from the latest production-hardening request
against what this repository actually contains today, after inspecting
`lib/`, `test/`, `android/`, `supabase/`, `scripts/`, `docs/`,
`CLAUDE.md`, `README.md`, and `.env.example`. Labels used throughout:
**COMPLETED**, **PARTIALLY COMPLETED**, **NOT IMPLEMENTED**,
**BLOCKED BY ENVIRONMENT**, **BLOCKED BY REAL SOURCE CONTENT**, and
(new to this pass) **NOT IMPLEMENTED BY DESIGN** — deliberately not
built because it would conflict with `CLAUDE.md`'s own governing rules,
not because it was overlooked.

## 1. Verify current state

COMPLETED — this document is that verification. Prior N+1/pagination
work (`docs/PERFORMANCE_AUDIT.md`) was re-read, not redone: the fixes to
`PaperRepository.getSectionsWithQuestions`, `AdminRepository.
getPaperContent`/`reorderQuestions`/`getDashboardStats`, the two new
admin RPCs, the `lib/core/pagination/` core, and the two new indexes are
all present and their tests (`test/unit/pagination_notifier_test.dart`
plus the full suite) pass.

## 2–4. Verified Answer workflow, Admin Answer Review, Discrepancy system

**NOT IMPLEMENTED BY DESIGN.** See `docs/AI_TEACHER_ARCHITECTURE.md`
"VERIFIED_ANSWER: why this pass did not build an 'AI-answer promotion'
pipeline" for the full reasoning; summary:

- The requested lifecycle (AI-generated → needs review → admin review →
  verified → published, with a new `created_by`/`verified_by`/
  `verified_at`/`source_reference`/`version` schema) would be the first
  path in this codebase by which AI-authored text could become stored
  exam content — directly contradicting `CLAUDE.md`'s "AI Teacher
  Rules" and "Content Rules" (never invent/silently correct content;
  the AI Teacher Edge Function never writes to `questions`/
  `paper_sections`/`question_options`).
- The lifecycle this request describes **already exists**, just not for
  AI-generated content: `questions.quality_status` +
  `questions.verification_status` + `papers.content_status`
  (DRAFT → UNDER_REVIEW → VERIFIED → PUBLISHED, gated server-side by
  `admin_transition_paper_status`), edited via the existing Admin
  Question Form and reviewed via the existing (now paginated) Admin
  Review screen. This is COMPLETED and was not touched this pass because
  it already works and needed no change.
- The "Answer Discrepancy" display this request asks for **already
  exists** too: `QuestionTile._DiscrepancyNotice` shows "⚠ Answer key
  requires review" with the original marked option vs. the verified
  answer side by side whenever `question.hasAnswerKeyDiscrepancy` is
  true (`verification_status == 'PAPER_ANSWER_ERROR'`) — this is the
  same "Source Answer / Suggested Answer / Difference" concept the
  request describes, already COMPLETED, for the one place a discrepancy
  can genuinely arise in this schema (the original paper's own ticked
  answer vs. the independently verified one).

**If a future decision is made to let AI Teacher content feed into
verified answers**, that is a product/architecture decision requiring
explicit discussion first (same standard `CLAUDE.md` already applies to
widening any status enum) — not something to implement unilaterally in
a single pass, and this audit deliberately did not attempt it.

## 5. AI Teacher production hardening

**COMPLETED** for everything that doesn't require a live provider/
Supabase project. Capability checklist against the request:

| Requested capability | Status |
|---|---|
| Chat, Ask, Explain Simply, Urdu, Examples, Exam Tips, Similar Questions, Generate Quiz, Explain MCQ, Why correct/why others wrong | COMPLETED — all are `AiTeacherAction` values with dedicated quick-action buttons. |
| Mathematics step-by-step | COMPLETED — system prompt rule 11 (Given/Required/Formula/Step-by-Step/Final Answer/Exam Tip). |
| Pedagogy, educational psychology, classroom management, curriculum, ICT in education | COMPLETED via general chat (`ask` action) — these are topics, not distinct app features; the system prompt is a general educational tutor, not scoped to one subject, so no dedicated button was needed or added for each. |
| Verified content as primary context when a question is open | COMPLETED (prior pass) — RLS-gated fetch of the real question/answer, injected as "VERIFIED CONTEXT" the model is instructed never to contradict. |
| Explicit VERIFIED/AI-GENERATED labels | COMPLETED — `content_kind` → `AiContentKindX.label`, five exact values including the newer `AI_GENERATED_PRACTICE`. |
| Uncertainty phrasing | COMPLETED — system prompt rule 9, verbatim the requested sentence. |

See `docs/AI_TEACHER_ARCHITECTURE.md` for what changed vs. was
deliberately not changed this pass (streaming, stop-generation
semantics, VERIFIED_ANSWER).

## 6. AI security

COMPLETED — re-verified, not rebuilt. See `docs/SECURITY_AUDIT.md`
"Edge Functions" / "AI endpoints / secrets": no provider key in Flutter,
no secret committed, auth required before any AI Teacher work happens,
rate limiting + prompt/output/timeout limits enforced server-side,
generic error mapping (no internals leaked).

## 7. AI Stop Generation

**COMPLETED as client-side abandonment; explicitly NOT a true
server-side cancellation**, and documented as such rather than claimed
otherwise — see `docs/AI_TEACHER_ARCHITECTURE.md` "Stop Generation" for
exactly why (the transport, `functions.invoke`, has no cancellation
hook) and what a true abort would require. Duplicate-request and
stale-response prevention were verified still correct (generation
counter guards both). Tests already exist for: cancel during generation
(`... stop generation ...` in `ai_teacher_screen_test.dart`), retry,
failed request. **New this pass**: none added — the existing coverage
already exercises cancel/retry/failure; a genuine "timeout" test would
require controlling wall-clock time inside the fake repository, which
existing tests don't need since the fake never really blocks except via
the `Completer`-based gate already used for the loading-state test —
timeout behavior itself lives entirely server-side (`AbortController` in
the Edge Function) and is not independently observable from Flutter,
so there is nothing further to unit test here client-side beyond what
already exists.

## 8. Response streaming

**NOT IMPLEMENTED — evaluated and documented, not faked.** See
`docs/AI_TEACHER_ARCHITECTURE.md` "Response streaming — evaluated, not
implemented" for the full reasoning: the provider and the Edge Function
layer both support it; the blocker is `supabase_flutter`'s
`functions.invoke` having no chunked-read API, and rewriting the
transport layer to a raw HTTP stream is a bigger, unverifiable-in-this-
sandbox change than this pass's scope justifies without live-environment
validation.

## 9. New Conversation / Clear Chat

COMPLETED (prior pass) — already two separate actions with distinct
semantics and existing tests. Re-verified this pass, not re-implemented.

## 10. AI Chat History

COMPLETED (prior pass) — `AiTeacherHistoryScreen`, owner-only RLS on
`ai_conversations`/`ai_messages`, delete-conversation support. Re-
verified, not re-implemented.

## 11. Content Management finalization

COMPLETED for everything listed except real content: Create
Phase/Subject/Paper/Section/Question/Answer, upload PDF/images, create
sections/questions/answers, edit questions/answers, run
validation/quality check, submit for review, verify, publish, unpublish,
archive — all exist in `AdminRepository`/`lib/features/admin/`. Preview
pages for a scanned original: the original-paper viewer
(`original_paper_viewer_screen.dart`, using `pdfx`/`photo_view`) already
renders the uploaded source file; there is no separate "multi-page
scan preview during upload" step because upload is a single
file (PDF or one image) per paper, not a multi-page scan-assembly
workflow — if papers are later supplied as multiple separate page
images needing to be merged/ordered before upload, that assembly step
does not exist yet and would be new work, tracked as
**BLOCKED BY REAL SOURCE CONTENT** until real scans reveal whether it's
actually needed.

## 12. Quality Check finalization

COMPLETED — `PaperQualityChecker`/`QuestionValidation`/
`QuestionNumberingValidator`/`ContentImportValidator` (client) and
`paper_has_critical_errors` (server, `006_admin_workflow.sql`) already
cover: missing/duplicate/gapped question numbers, missing MCQ
options/invalid correct option, empty question text/answer, empty
sections, quality-note requirement for non-VERIFIED status, and the
critical-error publish gate. A numeric 0–100 score with PASS/WARNING/
ERROR severity already exists (`PaperQualityChecker`'s score/category).
**Not present and not added this pass** (all genuinely require real
content to be meaningful, not just possible to code against a schema
that has none yet): duplicate-*question-text* detection (vs. duplicate
*numbers*, which is covered), marks-mismatch/total-marks-mismatch
cross-checking against a paper's declared total, OCR-corruption/
suspicious-character detection, missing-pages/page-order checks. These
are **BLOCKED BY REAL SOURCE CONTENT** in the sense that building and
tuning a real OCR-artifact/marks-mismatch detector against zero actual
transcribed papers risks encoding guesses as rules; flagged here as
explicitly deferred, not silently dropped.

## 13. Real paper safety

COMPLETED (anti-fabrication rules unchanged and re-affirmed) +
`docs/CONTENT_IMPORT_GUIDE.md` extended this pass with the
`content/source/phase_ii|iii|iv/` convention and an honest statement
that OCR is currently a manual step (no OCR script exists in this
repository) rather than a described-but-fictional automated pipeline.

## 14. Public user experience

COMPLETED — browsing by phase/subject, original viewer, answer keys,
solved questions, PDF download, bookmarks, search, practice, AI Teacher
all exist and were reviewed, not rebuilt. `MISSING_SOURCE` papers are
never shown as real content — the subject screen and original-paper
viewer both render the explicit "MISSING SOURCE PAPER — DO NOT PUBLISH"
state instead, and the public RLS policy makes it structurally
impossible for a non-`PUBLISHED` paper to reach a normal user's query
regardless of what the UI does.

## 15. Download system

**COMPLETED this pass** — added a persistent Downloads Manager
(`lib/features/downloads/`, `DownloadsService`) that was the one gap
flagged in the prior pass. Original paper, MCQ answer key, solved
short/long questions, and complete solved paper can now each be saved
to local device storage (not just ephemerally shared), listed on a
dedicated Downloads screen with paper title/phase/subject/document
type/size/date/verification status, and Opened (via `Printing.
layoutPdf`)/Shared (`Share.shareXFiles`)/Deleted. Duplicate-download
prevention is structural: a record's id is `paperId + documentType`, so
re-downloading overwrites in place rather than accumulating entries
(unit-tested in `test/unit/downloads_service_test.dart`). Missing/
corrupted files are detected (`DownloadsService.fileExists`) and shown
as a warning with Open/Share disabled, Delete still available. Only
PUBLISHED-paper content is ever downloadable through the public flow —
see `docs/SECURITY_AUDIT.md` "Download security" for why this was never
a separate authorization path. Account deletion now also clears all
downloaded files. 14 new tests (9 unit + 5 widget).

## 16. PDF generation

COMPLETED — reviewed `PdfExportService`: no year field is ever included
(consistent with the no-year rule), and VERIFIED vs. AI-GENERATED
distinction doesn't arise in generated PDFs today because PDFs are only
generated from the app's own stored `questions`/`verified_answer`/
`explanation` data — there is no path for AI Teacher content to appear
in an exported PDF at all (by the same "AI never writes into
questions" boundary discussed in §2–4), so there's nothing to visually
distinguish there yet.

## 17. Security audit

COMPLETED this pass — see `docs/SECURITY_AUDIT.md` (new). 0 CRITICAL
findings; all WARNING items are inherent tradeoffs or environment-
testing gaps, not defects.

## 18. RLS test preparation

COMPLETED this pass — see `docs/SECURITY_AUDIT.md` "RLS test
preparation" for the full per-role test matrix (anonymous,
authenticated, admin) documented for execution once a live Supabase
project exists. **Not performed** — no live project available, and this
document does not claim otherwise.

## 19. Performance audit (verify, don't rebuild)

COMPLETED (verification only, as instructed) — re-ran `flutter analyze`
(0 errors) and `flutter test` (all passing, including the 8 pagination
tests from the prior pass); re-read `docs/PERFORMANCE_AUDIT.md` and
confirmed the fixes it describes are present in the current tree
(`inFilter` batching, the two RPCs, the pagination core, the two new
indexes). Nothing was rebuilt.

## 20. UI/UX final polish

PARTIALLY COMPLETED — every listed screen already exists, supports
light/dark mode (Material 3 `AppTheme`), and has loading/empty/error/
retry states via the shared `state_widgets.dart` set
(`LoadingList`/`EmptyState`/`ErrorState`) applied consistently across
the screens reviewed this pass (admin lists, search, AI Teacher). Not
independently re-audited pixel-by-pixel for accessibility (contrast
ratios, semantic labels/screen-reader support) — that's a real,
addable pass, not attempted here to avoid a broad, low-confidence "UI
polish" sweep with no concrete finding driving it, consistent with the
brief's own "do not redesign the entire app unnecessarily" instruction.

## 21. Play Store readiness

COMPLETED (documentation) this pass — see `docs/
PLAY_STORE_RELEASE_CHECKLIST.md` (new): Android configuration itself is
READY pending a real signing key and an actual build; every Console-side
item (screenshots, store copy, Data Safety form, content rating, hosted
Privacy Policy URL) is NOT YET DONE, honestly labeled as such rather
than assumed.

## 22. Independent app disclaimer

COMPLETED — already present (`about_screen.dart`), wording reviewed and
closely matches the requested language; no change needed.

## 23. Final test suite

COMPLETED for what's testable without a live backend — see "TEST
RESULTS" in `docs/FINAL_QA_REPORT.md`(updated this pass). Areas the
request lists that are already covered: search (pagination), bookmarks
(via `BookmarkRepository`'s existing behavior, not independently
re-tested this pass since untouched), practice/scoring
(`practice_result_test.dart`, pre-existing), PDF generation
(pre-existing, untouched), admin authorization (RLS reviewed, not
executable here), quality validation (`question_validation_test.dart`,
`content_import_validation_test.dart`, pre-existing), AI Teacher/
cancellation/errors/conversation management (`ai_teacher_screen_test.
dart`, pre-existing + prior-pass additions), pagination (`pagination_
notifier_test.dart`, prior pass), content status
(`paper_status_test.dart`, pre-existing), verified answer workflow (see
§2–4 — the existing quality/verification-status tests already cover
this; no new workflow was added to test). **Not independently tested
this pass** (pre-existing, unchanged, and out of this pass's stated
priority order): authentication flow, navigation, dark mode toggling,
deep links — these have no dedicated automated test in the repo today
and adding them wasn't reachable within this pass's scope after
covering the higher-priority items above; tracked here rather than
silently skipped.

## 24. Build verification

**BLOCKED BY ENVIRONMENT.** No Android SDK in this sandbox; a prior
session's attempt to install one was rejected by the environment's
egress policy (`dl.google.com` connection refused). `flutter analyze`
and `flutter test` were run (see "TEST RESULTS"); `flutter build
appbundle`/`apk --release` were not attempted, per the explicit
instruction not to pretend a build succeeded. Exact commands for
whoever has SDK access:
```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
flutter build apk --release
```
Expected output locations: `build/app/outputs/bundle/release/` and
`build/app/outputs/flutter-apk/`.

## 25. Documentation

COMPLETED this pass — created/updated: `docs/REMAINING_WORK_AUDIT.md`
(this file, new), `docs/AI_TEACHER_ARCHITECTURE.md` (new),
`docs/CONTENT_IMPORT_GUIDE.md` (extended with the source/OCR section),
`docs/SECURITY_AUDIT.md` (new), `docs/PLAY_STORE_RELEASE_CHECKLIST.md`
(new), `docs/FINAL_QA_REPORT.md` (updated for this pass).
`docs/ADMIN_CONTENT_GUIDE.md` was reviewed and found already accurate —
not modified, since nothing in this pass changed the admin content
workflow it documents. `README.md` was reviewed and already covers
purpose/architecture/setup/environment variables/Supabase setup/content
import/admin workflow/AI Teacher/testing/release build — not modified,
for the same reason.
