# CallPages Merchant for iOS

Native iOS companion for [CallPages](https://callpages.me/) merchants — pages, call logs, activity, and settings in your pocket.

## Features (v1.0)
- **Sign in with Google** (same account as the web dashboard)
- **Pages**: list all your CallPages, see product counts and status
- **Call logs**: browse calls per page, read summaries and full transcripts
- **Activity**: live activity feed
- **Settings**: quick links to the web dashboard, sign out

Roadmap: catalog manager (edit products), WebRTC outbound dialer, push notifications.

## Install (free, no Apple Developer account needed)

Apple's App Store requires a $99/year membership, so this app is distributed free through:

1. **AltStore** (recommended) — add the CallPages source in AltStore, then install with one tap.
2. **TrollStore** — download the IPA from [GitHub Releases](../../releases).
3. **Sideloadly** — download the IPA from [GitHub Releases](../../releases).

## Build

Push a `v*` tag and GitHub Actions builds an unsigned IPA on macOS automatically. Built with XcodeGen from `project.yml`.
