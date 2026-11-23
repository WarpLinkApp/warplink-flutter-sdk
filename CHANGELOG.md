# Changelog

All notable changes to the WarpLink Flutter SDK will be documented in this
file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.1] - 2026-11-22

### Changed

- `WarpLinkPasteButton` imports `package:flutter/widgets.dart` instead of
  `package:flutter/material.dart`, because it uses no Material widget. No
  behavior changes.
- The README links the Tether guide at https://warplink.app/docs/tether.

## [1.4.0] - 2026-11-22

### Added

- **`WarpLink.getDeferredCheckStatus()`.** A read-only status that tells a check
  the SDK skipped from a check that found no match. It returns a
  `DeferredCheckStatus` whose `state` is one of `DeferredCheckState.notChecked`,
  `checking`, `matched`, `noMatch`, `waiting`, `skippedOldInstall` or
  `stopped`. For `waiting`, `retryAt` is the time the next check is allowed. It
  sends no request, and it comes from state stored on the device, so a
  relaunch keeps it. A `wl_test_` key never reports `waiting`,
  `skippedOldInstall` or `stopped`.
- **Tether handoff.** A person who taps a link in a browser that cannot open
  your app can hand the install a code through the clipboard. Three read modes
  say how the SDK gets that code: `TetherReadMode.pasteButton` (the default),
  `automatic` and `onCall`. Pass one to `WarpLink.configure(tetherReadMode:)`.
- **`WarpLinkPasteButton`.** The iOS system paste control as a widget. A tap
  reads the clipboard and calls `onResult` with a `TetherReadResult`, and iOS
  shows no paste alert. It takes no space on Android and below iOS 16.
- **`WarpLink.readTether()`.** Reads the clipboard once and returns a
  `TetherReadResult`: `TetherMatched`, `TetherNoCode`, `TetherUnusable` or
  `TetherTest`. Android reads no clipboard and always returns `TetherNoCode`.
- **Test receipts.** `WarpLink.lastTetherTestReceipt()` returns the receipt of
  the last test code (`wl1t_`) a `wl_test_` key sent.

### Changed

- When a Tether code resolves an exact link after `onLink` already received an
  estimate, through `WarpLink.readTether()` or `WarpLinkPasteButton`, `onLink`
  fires again with the exact link (`MatchType.deterministic`). The same link is
  never delivered twice.
- **Far fewer repeat attribution requests.** The first-launch check is still
  automatic and still sends one request when it succeeds. When it does not
  succeed, it now asks less often. The native SDKs make these decisions, and
  this package runs the check through them, so it follows the same rules.
  - An install older than 30 days sends no request and answers no match.
  - An install older than 48 hours sends no raw device signals.
  - After a check fails, the next one waits 15 minutes, then 1 hour, 6 hours
    and 1 day. The SDK stops for good 3 days after the first failure. A call
    made during a wait answers no match and sends nothing.
  - The check starts only while your app is on screen. A call made earlier
    waits and then runs.
  - A `wl_test_` key skips the age limits and the waits, so you can test a
    first launch as often as you like.
- Calling `WarpLink.configure` with the same key and the same options keeps
  the running session. It does not configure the native SDK again. A new
  `onLink` function replaces the old one and receives the results. If the
  first-launch check has not finished and none is running, the call asks the
  native SDK for one more check, at most once a minute. The native SDK decides
  whether that sends a request: a check inside its wait, or on an install past
  the age limit, sends nothing. A `wl_test_` key follows the same minute. A
  different key or different options still rebuilds the SDK.
- The native SDKs this package depends on are now 1.4.0 on Android and iOS.

## [1.3.0] - 2026-11-02

### Added

- **`WarpLink.clearAttribution()`.** Forgets this install's attribution so the
  next first launch can be tested again. It works with a `wl_test_` key and
  does nothing, completing normally, with a `wl_live_` key. With a Test key and
  `automaticDeferredDeepLinks` on, a check in flight is discarded and a fresh
  check starts; a match reaches `onLink`.
- **Storage failures from `clearAttribution()`.** When a stored item could not
  be deleted it throws `WarpLinkDecodingException` with the message "Could not
  clear stored attribution data." No error type gains a case. Calling again is
  safe.

### Changed

- The native SDKs this package depends on are now 1.3.0 on Android and iOS.

## [1.2.0] - 2026-10-25

### Added

- **`WarpLink.redeemInvitation(text)`.** Pass the text a person pasted. It
  returns a `WarpLinkDeepLink` when the text is an invitation that matched, and
  `null` when it is not an invitation. A refused invitation throws a
  `WarpLinkServerException` whose message tells the person to open the link
  again. After a network failure the native SDK keeps the invitation and tries
  again on a later launch, a bounded number of times. A resumed invitation is
  delivered through `getAttributionResult()` and `claimReferral`, not through
  `onLink`.
- **`WarpLink.claimReferral(installerId)`.** Claims the referral behind this
  install for the person who just signed up. It returns a `ReferralClaimResult`
  whose `status` is `claimed`, `flagged`, `ignored` or `none`. Status `none` is
  an answer, not an error. Calling again with the same id returns the same
  claim.
- **Evidence fields on `WarpLinkDeepLink` and `AttributionResult`.**
  `attributionId`, `matchMethod`, `evidenceClass`, `replayState`,
  `capturedParams` and `tappedAt`. A payload from an older native SDK, or a
  value this version does not know, reads as `null` (`{}` for
  `capturedParams`). An unknown value is never read as exact.
- New public types: `MatchMethod`, `EvidenceClass`, `ReplayState`,
  `ReferralClaimStatus` and `ReferralClaimResult`.

### Changed

- The native SDK pins move to 1.2.0: iOS 1.2.0 (Swift Package Manager) and
  Android 1.2.0 (`app.warplink:sdk`).
- The package reads no clipboard. The host app passes the pasted text.

## [1.1.1] - 2026-10-10

The native SDK pins move to 1.1.1: iOS 1.1.1 (Swift Package Manager) and
Android 1.1.1 (`app.warplink:sdk`). The Dart API does not change.

### Changed

- **Rate limits are retried once.** The native SDKs this package wraps now
  retry a `429` from the link resolve or the attribution match once when its
  `Retry-After` is 5 seconds or less (1 second when the header is unreadable). A
  longer `Retry-After` is not retried. When the call still fails, it fails with
  `WarpLinkServerException` and `statusCode` 429.

### Match guarantee

`matchGuaranteed` is not a credential. Use it, like a confidence threshold, to
pick the destination the attribution result routes to, and keep sign-in and
personal data on your own authentication.

On Android, a deterministic match comes from the Play Install Referrer. On iOS,
the IDFV lookup returns the install the device already has, with that install's
own match type and confidence.

## [1.1.0] - 2026-10-08

Initial release, at parity with the WarpLink iOS, Android, and React Native
SDKs at 1.1.0. Each tap delivers at most once, and one `onLink` callback receives
cold-start, warm-start, and deferred deep links.

### Added

- `WarpLink.configure()` with the opt-out model: a bare
  `configure(apiKey: ..., onLink: ...)` wires cold-start, warm-start, and
  deferred deep links into one callback. `automaticDeepLinks` and
  `automaticDeferredDeepLinks` switch each piece off.
- One delivery per tap: a repeat of the same URL within 1.5 seconds is
  delivered once, and a newer tap supersedes an older one that is still
  resolving. `onLink` and the `onDeepLink` stream see the same result for a tap.
- `handleDeepLink`, `checkDeferredDeepLink`, `getAttributionResult`,
  `isAttributionComplete`, `isConfigured`, `sdkVersion`, `isWarpLinkUrl`,
  `getInitialDeepLink`, and the `onDeepLink` stream.
- Typed results (`WarpLinkDeepLink`, `AttributionResult`, `MatchType`) and a
  sealed `WarpLinkException` hierarchy with nine subclasses.
- Custom link domains through `linkDomains`.
- Guides under `doc/`: integration, API reference, routing with `go_router`,
  deferred deep links, attribution, error handling, troubleshooting, and
  migration from other link providers.
- Native SDKs pinned to iOS 1.1.0 (Swift Package Manager) and Android 1.1.0
  (`app.warplink:sdk`).

