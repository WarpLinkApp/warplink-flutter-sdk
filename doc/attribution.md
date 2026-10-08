# Install Attribution

WarpLink uses two tiers of attribution matching to connect app installs and opens to the links that drove them. The native SDK collects device signals and sends them to the WarpLink API, which determines the match.

## Overview

When a user interacts with a WarpLink URL, WarpLink captures signals from the click. When the app opens for the first time after install, the SDK collects device-side signals. The server compares both sets of signals to determine if there is a match.

The result is returned as an `AttributionResult` with `matchType`, `matchConfidence`, and `matchGuaranteed` properties. The Flutter plugin adds no signal of its own. The native iOS and Android SDKs collect everything, so attribution in a Flutter app is identical to a native app.

## Deterministic Matching

Deterministic matching uses stable device identifiers that guarantee an exact match.

### iOS: IDFV

**Used for:** Re-engagement, when the app is already installed or was previously installed on the same device.

| Property | Value |
|----------|-------|
| Signal | IDFV (Identifier for Vendor) |
| Match type | `deterministic` |
| Confidence | 1.0 (exact match) |
| Requires ATT? | No |
| Requires user permission? | No |

IDFV is a UUID unique to the combination of your app's vendor and the device. It does not require any user permission and is **exempt from App Tracking Transparency (ATT)**. The SDK includes IDFV in attribution requests automatically.

### Android: Play Install Referrer

**Used for:** First-install attribution. The Play Store passes the click referrer through the install process.

| Property | Value |
|----------|-------|
| Signal | Play Install Referrer |
| Match type | `deterministic` |
| Confidence | 1.0 (exact match) |
| Requires Google Play? | Yes |
| Requires user permission? | No |

When available, Play Install Referrer provides deterministic attribution with no fingerprint ambiguity. It falls back to probabilistic matching if Play Services is unavailable (sideloaded apps, alternative stores).

## Probabilistic Matching (Enriched Fingerprint)

**Used for:** First-install attribution when deterministic signals are not available.

| Property | Value |
|----------|-------|
| Signals | IP address + preferred language + timezone |
| Match type | `probabilistic` |
| Confidence | 0.20 to 0.85 before the multipliers below, never `matchGuaranteed` |
| Requires ATT? | No |
| Requires user permission? | No |

When a user taps a WarpLink URL, a brief JavaScript interstitial captures request-side signals. On first app launch, the SDK collects the same categories of signals from the device and sends them to the attribution API. The server computes the fingerprint hash from both sets (IP is derived server-side from the request) and checks for a match.

The native SDKs send the IANA timezone name (`timezone`, for example `America/Toronto`) alongside the minute offset (`timezone_offset`). The zone name carries far more entropy than the offset, roughly 340 zones against roughly 38 offsets, and it does not shift at a daylight-saving boundary. The server prefers the zone name and falls back to the offset for older SDKs.

> **Note:** the fingerprint intentionally excludes User-Agent and screen dimensions. They differ between a mobile browser and a native app and never match, so including them only adds noise.

## App Identity

Every attribution request also carries the host app's identifier: `app_bundle_id` on iOS, `app_package_name` on Android. It is not a fingerprint component and does not affect confidence.

An API key is scoped to your organization, not to a single app. If your organization ships more than one app, this identifier is what lets the server attribute an install to the app it happened in. The native SDKs read it from the app itself, so there is nothing to configure and no Dart field to pass. An SDK key tied to one app acts only as that app.

### Confidence by Time Window

The elapsed time and the fingerprint variant set the ceiling. `enriched_tz` is the zone-name variant that an SDK collecting a zone name sends. `enriched` is the offset variant kept for older SDKs. `basic` is the language-only key the server tries last.

| Time Since Click | `enriched_tz` | `enriched` | `basic` |
|------------------|---------------|------------|---------|
| < 1 hour | 0.85 | 0.80 | 0.70 |
| < 3 hours | 0.65 | 0.60 | 0.50 |
| < 6 hours | 0.50 | 0.45 | 0.35 |
| < 24 hours | 0.30 | 0.25 | 0.20 |
| 24 hours or more | no match | no match | no match |

Confidence decreases over time because IP addresses and network conditions change. Those values are ceilings, and two multipliers pull the score down when the answer was less certain than the clock alone suggests:

| Condition | Multiplier |
|-----------|------------|
| More than one claimable click sat in the fingerprint's bucket | 0.6 |
| The click's IP was carrier-grade NAT or private | 0.6 |
| The click's IP was a household IPv4 address | 0.9 |
| The click's IP was IPv6 | 1.0 |

### The match window

The match window is server-side, set per link in the dashboard. It **defaults to 6 hours and cannot exceed 24**.

The window is short on purpose. The fingerprint key is a network, not a device: an IP address, a normalized language, and a timezone. Every phone behind one NAT that shares a language and timezone lands in the same bucket, so each extra hour lets another stranger join it while adding almost no real matches. This governs the probabilistic tier only. The deterministic paths (IDFV on iOS, Play Install Referrer on Android) read stored click data instead of the fingerprint bucket, so the window does not apply to them.

## Interpreting Match Results

### Using `getAttributionResult()`

```dart
final attribution = await WarpLink.getAttributionResult();
if (attribution != null) {
  debugPrint('Link ID: ${attribution.linkId}');
  debugPrint('Match type: ${attribution.matchType.name}');
  debugPrint('Confidence: ${attribution.matchConfidence}');
  debugPrint('Guaranteed: ${attribution.matchGuaranteed}');
  debugPrint('Is deferred: ${attribution.isDeferred}');
}
```

`getAttributionResult()` returns `null` for a genuine no-match (organic install). A non-null but malformed native payload throws `WarpLinkDecodingException` (`E_DECODING_ERROR`), so you can tell "no attribution" apart from "the data could not be read".

### `matchGuaranteed` is not a credential

`matchGuaranteed` is `true` only when the match came from a deterministic signal (IDFV on iOS, Play Install Referrer on Android). Use it, like `matchConfidence`, to pick the destination or personalize onboarding (for example, prefilling a referral code), not to authenticate the user. Attribution is not identity: never sign a user in, restore an account, or show personal data because of a match, guaranteed or not. Authenticate the user and check authorization separately. A probabilistic match is a best guess drawn from a network-shaped fingerprint, so even a high score can name the wrong user.

```dart
if (attribution.matchGuaranteed) {
  personalizeOnboarding(attribution.linkId); // a reliable hint, not an identity
} else {
  showContent(attribution.linkId);           // route content, never identity
}
```

### Reinstalls are attributed, and flagged

A reinstall counts as an install. Attribution runs again on the first launch after a reinstall, on both platforms, so the install is measured and the user still reaches the content they tapped for.

The SDK reports which of the two it was to the attribution API, so a reinstall can be measured separately. It is not surfaced to your app.

### Recommended Thresholds

| Confidence | Recommended Action |
|------------|-------------------|
| 1.0 (deterministic) | Route directly to content |
| > 0.5 (probabilistic) | Route to content, high confidence |
| 0.3 to 0.5 | Show content with a confirmation (for example, "Were you looking for...?") |
| < 0.3 | Show generic onboarding, too uncertain |

### Confidence-Based Branching

```dart
final attribution = await WarpLink.getAttributionResult();
if (attribution == null) {
  showOnboarding(); // organic install
} else if (attribution.matchConfidence >= 0.5) {
  navigateToLink(attribution.linkId);
} else if (attribution.matchConfidence >= 0.3) {
  showSuggestion(attribution.linkId);
} else {
  showOnboarding(); // too uncertain, treat as organic
}
```

## Privacy Considerations

The WarpLink SDK is designed with privacy as a core principle.

### What the SDK Does NOT Collect

- **IDFA** (iOS Advertising Identifier): never accessed
- **GAID** (Google Advertising ID): never accessed
- **Android ID**: never accessed
- **User-Agent**: not collected for attribution
- **Screen dimensions**: not collected for attribution
- **Location data**: not collected
- **Contacts or personal data**: not collected
- **App usage data**: no screens, sessions, taps, or in-app events. The reinstall flag below is install history, not usage.
- **Cross-app identifiers**: not used

### What the SDK Collects

| Signal | Purpose | Platform |
|--------|---------|----------|
| Preferred language | Fingerprint component | Both |
| Timezone name | Fingerprint component | Both |
| Timezone offset | Fingerprint component (fallback key) | Both |
| Reinstall flag (`is_reinstall`) | Routes a returning user back to the content they tapped, and separates reinstalls from first installs afterwards | Both |
| IDFV | Deterministic matching (re-engagement) | iOS only |
| Play Install Referrer | Deterministic matching (first install) | Android only |

The IP address used in the fingerprint is derived server-side from the request. The SDK never sends a precomputed fingerprint or the device's IP.

The reinstall flag is retained on the install record, so it outlives the request that carried it. Everything else in that table is used for the match and nothing else.

### Store privacy declarations

A Flutter app ships on both stores and each one wants a different thing from you.

- **App Store.** The iOS SDK ships a privacy manifest and Xcode folds it into your app's privacy report automatically. See [the iOS privacy manifest section](https://github.com/WarpLinkApp/warplink-ios-sdk/blob/main/docs/attribution.md#privacy-manifest) for what it declares.
- **Google Play.** Android has no equivalent, so nothing reaches Google on its own and the Data safety form in your Play Console listing is yours to fill in. [The Android Data safety mapping](https://github.com/WarpLinkApp/warplink-android-sdk/blob/main/docs/attribution.md#play-data-safety-mapping) gives you a field-by-field table to copy from.

Neither one answers for your whole app. Both cover only what this SDK contributes.

### ATT Compliance (iOS)

- The SDK does **not** prompt for App Tracking Transparency permission
- IDFV is [exempt from ATT](https://developer.apple.com/documentation/apptrackingtransparency). It does not track users across apps
- The SDK does **not** interfere with your app's own ATT strategy
- You can use WarpLink alongside any ATT implementation

### Data Handling

- Device signals are sent to the WarpLink API over HTTPS
- Fingerprint data is used solely for attribution matching
- No cross-app tracking is performed
- IDFV is scoped to your vendor. WarpLink cannot use it to track users across different vendors' apps
- Only ephemeral device signals are collected, for the purpose of attribution

## Related Guides

- [Deferred Deep Links](deferred-deep-links.md): how deferred deep linking uses attribution
- [API Reference](api-reference.md): `AttributionResult` and `WarpLinkDeepLink` documentation
- [Channel contract](channel-contract.md): how Dart talks to the native SDKs
