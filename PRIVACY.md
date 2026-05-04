# Privacy Policy — BlackHole

_Last updated: May 4, 2026_

BlackHole is a real-time relativistic black-hole simulator for macOS and
iOS, published by **Orch Aerospace, Inc.** ("we", "us"). This document
describes what data the app does and does not handle. The short version:
**we don't collect anything from you.**

## Data we collect

**None.** BlackHole does not collect, transmit, store on our servers,
or share any personal data, usage data, identifiers, or contact
information.

We do not run analytics. We do not use crash-reporting SDKs. We do not
embed Firebase, Sentry, Mixpanel, Amplitude, Segment, PostHog, Google
Analytics, or any other third-party telemetry. The macOS and iOS
binaries make no `URLSession` calls of their own.

## Data the system handles on our behalf

Two things flow through Apple's first-party services. We never see them:

1. **StoreKit purchase data.** When you subscribe to BlackHole Pro, your
   purchase, receipt, and renewal status are handled by Apple's StoreKit
   framework. We receive only an opaque entitlement bit (Pro: yes / no)
   from the system. We do not receive your name, payment method, Apple
   ID, billing address, or any other identifying information. Apple's
   handling of that data is governed by [Apple's Privacy
   Policy](https://www.apple.com/legal/privacy/).

2. **Subscription receipt validation.** Performed automatically by the
   operating system through StoreKit. No data leaves your device that
   we can see.

## Data stored locally on your device

These never leave your device:

- **Simulation parameters** (mass, spin, lensing strength, disk
  settings, quality preset, etc.) — saved via `UserDefaults` so the
  app reopens to your last view.
- **Pomodoro timer settings and session count** — saved via
  `UserDefaults`.
- **Subscription entitlement cache** — Apple caches your StoreKit
  entitlement locally; we read the cached bit.

You can wipe all of this by deleting the app.

## Photos library access (iOS only)

The iOS build includes a "Save as Wallpaper" button. Tapping it asks
you for permission to **write** to your Photos library and saves the
current frame as a still PNG to your camera roll. The app does **not**
read your existing photos, scan your library, or transmit anything.
The permission grant is one-way: write only.

You can revoke access at any time in **Settings → Privacy & Security →
Photos → BlackHole**.

## Network access

The macOS App Sandbox entitlements declare `network.client = false`
and `network.server = false`. The macOS app cannot make outbound
network connections of its own. The iOS build similarly does not
initiate network requests outside system services.

## Children's privacy

BlackHole is not directed at children under 13. We do not knowingly
collect any data from anyone, of any age.

## Changes to this policy

If this ever changes, we will update the "Last updated" date at the
top of this document and post the new version at the canonical URL
below. Material changes will also be reflected in the App Store
listing.

## Contact

For privacy questions, open an issue at
<https://github.com/wonmor/blackhole-simulation/issues>.

## Canonical URL

The authoritative version of this policy lives at:

<https://github.com/wonmor/blackhole-simulation/blob/main/PRIVACY.md>
