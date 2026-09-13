# Admin Content Guide

How to use the in-app admin screens to get a real, verified paper from a
blank phase/subject slot to `PUBLISHED`. For scripted/bulk import via
JSON files instead of typing questions into the app by hand, see
`docs/CONTENT_IMPORT_GUIDE.md`.

Everything in this guide assumes your account has `profiles.is_admin =
true` (see README.md "Supabase Setup" for how to grant that). Every action
described here is also enforced server-side — see "How security works"
at the end — so this UI is a convenience, not the actual access boundary.

## How to create a paper

1. Open **Admin → Manage Papers** (`/admin/papers`).
2. Tap **Import Source Paper**.
3. Pick the **Phase** and **Subject** — these are the fixed 3 phases and
   8 subjects; you cannot add a new one from this screen, by design (see
   CLAUDE.md "Database Rules").
4. Enter the **Title**, and — only if the source document actually states
   them — **Cadre**, **Total Marks**, **Duration**. Leave any of these
   blank rather than guessing; nothing here is invented.
5. Save. The paper is created as **Draft** with **Missing Source** (no
   file attached yet).

## How to upload source material

1. Open the paper (tap it from Manage Papers) → its detail screen.
2. Under **Original Paper File**, tap **Upload File** (or **Replace
   File** if one is already attached).
3. Pick the PDF or image (JPG/PNG) of the actual scanned paper. It is
   uploaded to the `original-papers` Storage bucket at
   `phase-<slug>/<subject-slug>/original.<ext>` and the paper's
   `source_file_url`/`source_file_type` are set automatically.
4. The original file is never modified in place by the app — replacing it
   uploads a new object at the same path; the paper's version/audit trail
   records that the file changed.

A paper with no file attached is always flagged **Missing Source** and
can never be Verified or Published — the Quality Check panel (see below)
enforces this every time, both on-screen and, authoritatively, in the
database.

## How to create sections

1. From the paper detail screen, tap **Manage Sections & Questions**.
2. Tap **+** to add a section: **Section Name** (e.g. "Section A"),
   **Section Code** (e.g. "A"), optional **Marks**, optional
   **Instructions**.
3. **Preserve the original paper's actual section structure.** Do not
   invent section names, and do not assume every paper has the same
   Section A/B/C layout — read the source document and match it exactly.

## How to enter questions and answers

1. From the sections list, tap a section to open its question list, then
   **+** to add a question (or tap an existing one to edit it).
2. Fill in **Question Number** (matching the original paper's own
   numbering — never renumber to "fix" a gap), **Question Type**
   (MCQ / Short / Long), and the **Question Text** exactly as printed.
3. For an **MCQ**: add at least 2 options, select the radio button next
   to the option you have independently verified as correct, and
   optionally record the **Original Marked Option** (what was ticked in
   the supplied paper). If that differs from the option you marked
   correct, the question is automatically flagged
   `PAPER_ANSWER_ERROR` — both the original and verified answers stay
   visible to end users, never silently overwritten.
4. For a **Short** or **Long** question: enter the **Verified Answer**
   (and optional **Explanation**). This field is required — a question
   with no verified answer is a critical quality error and blocks
   publication.
5. Set **Quality Status**. Leave it **Verified** only when you're
   confident the question, options, and answer are all correct as
   entered. Otherwise pick **Quality Check** (questionable),
   **Paper Error**, **Scan/OCR Uncertain**, or **Answer Key
   Discrepancy**, and fill in the **Quality Note** explaining why —
   this is required whenever status isn't Verified, and the note is what
   end users see when they tap the warning badge.

## How quality checks work

Every paper has a **Quality Check** report, visible on its **Review &
Publish** screen (`/admin/papers/:id/review`):

```
QUALITY CHECK

✓ All checks passed.
```

or, with issues:

```
QUALITY CHECK                                    ERROR — 55/100

✗ Section A Q7: MCQ does not have exactly one correct option.
✗ Section B Q3: missing a verified answer.
⚠ Section A Q12: quality status is OCR_UNCERTAIN — needs human review.
```

- **✗ errors** (red) are critical — missing source file, a section with
  no questions, an MCQ without exactly one correct option, an empty
  question, a short/long question with no verified answer, negative
  marks, or duplicate question numbers within a section. **These block
  Verify and Publish outright**, both in this screen's buttons and,
  authoritatively, in the database (`paper_has_critical_errors` in
  `supabase/migrations/006_admin_workflow.sql` — a client can't bypass
  this by calling the API directly).
- **⚠ warnings** (orange) are anything with a non-Verified
  `quality_status`. These don't block publishing, but they're exactly the
  items in **Admin → Review Questionable Questions** — resolve them when
  you can before publishing, since end users will see the warning badge.

Tap any listed issue's question from the section's question list to fix
it directly.

## How verification works

From the Review & Publish screen, once a paper is **Needs Review** (see
"How publishing works" for how it gets there) and has zero critical
errors, tap **Verify**. You'll be asked for optional notes. This records
`verified_by` (you), `verified_at` (now), and your notes on the paper, and
moves it to **Verified**.

**If you edit any section or question on a Verified (or Published) paper
afterward, it is automatically moved back to Needs Review** — the
verification record is cleared and an audit log entry
(`AUTO_INVALIDATE_VERIFICATION`) is written. This happens via a database
trigger, not app code, so it can't be skipped by editing through a
different client. A modified question can never keep sitting under a
stale "Verified" paper.

## How publishing works

The full status path is:

```
Draft → Needs Review → Verified → Published
```

with Archive available from any of the first three, and Unpublish
(`Published → Verified`) available once live. Each button on the Review
& Publish screen only shows the transitions currently legal from the
paper's status — e.g. a Draft paper can only go to Needs Review or
Archived.

- **Submit for Review** (Draft → Needs Review): do this once you believe
  the paper's sections and questions are complete, even if the Quality
  Check still shows issues — Needs Review is exactly the state for
  working through them.
- **Verify** (Needs Review → Verified): blocked while any critical error
  remains.
- **Publish** (Verified → Published): also blocked while any critical
  error remains (in practice this should already be true, since Verify
  required it — but the check runs again independently). **Publishing
  makes the paper visible to every user of the app.** Only do this once
  you're confident in the content.
- **Unpublish** (Published → Verified): takes a live paper back to
  Verified-but-not-public, e.g. to fix a small issue without dropping all
  the way back to Needs Review.
- **Archive**: available from Draft, Needs Review, or Verified/Published,
  for content you're retiring rather than actively working on.
- **Restore** (Archived → Draft): brings an archived paper back into the
  active workflow.

## How to handle errors

- **"Cannot move to VERIFIED/PUBLISHED — unresolved critical quality
  errors"**: open Review & Publish, read the ✗ list, tap through to each
  question and fix it, then retry.
- **A paper you thought was Verified shows Needs Review**: check the
  Audit Log (`/admin/audit-log`) for an `AUTO_INVALIDATE_VERIFICATION`
  entry — someone (possibly you) edited a section/question after it was
  verified. Re-run Verify once you're satisfied again.
- **"MISSING SOURCE PAPER — DO NOT PUBLISH"**: this is not an error to
  work around — it means exactly what it says. Upload the real original
  file before doing anything else with that paper.

## How to import future Phase II/III/IV papers

Repeat "How to create a paper" through "How to enter questions and
answers" above for each new phase/subject slot as real source papers
become available — there is no shortcut, and no content should ever be
entered without a real source document in hand. For entering many
questions at once from a careful transcription rather than one at a time
in the UI, use the scripted path in `docs/CONTENT_IMPORT_GUIDE.md`
instead (it produces papers in the same Draft state, ready for the same
review/verify/publish steps above).

## How security works

Everything above is a convenience UI. The actual enforcement is:

- Postgres Row Level Security requires `profiles.is_admin = true` for any
  write to `papers`, `paper_sections`, `questions`, or `question_options`
  (`supabase/migrations/002_rls.sql`) — a non-admin's write silently
  affects zero rows, never a special error path to rely on.
- The `admin_transition_paper_status` function re-validates both the
  status transition and the quality gate server-side
  (`006_admin_workflow.sql`) — a client cannot force an illegal
  transition or publish over unresolved critical errors by calling the
  API directly, bypassing the Flutter app's own buttons.
- The `SUPABASE_SERVICE_ROLE_KEY` is never used by the Flutter app itself
  — only by `scripts/import_content.dart` and the `delete-account` Edge
  Function, both run outside the app.
