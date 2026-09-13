# Content Import Guide

This guide covers the bulk/scripted path for getting a verified source
paper into the database as a JSON file, via `scripts/validate_content.dart`
and `scripts/import_content.dart`. For doing the same thing by hand inside
the app's admin screens, see `docs/ADMIN_CONTENT_GUIDE.md` instead — most
admins will use that; this guide is for whoever is transcribing a source
paper into the JSON format in the first place (or scripting a batch
import).

**No exam content ships in this repository.** Every phase/subject slot is
`MISSING SOURCE PAPER` until a real, verified source paper goes through
this pipeline. Nothing here should ever be used to invent or approximate
content — see CLAUDE.md "Content Rules" and "Do-Not-Do List".

## Directory layout

```
content/
  phase_2/
    english.json
    mathematics.json
    ... (8 subject files)
  phase_3/
    ... (same 8 subject files)
  phase_4/
    ... (same 8 subject files)
```

One file = one paper. `content/README.md` documents the full workflow;
this file documents the JSON shape and the two scripts in detail.

## JSON shape

```json
{
  "phase_slug": "phase-4",
  "subject_slug": "english",
  "title": "Teacher Induction Program — Phase IV — English",
  "cadre": null,
  "total_marks": 100,
  "duration_minutes": 90,
  "sections": [
    {
      "section_name": "Section A",
      "section_code": "A",
      "marks": 20,
      "questions": [
        {
          "question_number": 1,
          "question_type": "mcq",
          "question_text": "Identify the compound word.",
          "marks": 1,
          "quality_status": "VERIFIED",
          "options": [
            {"option_label": "A", "option_text": "milk", "is_verified_correct": false},
            {"option_label": "B", "option_text": "milk shake", "is_verified_correct": false},
            {"option_label": "C", "option_text": "milkshake", "is_verified_correct": true},
            {"option_label": "D", "option_text": "shake", "is_verified_correct": false}
          ],
          "explanation": "\"Milkshake\" is a compound word formed by combining \"milk\" and \"shake\"."
        }
      ]
    }
  ]
}
```

Rules that the validator enforces (see the next section for how to run
it), matching the spec's "Absolute Content Accuracy Rule":

- `phase_slug` must be one of `phase-2`, `phase-3`, `phase-4`.
- `subject_slug` must be one of the 8 fixed subject slugs (see
  `lib/core/constants/app_constants.dart`).
- **No `year`, `academic_year`, or `session_year` field, ever.**
- Every question needs a `question_number`, `question_type`
  (`mcq`/`short`/`long`), non-empty `question_text`, and a
  `quality_status` (`VERIFIED`/`QUESTIONABLE`/`PAPER_ERROR`/
  `OCR_UNCERTAIN`/`ANSWER_UNCERTAIN`).
- Any `quality_status` other than `VERIFIED` requires a `quality_note`
  explaining why.
- MCQs need at least 2 options, unique labels, and exactly one option
  marked `is_verified_correct`.
- Short/long questions need a non-empty `verified_answer`.
- Question numbers must be unique within their section.
- Marks, when present, must be non-negative.

If a question was originally marked with a different answer than the one
you've independently verified as correct, record both:

```json
{
  "original_marked_option": "B",
  "verified_answer": "C",
  "verification_status": "PAPER_ANSWER_ERROR"
}
```

Never let a tick on the original paper silently become the stored answer
— see CLAUDE.md "Database Rules" on `original_marked_option` vs.
`verified_answer`.

## Step 1 — Validate

```bash
dart run scripts/validate_content.dart content
```

Exits `0` with "PASSED" if there are no critical errors, or `1` listing
every `CRITICAL` line to fix. A file with only `WARNING` lines (e.g. an
empty section) still passes but is worth checking. Fix every critical
error before moving on — never hand-edit the database to route around a
validation failure.

## Step 2 — Import

```bash
dart run scripts/import_content.dart content \
  --url=$SUPABASE_URL --service-key=$SUPABASE_SERVICE_ROLE_KEY
```

This is an admin/CI tool — it uses the service-role key directly (never
ship it in the Flutter app) to upsert each file's paper/sections/
questions/options. **Every paper it creates or updates lands as `DRAFT`.**
The importer never sets `content_status` to anything else, and never
touches `verified_by`/`verified_at`/`verification_notes` — those only
change through the admin verification workflow (see
`docs/ADMIN_CONTENT_GUIDE.md`), never automatically.

If a paper already exists for that phase/subject slot (the `papers` table
has a `unique (phase_id, subject_id)` constraint), the importer updates it
in place rather than creating a duplicate.

## Step 3 — Attach the original file

The importer does not upload the source PDF/image — do that from the
admin Paper screen (`Upload File` / `Replace File`), or directly to the
`original-papers` Storage bucket at
`phase-<2|3|4>/<subject-slug>/original.<pdf|jpg|png>`, then set
`papers.source_file_url`/`source_file_type` to match. A paper with no
source file is flagged **Missing Source** and cannot be verified or
published — see the quality gate in
`supabase/migrations/006_admin_workflow.sql`.

## Step 4 — Review and publish

From here, follow the same admin verification workflow as content entered
by hand: Submit for Review → fix anything the Quality Check panel flags →
Verify → Publish. See `docs/ADMIN_CONTENT_GUIDE.md` "How verification
works" and "How publishing works".
