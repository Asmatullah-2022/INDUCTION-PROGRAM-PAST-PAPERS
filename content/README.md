# Content directory

This directory is where verified paper content JSON files go, one file per
paper, organized as `phase_<2|3|4>/<subject-slug>.json`.

**This directory is intentionally empty of paper content in this
repository.** No original scanned Teacher Induction Program papers were
supplied during development of this app, and per the project's content
rules, questions and answers must never be invented. Every phase/subject
slot below is:

**MISSING SOURCE PAPER — DO NOT PUBLISH**

## Expected files (24 total)

```
content/
  phase_2/
    english.json
    mathematics.json
    general-science.json
    islamiat-nazra-quran.json
    ict-in-education.json
    classroom-management-assessment.json
    educational-psychology.json
    curriculum-and-instruction.json
  phase_3/
    ... (same 8 subject files)
  phase_4/
    ... (same 8 subject files)
```

## Adding real content

1. Obtain the original scanned paper (PDF or image) for a phase/subject.
2. Upload it to the `original-papers` storage bucket at
   `phase-<2|3|4>/<subject-slug>/original.pdf` (or `.jpg`/`.png`).
3. Transcribe every question following the JSON shape documented at the
   top of `scripts/validate_content.dart`, including a `quality_status`
   for every question and a `quality_note` for anything not `VERIFIED`.
4. Run `dart run scripts/validate_content.dart content` and fix every
   CRITICAL error it reports.
5. Run `dart run scripts/import_content.dart content --url=... --service-key=...`
   to load the paper as a `DRAFT` paper in Supabase.
6. Follow the human review workflow (CLAUDE.md "Admin System") before
   setting `content_status = 'PUBLISHED'` — only published papers are ever
   shown to normal users.

Never skip step 4. Never hand-edit the database to work around a
validation failure — fix the source JSON instead.
