# Deferred Deep Links

Deferred deep links let you route users to specific content even when they do not have your app installed yet. The user taps a link, installs your app from the App Store or Play Store, and on first launch the SDK matches them back to the original link.

## What Are Deferred Deep Links?

Standard Universal Links (iOS) and App Links (Android) only work when the app is already installed. Deferred deep links solve the "tap before install" problem:

1. User taps a WarpLink URL (for example, a product share link)
2. The app is not installed, so the user is redirected to the App Store or Play Store
3. User installs the app
4. On first launch, the SDK matches the install to the original tap
5. Your app routes the user to the intended content (for example, the shared product)

Without deferred deep links, the user lands on your default home screen with no context about what brought them there.

## How It Works

The deferred deep link flow has 8 steps:

1. **Click.** User taps a WarpLink URL in a browser or another app
2. **Signal capture.** WarpLink captures request signals (IP, Accept-Language, timezone) through a brief JavaScript interstitial
3. **Store redirect.** User is redirected to the App Store (iOS) or Play Store (Android)
4. **Install.** User installs and opens the app
5. **First launch detection.** The SDK detects this is the first launch of this install. The completion marker is a backup-excluded file on iOS and a file in the no-backup directory on Android, so a reinstall runs the check again. A separate device-seen marker (Keychain on iOS, `SharedPreferences` on Android) outlives an uninstall and only sets the reinstall flag.
6. **Signal collection.** The native SDK collects device signals: preferred language, timezone (IANA zone name plus the minute offset), and platform-specific identifiers (IDFV on iOS)
7. **Attribution request.** The SDK sends the signals to `/attribution/match`
8. **Match result.** The server matches against stored click signals and returns a `WarpLinkDeepLink` with `isDeferred: true`

## Flutter Implementation

**With the opt-out model, deferred deep links are automatic.** As long as you pass `onLink` to `configure` and leave `automaticDeferredDeepLinks` at its default (`true`), a first-launch match is delivered through `onLink` with `isDeferred: true`. When the install also came from a link tap, the check starts after that link is delivered or dropped. Call `configure` from the `initState` of your root widget, as in the [Integration Guide](integration-guide.md#step-8-configure-the-sdk-opt-out-model):

```dart
await WarpLink.configure(
  apiKey: 'wl_live_yoursdkkeyhere000000000000000000',
  onLink: (event) {
    if (event case LinkEvent(:final deepLink) when deepLink.isDeferred) {
      // The install matched an original tap. Route to the intended content.
      navigateTo(deepLink.deepLinkUrl ?? deepLink.destination);
    }
  },
);
```

Only a real link or an error reaches `onLink`. A confirmed no-match, the organic install, delivers nothing.

### Manual check (opt-out)

If you set `automaticDeferredDeepLinks: false`, or you omitted `onLink` and so have nowhere for the match to arrive, call `checkDeferredDeepLink()` early in the app lifecycle. Omitting `onLink` does not stop the check: the install is attributed either way, and the manual call reads the result.

```dart
class _StartupGate extends StatefulWidget {
  const _StartupGate({required this.child});
  final Widget child;

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final link = await WarpLink.checkDeferredDeepLink();
      if (link != null && link.isDeferred) {
        navigateTo(link.deepLinkUrl ?? link.destination);
      }
    } on WarpLinkException catch (error) {
      // Offline on first launch: show the default experience.
      debugPrint('Deferred deep link check failed: ${error.message}');
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const SizedBox.shrink();
}
```

## Confidence Scores

The match confidence depends on the matching method and the time elapsed since the tap:

| Scenario | Confidence | Match Type |
|----------|------------|------------|
| IDFV re-engagement (iOS, app was previously installed) | 1.0 | `deterministic` |
| Play Install Referrer (Android) | 1.0 | `deterministic` |
| Fingerprint, < 1 hour since click | 0.85 | `probabilistic` |
| Fingerprint, < 3 hours since click | 0.65 | `probabilistic` |
| Fingerprint, < 6 hours since click | 0.50 | `probabilistic` |
| Fingerprint, < 24 hours since click | 0.30 | `probabilistic` |
| 24 hours or more since click | no match | none |

The fingerprint rows are the ceilings for the zone-name variant that an SDK collecting a zone name sends. Two multipliers then reduce whichever ceiling applied: 0.6 when more than one claimable click shared the fingerprint, and 0.6 / 0.9 / 1.0 for a carrier-grade-NAT, household-IPv4, or IPv6 click address. See [Attribution](attribution.md) for the full table.

**Recommendation:** Route to specific content when `matchConfidence` is above 0.5. Show generic onboarding when below 0.5. `matchGuaranteed` is `true` only for a deterministic match. Use it to pick the destination, not as a credential, since a probabilistic match is a best guess from a network-shaped fingerprint and can name the wrong user. Attribution is not identity. Authenticate the user and check authorization separately before anything sensitive.

## Match Window Configuration

The match window controls how far back the server looks for matching clicks. It is **server-authoritative**, set per link in the WarpLink dashboard and enforced by the attribution API. It **defaults to 6 hours and cannot exceed 24**. There is no client-side setting to change it.

The window is short on purpose. The fingerprint key is a network, not a device: an IP address, a normalized language, and a timezone. Every phone behind one NAT that shares a language and timezone lands in the same bucket, so each extra hour lets another stranger join it while adding almost no real matches. It governs the probabilistic tier only. The deterministic paths are unaffected.

## Platform Differences

### iOS

- **Deterministic matching:** IDFV (Identifier for Vendor), for re-engagement when the app was previously installed. No ATT prompt needed.
- **Probabilistic matching:** Fingerprint (IP + preferred language + timezone, hashed server-side). Used for first-time installs.
- **No IDFA.** The SDK does not use IDFA and does not trigger App Tracking Transparency prompts.

### Android

- **Deterministic matching:** Play Install Referrer. The Play Store passes the click referrer through the install process. This is the most accurate method (confidence 1.0).
- **Probabilistic fallback:** If Play Install Referrer is unavailable (sideloaded app, Play Services missing), the SDK falls back to fingerprint matching (IP + preferred language + timezone).

## Code Example with Confidence Branching

```dart
void routeDeferred(WarpLinkDeepLink link) {
  if (!link.isDeferred) return;
  final confidence = link.matchConfidence ?? 0;

  // A deterministic match is a reliable hint for onboarding, never an identity.
  if (link.matchGuaranteed) {
    prefillReferralCode(link);
  }

  if (confidence > 0.5) {
    final productId = link.customParams['product_id'] as String?;
    if (productId != null) {
      openProduct(productId);
    } else {
      openWebView(link.destination);
    }
  } else if (confidence > 0.3) {
    showSuggestion(link.destination); // "Were you looking for this?"
  }
  // Below 0.3: ignore and show default onboarding.
}
```

## Caching Behavior

- The SDK checks for a deferred deep link only on the first launch of an install.
- The first-launch marker is split into "attempted" and "completed". It is consumed only on a definitive server response. If the first attempt fails (for example offline), the check retries on the next launch.
- The result, match or no match, is cached by the native SDK once completed.
- Later calls to `checkDeferredDeepLink()` return that cached result without a network request: the same match if one was found, `null` if there was none.
- The attribution check completes exactly once per app install.

## Edge Cases

### Offline First Launch

If the device has no network connectivity on first launch, the check fails with `WarpLinkNetworkException` (`E_NETWORK_ERROR`). It surfaces through `onLink` as an `ErrorEvent`, or as a thrown exception from a manual `checkDeferredDeepLink()` call. The first-launch marker is **not** consumed on a failed attempt, so the check retries on the next launch once connectivity is restored.

**Recommendation:** Handle the error gracefully and show your default first-launch experience. The retry happens on its own.

### App Reinstall

A reinstall counts as an install. The deferred check runs again on the first launch after a reinstall, on both platforms, so the install is attributed and the user reaches the content they tapped for. Deleting the app and installing it again is enough to retest on iOS and on Android.

The SDK reports whether the install followed an earlier one to the attribution API, so the two can be measured separately. It is not surfaced to your app.

Two separate native markers produce this, and neither is readable from Dart:

- The **gate** answers "has attribution already completed for this install?". It is tied to the install and does not come back from a delete or from a restored backup, so it can never suppress the check on a reinstall.
- The **device-seen marker** answers "has this device ever completed attribution?". It survives a delete and a restore, and it gates nothing. It only tags the attribution request so a reinstall can be counted separately.

### Multiple Links Tapped Before Install

A fingerprint is a network rather than a device, so several clicks can land under one key: your own user tapping twice, or two strangers behind the same NAT. WarpLink keeps them as a list, newest first, up to 10 per fingerprint. A second tap does not overwrite the first, so the install that belongs to the earlier tap can still find it.

The server matches against the newest entry your app is allowed to claim, and removes only that entry once it becomes an install. When more than one entry was claimable, the match is scored lower to reflect that the answer was picked from a set.

### Match Window Expiry

If the user installs the app after the match window has expired (6 hours by default, 24 at most), the deferred deep link is not found. `checkDeferredDeepLink()` returns `null`.

## Related Guides

- [Attribution](attribution.md): detailed explanation of matching tiers
- [Error Handling](error-handling.md): handling deferred deep link errors
- [Troubleshooting](troubleshooting.md): common deferred deep link issues
