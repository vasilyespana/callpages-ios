# CallPages Merchant for iOS

Native iOS companion for [CallPages](https://callpages.me) merchants —
pages, products, call logs with transcripts, appointments, activity, and
settings. Feature parity with the Android app (v1.4.3); see
[IOS-PARITY.md](IOS-PARITY.md) for the gap table and verification payload.

> **Public distribution mirror.** Development lives in the monorepo
> [`vasilyespana/callpages`](https://github.com/vasilyespana/callpages)
> under `ios/` — that repo is private, and GitHub release assets in
> private repos are not anonymously downloadable. This repo mirrors the
> same `ios/` source so the unsigned IPA can be published from a public
> repo: the SideStore source feed downloads the release asset
> anonymously. Source files here are byte-identical copies of the
> monorepo's `ios/` at the mirrored version (v1.4.3); file bugs and
> features against the monorepo.

## Features

- **Sign in with Google** — system-browser account picker (device flow),
  Bearer session with automatic refresh; no password typing in the app
- **Pages & products** — real catalog from each page's config, grouped by
  collection
- **Calls** — summaries plus the full transcript as the call log, and the
  callback/voicemail message thread
- **Appointments** — bookings from your pages, with calendar-sync status
- **Activity** — unified event feed
- **Settings** — account, plan, payment gateways, sign out
- **Self-reporting** — sign-in failures and impossible states (e.g. pages
  loaded but zero products) report themselves to the server automatically;
  nobody has to notice a parity bug first
- **Onboarding** — new accounts create their first page natively, including
  website product import

## Build

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project CallPages.xcodeproj -scheme CallPages \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' test
```

CI (`.github/workflows/ios.yml`) runs the same on macos-15 for every PR,
exports the simulator screenshots, and builds the **unsigned IPA**.
On `ios-v*` tags the IPA is attached to a GitHub Release in this repo —
that public release asset is what the SideStore source feed
(`sidestore-source.json` in `vasilyespana/maps2uber-android`) points at
for CallPages.

## Install on a real iPhone (free channel)

The IPA is unsigned. The free install channel is personal-Apple-ID
sideloading — step-by-step in [INSTALL-FREE.md](INSTALL-FREE.md)
(SideStore preferred; AltStore / Sideloadly alternates). App Store /
TestFlight distribution would need the $99/yr Apple Developer Program,
which is not the chosen path.

## Layout

- `Sources/CallPages/` — the app (SwiftUI, iOS 17+, zero third-party deps)
- `Tests/CallPagesTests/` — XCTest: API contract, models, integrity checks,
  reporter payloads
- `Tests/CallPagesUITests/` — MVR-VP simulator screenshot flow (stub fixtures
  via the `-uitest-stub` launch argument; demo data only)
- `project.yml` — XcodeGen spec (app + both test targets)
