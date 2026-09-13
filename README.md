# Induction Program Past Papers

An Android app helping newly recruited government teachers in Khyber
Pakhtunkhwa, Pakistan prepare for the Teacher Induction Program
examinations — original past papers, verified answer keys, solved
short/long questions, complete solved papers, MCQ practice, bookmarks, and
progress tracking.

This app is an independent educational preparation resource and is not an
official government application unless explicitly stated otherwise.

## Architecture

```
lib/
  core/            constants, theme, routing (go_router), errors, services
  data/
    models/        plain Dart data models (fromJson/toJson, no codegen)
    repositories/  the only layer that talks to Supabase directly
  features/        one folder per feature (auth, home, phases, subjects,
                    papers, practice, bookmarks, progress, profile,
                    settings, search, admin)
  shared/widgets/  cross-feature UI (quality badges, empty/error states, ...)

supabase/
  migrations/      001_initial_schema, 002_rls, 003_storage,
                    004_seed_structure, 005_indexes
  functions/       delete-account (Edge Function; service-role only)

scripts/
  validate_content.dart   validates paper JSON before import
  import_content.dart     imports validated JSON into Supabase as DRAFT

content/           per-paper JSON source files (phase_<2|3|4>/<subject>.json)
```

Content is organized strictly as **Phase → Subject → Paper → Section →
Question → Answer**. There is deliberately **no year field anywhere** —
see `CLAUDE.md` for why, and don't add one.

State management is Riverpod, navigation is go_router, backend is
Supabase (Postgres + Auth + Storage + Edge Functions).

## Flutter Setup

Requires Flutter 3.35+ (Dart 3.9+).

```bash
flutter pub get
```

## Supabase Setup

1. Create a Supabase project.
2. Apply the migrations in order (via the Supabase CLI or SQL editor):
   ```bash
   supabase db push
   # or run supabase/migrations/*.sql in order through the SQL editor
   ```
3. Deploy the Edge Function used for account deletion:
   ```bash
   supabase functions deploy delete-account
   ```
4. In Authentication → URL Configuration, add a redirect URL matching the
   Android deep link declared in `AndroidManifest.xml`:
   `com.asmatullahkhan.inductionprogrampastpapers://reset-password`
5. Create your first admin: sign up normally through the app, then in the
   SQL editor run:
   ```sql
   update public.profiles set is_admin = true where email = 'you@example.com';
   ```

## Environment Configuration

Copy `.env.example` to `.env` for your own reference (the app does not
read `.env` directly). Pass the values at run/build time via
`--dart-define`:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
```

Never pass `SUPABASE_SERVICE_ROLE_KEY` here — it is only used server-side
(Edge Functions, `scripts/import_content.dart` run from a trusted
machine/CI).

## Database Setup / Storage Setup

Covered by the migrations above. The `original-papers` Storage bucket is
created and policy-protected by `003_storage.sql` (public read, admin-only
write), with the path convention
`phase-<2|3|4>/<subject-slug>/original.<pdf|jpg|png>`.

## Content Import

See `content/README.md` for the full workflow. In short:

```bash
dart run scripts/validate_content.dart content
dart run scripts/import_content.dart content \
  --url=$SUPABASE_URL --service-key=$SUPABASE_SERVICE_ROLE_KEY
```

No paper content ships in this repository — every phase/subject slot is
currently `MISSING SOURCE PAPER — DO NOT PUBLISH` until real, verified
source papers are supplied and go through this pipeline.

## Admin Setup

Admin access is controlled by `profiles.is_admin` (see Supabase Setup
above) and enforced server-side by RLS — see `CLAUDE.md` "Security Rules".
The in-app `/admin` route currently ships a content QA dashboard
(published-paper counts per phase, question-type/quality-status counts)
and a role gate; full content CRUD admin screens are a planned follow-up
(see `CLAUDE.md` "Admin System").

## Testing

```bash
flutter analyze
flutter test
```

## Debug Build

```bash
flutter run \
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

## Release Build

1. Generate an upload keystore and create `android/key.properties` from
   `android/key.properties.example` (never commit the real file).
2. Build the release App Bundle for Play Console:
   ```bash
   flutter build appbundle --release \
     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
   ```
3. For direct device testing, build an APK instead:
   ```bash
   flutter build apk --release \
     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
   ```

## Signing

See `android/app/build.gradle.kts` — it reads `android/key.properties` if
present, and falls back to debug signing only when that file is absent
(so `flutter run --release` works locally without a real keystore). A real
Play Store build **must** supply `key.properties`.

## Play Store Publishing

- Application ID `com.asmatullahkhan.induction_program_past_papers` is
  permanent — never change it after first publish.
- `compileSdk`/`targetSdk` come from the Flutter Gradle plugin's bundled
  defaults (currently API 36), satisfying Play's current target-API
  requirement.
- Prepare, before submitting: Privacy Policy URL (see in-app
  `/privacy` screen for the text to host), Data Safety declaration
  (collects: name, email, mobile, district, practice/progress data —
  see `lib/features/settings/privacy_screen.dart`), content rating,
  screenshots, feature graphic, and app icon (adaptive icon assets are
  under `android/app/src/main/res/mipmap-*`, regenerate with your final
  artwork before release).
- "Contains ads": No, unless ads are added later (see `CLAUDE.md`).
- Account deletion: supported in-app (Profile → Delete Account), satisfying
  Play's account-deletion requirement.

## Troubleshooting

- **"MISSING SOURCE PAPER" everywhere**: expected on a fresh install with
  no imported content — see Content Import above.
- **Login works but no papers/subjects show**: check that migrations
  001–005 ran and that `phases`/`subjects` were seeded by
  `004_seed_structure.sql`.
- **Password reset link doesn't open the app**: verify the Supabase
  redirect URL matches the Android manifest's deep link scheme exactly.
- **Build fails referencing `key.properties`**: only required for a real
  release build; debug/profile builds don't need it.
