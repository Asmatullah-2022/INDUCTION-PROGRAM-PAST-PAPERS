# Privacy Policy Deployment

**Status: DEPLOYMENT CONFIRMED (via GitHub API), HTTPS ACCESSIBILITY NOT
INDEPENDENTLY VERIFIED FROM THIS SANDBOX.** GitHub Pages has been enabled
by the repository owner and GitHub's own "pages build and deployment"
workflow reports a successful build (evidence below). This sandbox's
network egress cannot reach `*.github.io` to independently confirm the
live HTTP response/content, so that specific check — and only that
check — still requires a human (or a future session with unblocked
egress) to open the URL directly.

## Verification performed this session (2026-09-13)

**1. Deployment build confirmed successful — via GitHub's Actions API**
(`api.github.com`, not blocked by this sandbox's egress policy):

```
mcp__github__actions_list(method: list_workflow_runs,
  owner: Asmatullah-2022, repo: INDUCTION-PROGRAM-PAST-PAPERS,
  branch: claude/induction-program-app-c3mfag)
```

Result — one run, of workflow **"pages build and deployment"**:

| Field | Value |
|---|---|
| Run ID | `34758035632` |
| Status / Conclusion | `completed` / **`success`** |
| Branch | `claude/induction-program-app-c3mfag` |
| Commit | `fb75dfff5eb797512fdb3df6d24a1d312efa465e` |
| Triggered by | `Asmatullah-2022` (repo owner) |
| Started / Updated | `2026-09-13T12:47:05Z` / `2026-09-13T12:47:33Z` |
| Run URL | https://github.com/Asmatullah-2022/INDUCTION-PROGRAM-PAST-PAPERS/actions/runs/34758035632 |

This is real, independently-checkable evidence — not the user's
unverified claim — that GitHub accepted the Pages configuration and
built/published the site successfully for the exact commit that added
`privacy-policy.html`.

**2. HTTPS-level content check — attempted twice, both blocked by this
sandbox's own egress policy (not a GitHub-side failure):**

- `WebFetch` on `https://asmatullah-2022.github.io/INDUCTION-PROGRAM-PAST-PAPERS/privacy-policy.html`
  → `EGRESS_BLOCKED` ("Access to asmatullah-2022.github.io is blocked by
  the network egress proxy").
- `curl -I` on the same URL → exit 56, `CONNECT tunnel failed, response
  403`, `HTTP_STATUS:000`.
- Confirmed via the proxy's own status endpoint
  (`http://127.0.0.1:44055/__agentproxy/status`): `*.github.io` is not
  in the `noProxy` allowlist, and `recentRelayFailures` shows a live
  entry — `{"host": "asmatullah-2022.github.io:443", "kind":
  "connect_rejected", "detail": "gateway answered 403 to CONNECT
  (policy denial or upstream failure)"}`.

This is a standing, deliberate organization network policy in this
sandbox, not a transient error — retrying will not change the result.
**DEPLOYMENT EXISTS BUT EXTERNAL VERIFICATION IS UNAVAILABLE** (from
this sandbox) for the live-HTTP-response/content check specifically.

## The confirmed URL

Given (1) above, this is now reported as a **real, build-confirmed**
deployment URL — not merely the deterministic formula predicted before
Pages was enabled:

```
https://asmatullah-2022.github.io/INDUCTION-PROGRAM-PAST-PAPERS/privacy-policy.html
```

**Before entering this in Play Console, a human should still open it in
a real browser once** to confirm the page renders (content/mobile
layout), since this sandbox could only confirm the *build* succeeded,
not the *served content*. This is a materially lighter check than
verifying a deployment happened at all — that part is now done.

## Prior session's findings (superseded by the above)

Earlier in this project, GitHub Pages had not yet been enabled, and this
document accordingly reported that deployment could not proceed past a
human-only boundary (enabling Pages requires repo Settings access this
session never had). The repository owner has since enabled Pages
themselves; the section above reflects the current, confirmed state.

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

## Deployment steps — Option A already completed by the repo owner

### Option A — GitHub Pages (DONE — confirmed via GitHub Actions API above)

The repo owner enabled **Settings → Pages → Deploy from a branch →
`claude/induction-program-app-c3mfag` → `/ (root)`** themselves, and the
resulting "pages build and deployment" workflow run (`34758035632`)
completed with conclusion `success` for commit `fb75dfff5eb7...`. The
live URL is:

```
https://asmatullah-2022.github.io/INDUCTION-PROGRAM-PAST-PAPERS/privacy-policy.html
```

Remaining step: a human should open this URL once in a real browser to
eyeball rendering/mobile layout — this sandbox confirmed the build
succeeded server-side but could not fetch the page's actual HTTP
response (egress to `*.github.io` is blocked here; see above).

**Known tradeoff of this option, stated plainly**: choosing "root" as
the Pages folder publishes the *entire* repository's tracked files as
static, browsable content (e.g. `README.md`, the `docs/` folder) at
their own paths, not just `privacy-policy.html`. Nothing in this
repository is secret — every prior security audit in this project
(`docs/SECURITY_AUDIT.md`) confirmed no credential is ever committed —
so this is not a security exposure, but it is a discoverability
tradeoff worth knowing.

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

## How to verify the deployed page (remaining human step)

```bash
curl -I https://asmatullah-2022.github.io/INDUCTION-PROGRAM-PAST-PAPERS/privacy-policy.html
```
Expect `HTTP/2 200` (or `HTTP/1.1 200 OK`) and `content-type: text/html`.
Then open the URL in an actual mobile browser (or Chrome DevTools'
device emulation) and confirm it renders without horizontal scrolling
and is readable at phone width — the page's CSS was written to be
mobile-friendly by default (a single centered column, system fonts, a
`viewport` meta tag), but this should still be eyeballed once, on the
real deployed URL, not just assumed from reading the HTML source or
from GitHub's build-success signal alone.

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

## What remains — updated after this session's verification pass

- **Enabling GitHub Pages** — DONE (repo owner), confirmed via the
  GitHub Actions API evidence above. No longer a blocker.
- **Deployment build succeeding** — DONE, confirmed via GitHub's own
  "pages build and deployment" workflow (`run 34758035632`,
  conclusion `success`) — not this sandbox's assumption, GitHub's own
  record.
- **Independently fetching the live HTTP response/content from this
  sandbox** — still blocked: this sandbox's network egress cannot reach
  `*.github.io` (reconfirmed this session via `WebFetch`, `curl`, and
  the proxy's `/__agentproxy/status` `recentRelayFailures` entry). A
  human (or a future session with unblocked egress) should open the URL
  above once in a real browser to eyeball rendering/mobile layout before
  final Play Store submission — this is a lighter remaining check than
  "is it deployed at all," which is now answered yes.
- **`PRIVACY_POLICY_URL_REQUIRED` placeholders** — replaced in
  `docs/PLAY_STORE_RELEASE_CHECKLIST.md` and `docs/FINAL_QA_REPORT.md`
  with the real, build-confirmed URL above, each annotated with the
  same "build-confirmed, human should eyeball once" caveat.
  `docs/PLAY_STORE_LISTING.md` was checked this session and contains no
  `PRIVACY_POLICY_URL_REQUIRED` occurrence, so it needed no edit.
- **Play Store submission itself** — every other Play Store checklist
  item in `docs/PLAY_STORE_RELEASE_CHECKLIST.md` can proceed
  independently; this specific blocker is now resolved pending the
  one-time human eyeball check above.
