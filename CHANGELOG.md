# Changelog

All notable changes to the WarpLink Flutter SDK will be documented in this
file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

