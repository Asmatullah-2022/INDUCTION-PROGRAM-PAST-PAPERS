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
| `versionName` / `versionCode` | READY | `pubspec.yaml` → `1.0.0+1` (versionName 1.0.0, versionCode 1). Fine for a first release; increment `versionCode` on every subsequent Play Store upload — Play Console rejects a re-upload with the same `versionCode`. |
| `compileSdk` / `targetSdk` | READY | Both follow `flutter.compileSdkVersion`/`flutter.targetSdkVersion` (currently 36, from the bundled Flutter Gradle plugin) rather than a hard-coded number — re-check Play's current minimum target-API requirement against whatever Flutter version is bundled at release time; this auto-follows Flutter upgrades but a stale Flutter SDK could still fall behind Play's minimum. |
| `minSdk` | READY | Follows `flutter.minSdkVersion` (Flutter's own default) — no custom override found. |
| Permissions | READY | Only `android.permission.INTERNET` in `AndroidManifest.xml`, plus a `PROCESS_TEXT` query entry (required by Flutter's text-selection plugin, not a runtime permission). No camera/storage/location/contacts permission requested — matches the app's actual feature set (no photo capture found in the reviewed code; `file_picker` is used for admin PDF/image uploads, which typically uses the system picker without a broad storage permission on modern Android — re-verify this specifically if `file_picker`'s Android implementation changes). |
| Deep links | READY | One custom-scheme link (`reset-password`) for Supabase Auth password reset — no broader intent-filter surface. |
| Network security config | READY | No `network_security_config.xml` found; the app only talks to `https://*.supabase.co` and the Anthropic API server-side (never from the client) — Android's default network security config already blocks plaintext HTTP for apps targeting a modern `targetSdk`, so an explicit config is likely unnecessary. Add one only if a future requirement needs an HTTP exception. |
| Launcher icon | PENDING | `android:icon="@mipmap/ic_launcher"` is wired; the actual icon *image* content wasn't inspected pixel-by-pixel — open it before submission and confirm it isn't Flutter's default template icon. |
| Adaptive icon | PENDING | Standard `flutter create` scaffolding includes adaptive-icon XML under `android/app/src/main/res/mipmap-anim*`/`values/`; confirm the foreground/background layers are the app's real icon, not the Flutter default, before submission. |
| Splash screen | READY | `LaunchTheme`/`NormalTheme` wired per standard Flutter scaffolding; app has its own splash screen widget per `test/widget_test.dart`'s "App boots to splash screen" test. |
| Signing | PENDING | `build.gradle.kts` reads `android/key.properties` when present and falls back to debug signing otherwise — **a real Play Store upload must supply a real `key.properties`** (see `key.properties.example`); never ship a debug-signed release build. `key.properties`/`*.jks`/`*.keystore` are correctly excluded from version control per `CLAUDE.md`. |
| ProGuard/R8 | READY | `isMinifyEnabled = true` with `proguard-android-optimize.txt` + `proguard-rules.pro` wired for the release build type. |
| Release build itself | **BLOCKED BY ENVIRONMENT** | This sandbox has no Android SDK (`flutter build appbundle`/`apk` cannot run here — see `docs/FINAL_QA_REPORT.md`). All configuration above is reviewed, none of it has been exercised by an actual build. |

## Play Console listing requirements (status: prepare, not yet submitted)

| Item | Status | Note |
|---|---|---|
| Privacy Policy | PENDING | A production-ready hosted page exists at `privacy-policy.html` (repo root), matching `docs/PRIVACY_POLICY.md` and the in-app screen exactly — it has **not been deployed anywhere yet**. Enter this exact placeholder in Play Console until it is: `PRIVACY_POLICY_URL_REQUIRED`. See `docs/PRIVACY_POLICY_DEPLOYMENT.md` for the exact deployment steps (GitHub Pages recommended, since the repo is already on GitHub) and where to enter the real URL once deployed. |
| Data Safety form | PENDING (Console-side) | Fill it to match `docs/PRIVACY_POLICY.md`'s "Data we collect" table exactly: account fields, bookmarks/practice/progress, AI Teacher conversations (tied to account). No advertising ID, no analytics SDK, no third-party data sharing beyond Supabase (backend) and Anthropic (AI Teacher's model provider, server-side only) — do not under- or over-declare either. |
| Content rating questionnaire | PENDING (Console-side) | Educational exam-prep content, no user-generated public content, no violence/mature themes — expect a low/"Everyone" rating, but the questionnaire itself must be completed in Console, not assumed. |
| Account deletion | READY | In-app account deletion exists, goes through the `delete-account` Edge Function, and now also clears local cache/downloaded files (`AuthRepository.deleteAccount`) — Play's account-deletion policy (an in-app deletion option, not just a support-email request) is satisfied. |
| App screenshots | PENDING | No screenshot assets found in this repository — capture real device/emulator screenshots once a build can actually run (blocked by the same Android-SDK limitation above, though screenshots could also be captured from `flutter run` on a connected device without a signed release build). |
| Feature graphic | PENDING | Standard 1024×500 Play Store banner — not started. |
| App icon (Store listing) | PENDING | Same launcher icon asset, exported at Play's required 512×512 — confirm before upload. |
| Short description | READY | Drafted in `docs/PLAY_STORE_LISTING.md` (79 characters, fits Play's 80-char limit). |
| Full store description | READY (content-status-dependent) | Drafted in `docs/PLAY_STORE_LISTING.md`, with an explicit switch between "papers available" and "structure ready" wording depending on whether real Phase II/III/IV content is actually PUBLISHED at submission time — read that file's note before publishing either version. |
| Release notes | PENDING | Write these once an actual release build/version is being submitted — nothing to draft yet for a version that hasn't been built. |
| App category | PENDING (Console-side) | Likely "Education" — see `docs/PLAY_STORE_LISTING.md`. |
| Contact information / developer information | PENDING (Console-side) | Requires a real support email/website — outside what this codebase can supply; `docs/PLAY_STORE_LISTING.md` has a placeholder to fill in. |
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
Android SDK. Store copy (short/long description) is now READY as
drafted text in `docs/PLAY_STORE_LISTING.md`; every remaining
Console-side item (screenshots, icon assets, Data Safety form, content
rating, hosting the Privacy Policy URL, contact info) is PENDING and
requires manual completion outside this codebase.**
