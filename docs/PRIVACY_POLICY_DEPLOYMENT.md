# Privacy Policy Deployment

**Status: page created, NOT DEPLOYED.** This document describes exactly
what exists in the repository and exactly what a human with hosting/
Play Console access must do next — it does not claim any URL is live,
because none has actually been published anywhere from this sandbox.

## This session's findings — why deployment stops here, at a human boundary

Inspected directly via the GitHub API this session:

- **Repository**: `Asmatullah-2022/INDUCTION-PROGRAM-PAST-PAPERS`.
- **Branches**: exactly one — `claude/induction-program-app-c3mfag`.
  There is no `main`/`master` branch. This branch *is* the repository's
  only branch, so Option A below needs no "merge to default branch"
  step — it already is the only branch there is.
- **GitHub Pages**: this session has no tool that can read or change a
  repository's Pages configuration (enabling Pages is a repository
  **Settings** action — `Settings → Pages` — that requires a human with
  admin access to the repo; no API call for it is exposed to this
  session). There is no evidence Pages is currently enabled, and this
  session cannot enable it.
- **Network egress**: this sandbox's outbound network is restricted by
  an allowlisted proxy. A direct attempt this session to fetch
  `https://asmatullah-2022.github.io/INDUCTION-PROGRAM-PAST-PAPERS/privacy-policy.html`
  (to check whether Pages happened to already be live) was rejected by
  the proxy with `EGRESS_BLOCKED` before even reaching GitHub's
  servers. This means **even after a human enables Pages, this sandbox
  cannot verify the resulting URL itself** — verification (§"How to
  verify" below) must be done by the human doing the deployment, from
  their own browser/machine, not from this session.

Both of these are hard boundaries of this environment, not something a
different prompt or another attempt would get past. This is the exact
point at which the task stops, per the explicit instruction not to
fabricate a deployment or a URL.

## What exists right now

| File | Purpose |
|---|---|
| `privacy-policy.html` (repo root) | The hosted-ready, self-contained, mobile-friendly static page. No build step, no external asset, no JavaScript dependency — open it directly in any browser to preview it as-is. |
| `.nojekyll` (repo root) | Tells GitHub Pages not to run Jekyll over the repository, so this plain HTML file (and the rest of the repo) is served byte-for-byte rather than being processed as a Jekyll site. |
| `docs/PRIVACY_POLICY.md` | The markdown source of truth this page's content was written from — keep both in sync if either changes. |
| `lib/features/settings/privacy_screen.dart` | The in-app equivalent, shown inside the Flutter app itself (Settings → Privacy Policy, About → Privacy Policy link, Sign Up screen link) — required by Play, but **not** a substitute for a public URL (see below). |

## Why a separate hosted page is required at all

Google Play Console requires a **publicly reachable URL** for the
Privacy Policy field in the app's store listing — an in-app screen
alone does not satisfy this, because reviewers and users must be able
to open the policy from a web browser, before ever installing the app.
`privacy-policy.html` exists specifically to be that URL's content.

## Exact deployment steps (pick one — none of these has been run)

### Option A — GitHub Pages (recommended: zero new service, repo is already on GitHub)

For this exact repository (`Asmatullah-2022/INDUCTION-PROGRAM-PAST-PAPERS`),
which currently has only one branch:

1. Go to **github.com/Asmatullah-2022/INDUCTION-PROGRAM-PAST-PAPERS →
   Settings → Pages**. (Requires being signed in as the repo owner or
   an admin collaborator — this is the human-only step this session
   cannot perform.)
2. Under **Build and deployment → Source**, choose **"Deploy from a
   branch"**.
3. Under **Branch**, choose **`claude/induction-program-app-c3mfag`**
   (this repository's only branch today) and **Folder: `/ (root)`**,
   then **Save**.
   - If, by the time you do this, the work has been merged into a
     `main` branch instead, choose `main` there rather than this
     branch — use whichever branch is actually the repository's default
     at deployment time.
4. Wait for the "pages build and deployment" GitHub Action to finish —
   Settings → Pages will show a green "Your site is live at ..." banner
   once done (usually under a minute).
5. **The resulting URL will be exactly:**
   ```
   https://asmatullah-2022.github.io/INDUCTION-PROGRAM-PAST-PAPERS/privacy-policy.html
   ```
   This is a deterministic consequence of GitHub Pages' own URL scheme
   for this specific, already-known repository owner/name — it is
   **not yet live**, and this session could not verify it even after
   you enable Pages (see "This session's findings" above: outbound
   access to `*.github.io` is blocked from this sandbox). **You must
   verify it yourself** — open it in a real browser, or run the `curl`
   command in "How to verify" below from your own machine — before
   treating it as real and before entering it anywhere in Play Console
   or replacing any `PRIVACY_POLICY_URL_REQUIRED` placeholder with it.

**Known tradeoff of this option, stated plainly**: choosing "root" as
the Pages folder publishes the *entire* repository's tracked files as
static, browsable content (e.g. `README.md`, the `docs/` folder) at
their own paths, not just `privacy-policy.html`. Nothing in this
repository is secret — every prior security audit in this project
(`docs/SECURITY_AUDIT.md`) confirmed no credential is ever committed —
so this is not a security exposure, but it is a discoverability
tradeoff worth knowing before enabling it. If that's undesirable, use
Option B or C instead, or move the page to its own dedicated
Pages-serving branch (a repository-structure decision to make
deliberately, not one this document makes unilaterally).

### Option B — Any static host (Vercel, Netlify, Cloudflare Pages, S3+CloudFront, etc.)

1. Deploy `privacy-policy.html` as the sole file (or one file among
   others) to the static host of choice — every one of these supports
   "drag and drop a single HTML file" or a one-command CLI deploy.
2. Note the resulting public URL from that host's dashboard/CLI output.
3. No repository changes are needed for this option beyond the file
   already committed here.

### Option C — Your organization's own existing website

If there's already a website for this project/organization, upload
`privacy-policy.html`'s contents to a page there (e.g.
`https://your-existing-site.example/privacy-policy`) and use that URL
instead.

## How to verify the deployed page (once one of the above is done)

```bash
curl -I https://<the-real-deployed-url>
```
Expect `HTTP/2 200` (or `HTTP/1.1 200 OK`) and `content-type: text/html`.
Then open the URL in an actual mobile browser (or Chrome DevTools'
device emulation) and confirm it renders without horizontal scrolling
and is readable at phone width — the page's CSS was written to be
mobile-friendly by default (a single centered column, system fonts, a
`viewport` meta tag), but this should still be eyeballed once, on the
real deployed URL, not just assumed from reading the HTML source.

## Where to enter the URL in Google Play Console

**Play Console → your app → Policy → App content → Privacy policy** —
paste the exact deployed URL from whichever option above was used.
Play also surfaces a Privacy Policy field under **Store presence →
Main store listing** in some Console layouts; enter the same URL in
both places if both are shown.

## Account deletion requirement (Play policy, not just this document)

Google Play separately requires that if an app supports account
creation, it must also let users request account deletion — and, since
2023, that this deletion option be reachable **from within the app**,
not only via a web form or support email. This app already satisfies
that: **Profile → Delete Account** (see `lib/features/profile/
profile_screen.dart`) calls the `delete-account` Edge Function directly
and is covered by an automated test
(`test/widget/privacy_and_account_test.dart`, "ProfileScreen — account
deletion entry point"). Play Console may also ask for a **web** page
describing the deletion process (separate from performing the deletion
itself) — the "Account Deletion" section already inside
`privacy-policy.html`/`docs/PRIVACY_POLICY.md` covers this; no separate
page is required unless Play's own form for this specific app
explicitly asks for one.

## What remains blocked until deployment

- **Enabling GitHub Pages itself** — requires a human with admin access
  to the repository's Settings; no tool available to this session can
  do this. This is the actual, current blocker — everything else in
  this document is ready and waiting on this one manual step.
- **Verifying the resulting URL** — even after Pages is enabled, this
  sandbox's network egress cannot reach `*.github.io` (confirmed this
  session — see "This session's findings" above), so verification must
  happen from the deploying human's own browser/machine, not from a
  future session running in this same sandbox either.
- **Play Store submission itself** — cannot be finalized without a
  real, live, human-verified Privacy Policy URL entered in Console.
  Every other Play Store checklist item in `docs/
  PLAY_STORE_RELEASE_CHECKLIST.md` can proceed independently of this
  one, but the listing as a whole cannot be submitted without it.
- **`docs/PLAY_STORE_RELEASE_CHECKLIST.md` and `docs/PLAY_STORE_LISTING.md`**
  both reference the literal placeholder `PRIVACY_POLICY_URL_REQUIRED`
  wherever the real URL belongs — replace every occurrence of that
  exact string with the real, human-verified deployed URL once the
  steps above have actually been carried out, and only then. Do not
  replace it based on the deterministic URL formula in Option A step 5
  alone — that formula is correct but unverified until a human opens it.
- **A live-browser mobile-friendliness check** — the CSS was written to
  be mobile-friendly and reviewed by reading it, but was not opened in
  an actual browser from this sandbox; do this once deployed, per "How
  to verify" above, from the deploying human's own device.
