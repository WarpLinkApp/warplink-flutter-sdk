# Changelog

All notable changes to the WarpLink Flutter SDK will be documented in this
file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-10-10

The native SDK pins move to 1.1.1: iOS 1.1.1 (Swift Package Manager) and
Android 1.1.1 (`app.warplink:sdk`). The Dart API does not change.

### Changed

- **Rate limits are retried once.** The native SDKs this package wraps now
  retry a `429` from the link resolve or the attribution match once when its
  `Retry-After` is 5 seconds or less (1 second when the header is unreadable). A
  longer `Retry-After` is not retried. When the call still fails, it fails with
  `WarpLinkServerException` and `statusCode` 429.

### Clarification

`matchGuaranteed` is not a credential. Use it, like a confidence threshold, to
pick the destination the attribution result routes to. A probabilistic match is
a best guess from a fingerprint shaped by the network rather than the device, so
it can name the wrong user. Do not sign anyone in, or show personal data, on
this flag. Authenticate the user and check authorization separately.

On Android, a deterministic match comes from the Play Install Referrer. On iOS,
the IDFV lookup returns the install the device already has, with that install's
own match type and confidence. Neither lookup turns a probabilistic match into a
guaranteed one.

## [1.1.0] - 2026-10-08

Initial release, at parity with the WarpLink iOS, Android, and React Native
SDKs at 1.1.0. Each tap delivers once, at most once, and one `onLink` callback
receives cold-start, warm-start, and deferred deep links.

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

### Known limits

- Delivery is at most once. A process death or engine disposal while a tap's
  final step is in flight can lose that one delivery.
- On iOS, a newer tap supersedes an older one for navigation only. The older
  request still completes.
- On iOS, another plugin that handles a cold-start link first can hide it
  from WarpLink.
