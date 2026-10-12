# iOS ↔ Android Parity — Gap Table & Scorecard

Reference: **Android v1.4.3** (monorepo `android/`, PR #224 branch: Credential
Manager sign-in + token contract, catalog from `config`, calls + transcript
call log, integrity self-reporting).

Baseline audited: the pre-existing iOS app (v1.1, formerly the standalone
`vasilyespana/callpages-ios` repo @ 70b6db8, imported into `ios/` by this PR) —
Swift/SwiftUI, ~1,060 LOC, cookie-session auth, **zero automated tests**, CI =
tag-only unsigned IPA build.

## Gap table (before → after)

| # | Feature (Android v1.4.3) | iOS before | iOS after this PR |
|---|---|---|---|
| 1 | Google sign-in: account picker, no password typing; `POST /api/v1/auth/google` {idToken} or device-flow code exchange → Bearer access+refresh pair; refresh on 401; `/api/me` validation | Web cookie flow only (ASWebAuth on `/api/auth/google`, no `mobile_app` param); cookie mirrored to Keychain; no tokens, no `/api/me` check, no refresh | Device flow via ASWebAuthenticationSession (`?mobile_app=1&login_id=`) + `mobile-status` polling + `POST /api/v1/auth/google/code` exchange → Keychain token pair; refresh-and-retry-once on 401; `/api/me` validated at launch. ID-token exchange implemented for the GoogleSignIn-SDK path (needs an iOS OAuth client ID — console step, not a code gap) |
| 2 | Pages list + detail read canonical `config` (#240 contract) | `Page` had `product_count` only, **no `config`** — products unrenderable | `config.products`/`config.collections` modeled and rendered |
| 3 | Products per page: real counts, grouped by collection | No products UI at all (unused `Product` struct) | Products section grouped by collections + ungrouped remainder, prices, thumbnails; header count from config |
| 4 | Calls list (cursor paging) + detail: summary, **transcript as the call log**, communications thread | Wrong field names (`from_number`, `duration_sec`, `started_at` don't exist in the payloads), transcript modeled as `String` (server sends turn arrays), detail never fetched | Correct models (`caller_phone`, `duration_ms`/`duration_seconds`), `GET /api/calls/:id` fetched, transcript turns rendered under "Call log", communications under "Messages", cursor pagination |
| 5 | Appointments (owner list) | Absent | New tab: `GET /api/owner/appointments` list + detail (customer, time, status, calendar sync, event link) |
| 6 | Settings: account, payment gateways, sign out | Web links + sign out only | Account + plan from `/api/me`, gateways list (`/api/gateways`), links, app version, sign out |
| 7 | AppIntegrityReporter → `POST /api/v1/mobile/report` | Absent | Full port: products-zero, pages-mismatch, call-log-empty, endpoint-error, unparseable-body; 10-min per-check throttle; payload builders unit-tested against the server whitelist |
| 8 | SignInFailureReporter → `POST /api/v1/auth/mobile/failure` | Absent | Full port: every device-flow step reports (open session, poll timeout, exchange, cancellation) |
| + | Activity feed | Model expected `{activity:[{type,text,created_at}]}` — a shape the worker has never sent; tab could only be empty | Real shape `{events:[{event_type,channel,page_title,ts}]}` modeled and rendered |
| + | Dashboard WebView | Present, but stuck on "Loading…" forever (nothing ever set `.loaded`) | Fixed; cookie sync before first load kept |
| + | Onboarding (zero-pages gate, native create, website research) | Present | Kept, rewired to the token API client |
| + | Tests & CI | None | XCTest unit suite (models, API contract incl. 401→refresh→retry, integrity checks, reporter payloads/throttle) + XCUITest MVR-VP screenshot flow, run on macos-15 for every PR touching `ios/**` |

Server change in this PR (minimal, contract-tested in `src/app-parity.test.js`):
the two mobile self-report endpoints now accept optional `platform`
(`"ios"` → error_log source `ios-app`) and `osVersion`. Absent/unrecognized
values keep the historical Android attribution byte-for-byte, so the fielded
Android app is unaffected.

## 📱 Mobile Release Verification Payload (this PR)

- **Platforms:** iOS (this PR). Android reference: v1.4.3 (PR #224).
- **User flow (simulator, stub fixtures):** [1] launch + mock auth → signed-in
  shell · [2] FTUE onboarding (zero-page account) · [3] native page creation →
  "Your page is ready!" · [4] page → products from config; call → transcript
  call log; appointments list.
- **Visual proof:** XCUITest attachments exported by CI as the
  `ios-simulator-screenshots` artifact (stage1-launch-mock-auth,
  stage2-ftue-details, stage3-template-picker, stage3-page-created,
  stage4-pages-list, stage4-page-products, stage4-call-log-transcript,
  stage4-appointments). **Simulator proof with demo data — not real-device
  proof.**
- **Cloud log proof:** GitHub Actions `.github/workflows/ios.yml` on this
  branch — first fully green run:
  https://github.com/vasilyespana/callpages/actions/runs/38175503587
  (unit tests **21/21**, UI tests **2/2**, unsigned IPA built; the final
  head re-runs the same workflow — see the PR verification comment for the
  final run link). Getting CI green took five iterations, all environmental
  or test-side, none hidden: Xcode pin removed (image runtimes match the
  default Xcode), simulator device now created in-job with the destination
  OS pinned, one Swift `await`-in-condition compile error, TokenStore
  in-memory cache (Keychain is unavailable in the unsigned test host),
  and a case-insensitive match for the uppercased "CALL LOG" section
  header.
- **Real-device verification:** NOT performed — impossible for unsigned IPAs
  (see blockers). No claim is made.

## Remaining blockers to "on a real iPhone"

1. **Free channel (chosen by Vasily, 2026-10-11):** personal-Apple-ID
   sideloading of the CI unsigned IPA — SideStore preferred; AltStore /
   Sideloadly alternates. Friction: 7-day signature expiry (refresh),
   3-app limit. Step-by-step: `ios/INSTALL-FREE.md`. The install itself is
   a manual, on-his-own-devices step — no automation on our side can (or
   should) hold his Apple ID.
2. **App Store / TestFlight:** requires Apple Developer Program enrollment
   ($99/yr) — **not chosen**; no other blocker if ever revisited (the app
   is a standard SwiftUI build with no signing identity baked in).
3. **GoogleSignIn SDK (optional polish):** the device flow already gives a
   picker-first, no-typing sign-in. The SDK path is implemented server-side
   and in `AuthService.signInWithIDToken`; it additionally needs an iOS
   OAuth client ID created in Google Cloud Console.
