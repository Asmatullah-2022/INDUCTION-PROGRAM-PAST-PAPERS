# Privacy Policy

_Last reviewed against the actual codebase on this date's session. This
document must be re-verified against the code any time a feature that
touches user data changes — it is a description of what the app
actually does, not an aspirational policy._

This is the hosted-URL counterpart to the in-app Privacy Policy screen
(`lib/features/settings/privacy_screen.dart`) — Play Console requires a
publicly hosted URL, not just in-app text (see
`docs/PLAY_STORE_RELEASE_CHECKLIST.md`). Keep both in sync; this
document was written by reading that screen and the underlying
Supabase schema/Edge Functions, not the other way around.

## Who this app is

Induction Program Past Papers is an independent educational preparation
app for teachers, teacher aspirants, and students preparing for the KP
Teacher Induction Program exams. It is not an official government
application unless explicitly stated otherwise (see the About screen).

## Data we collect

| Category | What, exactly | Why |
|---|---|---|
| Account information | Full name, email address, mobile number, district — collected at sign-up via Supabase Authentication. | To create and identify your account. |
| Bookmarks | Which questions/papers you've bookmarked. | So your bookmarks sync across sessions/devices. |
| Practice history | Practice attempts and answers you submit in Practice Mode. | To score attempts and track your progress. |
| Progress | Per-phase/subject attempted/correct/incorrect counts. | To show your own progress over time. |
| AI Teacher conversations | The messages you send to AI Teacher and its responses, tied to your account. | So you can revisit past AI Teacher conversations; to enforce a daily usage limit (a request count only, not conversation content) so the feature stays available for everyone. |
| Downloads | **Not collected by us at all.** Downloaded PDFs are saved only in your device's own local app storage — the app does not upload, track, or report what you download. | N/A — this stays entirely on your device. |

**We do not collect**: payment information (the app has no payments),
device advertising identifiers, precise location, contacts, or any
analytics/tracking SDK — none exist in this codebase.

## What we do not do

- We do not sell your personal information.
- We do not share your data with any third party for advertising.
- We do not use any third-party analytics or advertising SDK — grepped
  the codebase for common analytics/ads package names and found none.

## Third-party services actually used

| Service | What it's used for | What it can see |
|---|---|---|
| Supabase (Postgres, Auth, Storage, Edge Functions) | The entire backend — authentication, database, file storage, and the two Edge Functions (`delete-account`, `ai-teacher`). | Everything listed in "Data we collect" above, since Supabase *is* our backend, not a separate third party your data is additionally shared with. |
| Anthropic (Claude) | Powers AI Teacher's responses, called only from the server-side `ai-teacher` Edge Function — the Flutter app never talks to Anthropic directly. | The text of your AI Teacher messages and, when you ask about a specific verified question, that question's already-public verified content. Anthropic's own data-handling terms govern what happens to a request once it reaches their API; we do not control that independently of using their API as intended. | 

No other third-party service is integrated into this app.

## Storage and security

Your data is stored in Supabase (PostgreSQL) with Row Level Security
enabled on every table that holds user data — you can only read or
write your own bookmarks, practice history, progress, and AI Teacher
conversations; nobody else's account can see them, and this is enforced
by the database itself, not just the app's screens. See
`docs/SECURITY_AUDIT.md` for the full technical review.

## Retention

Your data is retained for as long as your account exists. There is no
automatic expiry on bookmarks/practice history/progress/AI Teacher
conversations today — they persist until you delete them individually
(where the app supports that, e.g. deleting one AI Teacher conversation)
or delete your account entirely.

## Account deletion

You may delete your account at any time from **Profile → Delete
Account**. This permanently removes, via the `delete-account` Edge
Function and database foreign-key cascades:
- Your profile (name, email, mobile number, district)
- Your bookmarks, practice attempts/answers, and progress
- Your AI Teacher conversations and messages (cascades automatically
  when your account is deleted, via the database's own foreign-key
  rules — not a separate manual step that could be missed)
- Your authentication account itself

The app also clears locally-cached content and any files you've
downloaded from your device at the same time, so nothing related to the
deleted account remains on your device either.

This is irreversible. There is currently no "export your data before
deleting" feature — if you want a copy of your practice history or AI
Teacher conversations before deleting your account, review them in the
app first.

## AI Teacher — specific handling

- AI Teacher's responses always distinguish "AI-generated" content from
  the app's own verified answers with an explicit label — an AI response
  is never presented as an official verified answer.
- AI Teacher never receives your name, email, mobile number, or district
  — only the message you type and (if you opened it from a specific
  question) that question's own already-public content.
- The server-side Edge Function that powers AI Teacher does not log the
  full content of your prompts or responses in its own operational logs
  — only error events, and those never include your message content or
  any credential.

## Children's / student privacy

This app is intended for use by teachers, teacher aspirants, and
students preparing for a professional teacher-certification exam — it
is not directed at young children, and account creation requires the
same information (name, email, mobile number, district) from every
user regardless of age. If you believe a minor's data was collected
inappropriately, contact us using the information below and we will
address it.

## Changes to this policy

If what the app actually collects or does changes, this document (and
the in-app Privacy Policy screen it mirrors) will be updated to match —
not the other way around.

## Contact

For privacy questions or account-deletion requests you cannot complete
in-app, contact: **[YOUR_SUPPORT_EMAIL — replace before publishing]**.
