# Final QA Report

Run results as of the latest changes (question reordering + live
numbering validation, PDF export, Content Coverage screen, in-app bulk
JSON import, and `scripts/validate_content.dart`'s move onto shared
validation). See `docs/PRODUCTION_FEATURE_AUDIT.md` for
feature-completeness and `docs/PROJECT_AUDIT.md` for the
architecture/security narrative.

## flutter analyze

```
10 issues found.
```

All 10 are `info`-level deprecation notices from third-party
packages/Flutter itself (`RadioListTile.groupValue`/`onChanged`,
`supabase_flutter`'s `anonKey`, an unnecessary `photo_view` import) —
**zero errors, zero warnings**. These predate this session and are
tracked, not ignored: `CLAUDE.md` "Testing Rules" says info-level notices
from third-party packages are acceptable and to fix them
opportunistically.

## flutter test

```
88 tests, all passing (0 failures)
```

55 tests carried over from before the reordering work, plus 33 added
since:

- `test/unit/question_numbering_test.dart` — 9 tests (sequential pass,
  duplicate detection, gap detection, gap-is-warning-not-error,
  duplicate+gap combined, empty list, single question, unordered input,
  multiple duplicates/gaps)
- `test/unit/question_reorder_test.dart` — 10 tests (renumbering, order
  preservation, id preservation, move-to-end, move-to-front, no-op move,
  multi-step reordering, post-reorder validity)
- 1 test added to `test/unit/paper_status_test.dart` (empty
  question_text is a critical error)
- `test/unit/content_import_validation_test.dart` — 13 tests (valid
  paper passes; invalid phase/subject slug, year field, missing title, no
  sections, empty section, MCQ with no correct option, duplicate/gap
  numbering, quality_note requirement, missing verified_answer)

## scripts/validate_content.dart

```
No content files found under content. This is expected until verified
source papers are supplied — nothing to validate.
MISSING SOURCE PAPER — DO NOT PUBLISH.
```

Exit code 0. Unchanged from prior sessions — still correctly reports
there is nothing to validate, because there is no content.

## Android build

**Not attempted, per explicit instruction not to pretend.** Environment
state, re-verified this session:

```
[✗] Android toolchain - develop for Android devices
    ✗ Unable to locate Android SDK.
```

A prior session already tried to download the Android command-line tools
to fix this and hit an environment-level block:

```
curl: (56) CONNECT tunnel failed, response 403
[agent-proxy] ... dl.google.com:443 — connect_rejected
(the egress proxy denied the CONNECT — organization policy)
```

This is an egress-allowlist restriction on this sandbox, not something
fixable from inside the session. **Exact blocker: this environment's
network policy does not allow reaching `dl.google.com` to install an
Android SDK, so `flutter build appbundle`/`apk` cannot be run or verified
here.** The Gradle/signing/manifest configuration itself has been
reviewed and is release-ready (see `README.md` "Release Build" /
"Signing") — it has simply never been exercised by an actual build in
this sandbox. Whoever runs the build in an environment with Android SDK
access should treat that as the first real build attempt, not a repeat of
one that already succeeded.

## Content coverage / real exam data

No exam content exists in the repository, and none was added this
session. Every phase/subject slot remains **Missing Source**. Nothing was
fabricated to make the new Content Coverage screen, PDF export, or
reordering feature look populated — they were all built and tested
against constructed test fixtures (in `test/unit/`) or empty-state UI, not
invented exam questions.

**REAL SOURCE PAPERS ARE STILL REQUIRED. NO EXAM CONTENT WAS FABRICATED.**
