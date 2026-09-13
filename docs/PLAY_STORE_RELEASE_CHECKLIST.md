# Play Store Release Checklist

Status per item, based on reading the current Android configuration and
project docs — **not** verified against the live Play Console (this
sandbox has no web access to confirm current Play Store policy pages,
and no Play Console account to check against). Cross-check every "policy
compliance" row against Google's current published requirements before
submitting; policy text changes over time and this document cannot stay
current on its own.

## Android configuration (verified by reading the repo)

| Item | Status | Detail |
|---|---|---|
| `applicationId` | READY | `com.asmatullahkhan.induction_program_past_papers` — permanent per `CLAUDE.md`, never change after first publish. |
| App name | READY | "Induction Program Past Papers" (`AndroidManifest.xml` `android:label`). |
| `versionName` / `versionCode` | READY, PLACEHOLDER VALUE | `pubspec.yaml` → `1.0.0+1` (versionName 1.0.0, versionCode 1). Fine for a first release; increment `versionCode` on every subsequent Play Store upload — Play Console rejects a re-upload with the same `versionCode`. |
| `compileSdk` / `targetSdk` | READY | Both follow `flutter.compileSdkVersion`/`flutter.targetSdkVersion` (currently 36, from the bundled Flutter Gradle plugin) rather than a hard-coded number — re-check Play's current minimum target-API requirement against whatever Flutter version is bundled at release time; this auto-follows Flutter upgrades but a stale Flutter SDK could still fall behind Play's minimum. |
| `minSdk` | READY | Follows `flutter.minSdkVersion` (Flutter's own default) — no custom override found. |
| Permissions | READY | Only `android.permission.INTERNET` in `AndroidManifest.xml`, plus a `PROCESS_TEXT` query entry (required by Flutter's text-selection plugin, not a runtime permission). No camera/storage/location/contacts permission requested — matches the app's actual feature set (no photo capture found in the reviewed code; `file_picker` is used for admin PDF/image uploads, which typically uses the system picker without a broad storage permission on modern Android — re-verify this specifically if `file_picker`'s Android implementation changes). |
| Deep links | READY | One custom-scheme link (`reset-password`) for Supabase Auth password reset — no broader intent-filter surface. |
| Network security config | NOT PRESENT — LIKELY FINE, NOT VERIFIED | No `network_security_config.xml` found; the app only talks to `https://*.supabase.co` and the Anthropic API server-side (never from the client) — Android's default network security config already blocks plaintext HTTP for apps targeting a modern `targetSdk`, so an explicit config is likely unnecessary. Add one only if a future requirement needs an HTTP exception. |
| Launcher icon | READY (unverified content) | `android:icon="@mipmap/ic_launcher"` is wired; the actual icon *image* content wasn't inspected pixel-by-pixel — open it before submission and confirm it isn't Flutter's default template icon. |
| Adaptive icon | NOT VERIFIED | Standard `flutter create` scaffolding includes adaptive-icon XML under `android/app/src/main/res/mipmap-anim*`/`values/`; confirm the foreground/background layers are the app's real icon, not the Flutter default, before submission. |
| Splash screen | READY | `LaunchTheme`/`NormalTheme` wired per standard Flutter scaffolding; app has its own splash screen widget per `test/widget_test.dart`'s "App boots to splash screen" test. |
| Signing | READY, ACTION REQUIRED BEFORE RELEASE | `build.gradle.kts` reads `android/key.properties` when present and falls back to debug signing otherwise — **a real Play Store upload must supply a real `key.properties`** (see `key.properties.example`); never ship a debug-signed release build. `key.properties`/`*.jks`/`*.keystore` are correctly excluded from version control per `CLAUDE.md`. |
| ProGuard/R8 | READY | `isMinifyEnabled = true` with `proguard-android-optimize.txt` + `proguard-rules.pro` wired for the release build type. |
| Release build itself | **BLOCKED BY ENVIRONMENT** | This sandbox has no Android SDK (`flutter build appbundle`/`apk` cannot run here — see `docs/FINAL_QA_REPORT.md`). All configuration above is reviewed, none of it has been exercised by an actual build. |

## Play Console listing requirements (status: prepare, not yet submitted)

| Item | Status | Note |
|---|---|---|
| Privacy Policy | NEEDS A HOSTED URL | The in-app disclaimer/privacy content exists (`lib/features/settings/privacy_screen.dart`, `about_screen.dart`) but Play Console requires a **publicly hosted** Privacy Policy URL, not just in-app text — publish the same content at a real URL before submission. |
| Data Safety form | NOT YET FILLED (Console-side) | Based on what this app actually collects/uses: account email + profile fields (auth), bookmarks/practice/progress (user-generated, tied to account), AI Teacher conversation text (tied to account, see `docs/AI_TEACHER_GUIDE.md` "Privacy"). No advertising ID, no analytics SDK, no third-party data sharing found in the reviewed code. Fill the Console form to match this — do not under- or over-declare. |
| Content rating questionnaire | NOT YET SUBMITTED (Console-side) | Educational exam-prep content, no user-generated public content, no violence/mature themes — expect a low/"Everyone" rating, but the questionnaire itself must be completed in Console, not assumed. |
| Account deletion | READY | In-app account deletion exists and goes through the `delete-account` Edge Function (`CLAUDE.md` "Security Rules") — Play's account-deletion policy (in-app deletion option, not just a support-email request) is satisfied by this. |
| App screenshots | NOT YET PRODUCED | No screenshot assets found in this repository — capture real device/emulator screenshots once a build can actually run (blocked by the same Android-SDK limitation above, though screenshots could also be captured from `flutter run` on a connected device without a signed release build). |
| Feature graphic | NOT YET PRODUCED | Standard 1024×500 Play Store banner — not started. |
| App icon (Store listing) | NOT VERIFIED | Same launcher icon asset, exported at Play's required 512×512 — confirm before upload. |
| Short description | NOT YET WRITTEN | Suggested draft: "Past papers, verified answers, and AI-assisted practice for KP Teacher Induction Program prep." (≤80 chars — trim if needed). |
| Full store description | NOT YET WRITTEN | Draft the listing from the app's real feature set (original papers, verified answer keys, solved questions, practice mode, AI Teacher, bookmarks, progress tracking) — never mention Phase II/III/IV content as available until real papers are actually published in-app, per the project's no-fabrication rule. |
| App category | NOT YET SELECTED (Console-side) | Likely "Education". |
| Contact information / developer information | NOT YET SUBMITTED (Console-side) | Requires a real support email/website — outside what this codebase can supply. |
| Independent-app disclaimer | READY | `about_screen.dart` already states the app is an independent educational resource, not an official government app unless stated otherwise — matches the required wording closely. |

## What this checklist cannot verify

- Google Play's *current* policy requirements (they change over time) —
  this document reflects general, stable Play Store practices as of
  this writing, not a live fetch of Play's policy pages. Re-check the
  official Play Console policy center immediately before submission.
- Actual screenshots, store copy quality, or Console-side form
  submissions — all Console-side work is outside what a code review can
  confirm.
- That a release build actually succeeds — blocked by no Android SDK in
  this sandbox (see `docs/FINAL_QA_REPORT.md` "Android build").

**Bottom line: Android configuration is READY pending a real signing
key and an actual successful release build in an environment with the
Android SDK; every Console-side listing item (screenshots, descriptions,
Data Safety form, content rating, hosted Privacy Policy URL) is
NOT YET DONE and requires manual completion outside this codebase.**
