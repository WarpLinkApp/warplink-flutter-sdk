# warplink_flutter

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![pub package](https://img.shields.io/pub/v/warplink_flutter.svg)](https://pub.dev/packages/warplink_flutter)
[![CI](https://github.com/WarpLinkApp/warplink-flutter-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/WarpLinkApp/warplink-flutter-sdk/actions/workflows/ci.yml)

Deep linking, install attribution, and real-time analytics for Flutter. Handle Universal Links and App Links, resolve deferred deep links, and attribute installs with [WarpLink](https://warplink.app).

The plugin wraps the WarpLink iOS and Android SDKs. It needs no `AppDelegate`, `SceneDelegate`, or `MainActivity` edits. You add an Associated Domains entry on iOS, an intent filter on Android, and set Android `minSdk` to 26.

## Requirements

| Requirement | Minimum Version |
|-------------|----------------|
| Flutter | >= 3.38.0 |
| Dart | >= 3.10.0 |
| iOS | 15+ |
| Android | API 26+ (Android 8.0) |

The iOS side is integrated with Swift Package Manager. Flutter 3.44 and later enable it by default. On Flutter 3.38 to 3.43, the app owner runs this once:

```bash
flutter config --enable-swift-package-manager
```

The plugin supports iOS and Android only. On web and desktop every call throws `UnsupportedError`.

## Installation

```bash
flutter pub add warplink_flutter
```

## Native setup

Three edits, all of them configuration. No native code.

### iOS: Associated Domains

In Xcode, open the Runner target, go to **Signing & Capabilities**, add **Associated Domains**, and add:

```text
applinks:yourapp.aplnk.to
```

Find your app's subdomain in the dashboard: open the app, then **Settings**. Every app has its own link host, `{handle}.aplnk.to`. Add that exact host, never a wildcard such as `applinks:*.aplnk.to`. If your app existed before subdomains, or its links live on `aplnk.to`, also keep `applinks:aplnk.to` listed.

Or add it to `ios/Runner/Runner.entitlements`:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:yourapp.aplnk.to</string>
</array>
```

Enable the same capability for your App ID in the Apple Developer portal. The plugin registers itself for incoming links on both the `AppDelegate` and `UIScene` life cycles, so you add no delegate code.

### Android: minSdk and intent filter

Set `minSdk` to 26 in `android/app/build.gradle.kts`:

```kotlin
android {
    defaultConfig {
        minSdk = 26
    }
}
```

Add an `autoVerify` intent filter inside your main `<activity>` in `android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" android:host="yourapp.aplnk.to" />
</intent-filter>
```

Use your app's own subdomain as the host. If your app existed before subdomains, or its links live on `aplnk.to`, add a second `<data>` host line for `aplnk.to` in the same filter (or a second intent filter).

Keep the `android:launchMode="singleTop"` value that `flutter create` writes. No `MainActivity` code is needed.

### Flutter's own deep-linking flag

Flutter has its own deep link handler, enabled by default. Switch it off so your router does not also receive `https://yourapp.aplnk.to/<slug>` as a route, and let `onLink` drive navigation.

iOS, in `ios/Runner/Info.plist`:

```xml
<key>FlutterDeepLinkingEnabled</key>
<false/>
```

Android, inside `<activity>` in `AndroidManifest.xml`:

```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
```

If your app must keep Flutter's own deep linking for other, non-WarpLink domains, WarpLink cannot share the same links safely. Keep the WarpLink domains out of Flutter's route table. See [Routing with go_router](doc/go-router.md).

## Quick start

The SDK is **opt-out**: a bare `configure(apiKey:, onLink:)` wires cold-start, warm-start, and deferred deep links into one callback. No stream subscriptions, no lifecycle code.

Call `configure` from the `initState` of your root widget, and give `MaterialApp` a `navigatorKey`. A cold-start link can arrive before the first frame, when no navigator exists yet. `navigateTo` below waits for the navigator, so that link is never lost.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void navigateTo(String url) {
  final navigator = navigatorKey.currentState;
  if (navigator != null) {
    navigator.pushNamed('/product', arguments: url);
    return;
  }
  // The first frame has not built the navigator yet.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    navigatorKey.currentState?.pushNamed('/product', arguments: url);
  });
}

void main() => runApp(const App());

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    unawaited(
      WarpLink.configure(
        apiKey: 'wl_live_yoursdkkeyhere000000000000000000',
        onLink: (event) {
          switch (event) {
            case LinkEvent(:final deepLink):
              // Fires for cold start, warm start, AND deferred (first launch).
              // Tell deferred installs apart with deepLink.isDeferred.
              navigateTo(deepLink.deepLinkUrl ?? deepLink.destination);
            case ErrorEvent(:final error):
              debugPrint('WarpLink ${error.wireCode}: ${error.message}');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigatorKey,
        routes: <String, WidgetBuilder>{
          '/': (context) => const Placeholder(), // your home screen
          '/product': (context) => const Placeholder(), // your product screen
        },
      );
}
```

That is the whole happy path. `onLink` receives one delivery for every tap, and `navigateTo` in the samples that follow is the function above.

An exception thrown by your `onLink` while `configure` delivers a rejected key or a configuration error propagates out of the future that `configure` returns. An exception thrown for a link that arrives later surfaces as an uncaught error and does not stop the SDK. That link is not delivered again.

A background deferred check that fails, for example on a launch with no network, also reaches `onLink` as an `ErrorEvent`. The check stays open, so the next launch retries by itself. Treat the error as a report, not something to act on.

### Getting your SDK key

`apiKey` takes an **SDK key**, created under **Keys** > **SDK keys** in the dashboard. It is pre-scoped for link resolution and install attribution. API keys are a separate credential for backend scripts, CI, and AI agents, and they cannot record installs. Both share the `wl_live_` prefix, so pasting an API key here is an easy mistake: deep links keep resolving, but no installs appear in your dashboard. See the [Integration Guide](doc/integration-guide.md) for the full walkthrough.

### Using a custom link domain

`aplnk.to` works without `linkDomains`. On iOS, the Flutter plugin also recognizes `{handle}.aplnk.to` before configuration. On Android, declare your app host in `linkDomains` for a first launch without network access. If your links are on your own domain, declare it too, so the SDK recognizes it on the very first launch, before it has fetched your domain list and even with no network:

```dart
await WarpLink.configure(
  apiKey: 'wl_live_yoursdkkeyhere000000000000000000',
  linkDomains: ['links.yourapp.com'],
  onLink: handleLink,
);
```

Add `applinks:links.yourapp.com` to your Associated Domains and a second `<data>` host to your Android intent filter. See [Custom link domains](doc/api-reference.md#custom-link-domains).

## Manual mode

Set `automaticDeepLinks: false`, or omit `onLink`, to wire links yourself. `WarpLink.onDeepLink` emits every URL the app receives while it runs, resolved. `WarpLink.getInitialDeepLink()` returns the link that launched the app, once.

```dart
class _AppState extends State<App> {
  StreamSubscription<WarpLinkEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    unawaited(_listen());
  }

  Future<void> _listen() async {
    await WarpLink.configure(apiKey: 'wl_live_yoursdkkeyhere000000000000000000');

    _subscription = WarpLink.onDeepLink.listen((event) {
      switch (event) {
        case LinkEvent(:final deepLink):
          navigateTo(deepLink.destination);
        case ErrorEvent(:final error):
          debugPrint('Deep link error: ${error.message}');
      }
    });

    final launchLink = await WarpLink.getInitialDeepLink();
    if (launchLink != null) {
      navigateTo(launchLink.destination);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  // build as in the quick start
}
```

`onDeepLink` carries warm-start links. The launch link comes only from `getInitialDeepLink()`. A link that arrives before the first listener attaches is held and delivered when it does. If `getInitialDeepLink()` throws, call it again: the launch link is still waiting.

The deferred check still fires without `onLink`, because that request is what attributes the install. Call `checkDeferredDeepLink()` to read the match, or pass `automaticDeferredDeepLinks: false` to switch the check off.

## What one tap delivers

- **One delivery per tap.** `onLink` receives each tap once. A second tap on the same URL within 1.5 seconds counts as the same tap and is not delivered again. If a newer tap arrives while an older one is still resolving, only the newer tap reaches `onLink`.
- **`onLink` and `onDeepLink` are separate.** `onLink` receives only WarpLink links, from the automatic path. `onDeepLink` receives every URL the app is opened with, including foreign URLs as an `E_INVALID_URL` error, and does not apply the 1.5 second rule. A tap resolves once and both see the same result.
- **`getInitialDeepLink` and `onLink` do not overlap.** With the automatic path on, the launch link goes to `onLink` and `getInitialDeepLink()` returns `null`.
- **Deferred installs** arrive through `onLink` with `isDeferred: true`, after the launch link has been delivered or dropped.

### Known limits

- Delivery is at most once. A process death or engine disposal while a tap's final step is in flight can lose that one delivery, and so can an `onLink` that throws before it navigates. The SDK never offers a delivered link again. If the process dies after the server recorded the click and before the app received the answer, the relaunch is a new launch and the click can be counted a second time.
- On iOS, a newer tap supersedes an older one for navigation only. The older request still completes.
- On iOS, another plugin that handles a cold-start link first can hide it from WarpLink. See [Another plugin handles links first](doc/troubleshooting.md#7-another-plugin-handles-links-first-ios).

## Deferred deep links and attribution

Deferred deep links route a user who installs your app after tapping a link. With the default options the match arrives through `onLink` with `isDeferred: true`. To read it yourself:

```dart
final link = await WarpLink.checkDeferredDeepLink();
if (link != null && link.isDeferred) {
  navigateTo(link.deepLinkUrl ?? link.destination);
}

final attribution = await WarpLink.getAttributionResult();
if (attribution != null) {
  debugPrint('${attribution.matchType.name} ${attribution.matchConfidence}');
}
```

The check runs once per install and the native SDK caches the result. Later calls return the stored match, or `null` for a confirmed no-match. See [Deferred Deep Links](doc/deferred-deep-links.md) and [Attribution](doc/attribution.md).

### `matchGuaranteed` is not a credential

`matchGuaranteed` is `true` only for a deterministic match (the Play Install Referrer on Android; the iOS IDFV never produces one). A probabilistic match is a best guess drawn from a network-shaped fingerprint, so even a high score can name the wrong user.

```dart
if (attribution.matchGuaranteed) {
  personalizeOnboarding(attribution.linkId); // a reliable hint, not an identity
} else {
  showContent(attribution.linkId);           // route content, never identity
}
```

Use `matchGuaranteed` to pick a destination or personalize onboarding, for example by prefilling a referral code. Attribution is not identity: never sign a user in or restore an account from it. Authenticate the user and check authorization separately before showing private data, guaranteed match or not.

## Error handling

Every failure is a `WarpLinkException`, a sealed class with nine subclasses. Switch over it for exhaustive handling, or read `wireCode` (for example `E_NETWORK_ERROR`), the same code string the iOS, Android, and React Native SDKs use.

```dart
try {
  final link = await WarpLink.handleDeepLink(url);
  if (link != null) navigateTo(link.destination);
} on WarpLinkException catch (error) {
  switch (error) {
    case WarpLinkNetworkException():
      showMessage('No internet connection.');
    case WarpLinkLinkNotFoundException():
      showMessage('This link is no longer available.');
    case WarpLinkPasswordRequiredException():
      openInBrowser(url);
    default:
      debugPrint('${error.wireCode}: ${error.message}');
  }
}
```

`configure` does not throw for a malformed key. It prints a warning, delivers an `ErrorEvent` with `E_INVALID_API_KEY_FORMAT` to `onLink`, and leaves the SDK unconfigured. See [Error Handling](doc/error-handling.md) for every code and its fix.

## Debug logging

```dart
await WarpLink.configure(
  apiKey: 'wl_live_yoursdkkeyhere000000000000000000',
  debugLogging: true,
  onLink: handleLink,
);
```

iOS logs appear in the Xcode console with a `[WarpLink]` prefix. On Android, run `adb logcat -s WarpLink`. Warnings, such as a malformed or rejected key, print even with `debugLogging` off.

## Features

- **Opt-out by default:** one `configure(apiKey:, onLink:)` call turns on cold-start, warm-start, and deferred deep linking. Each is independently switchable.
- **Zero native edits:** no `AppDelegate`, `SceneDelegate`, or `MainActivity` code.
- **Universal Link and App Link handling:** resolve incoming links to destinations and custom parameters. See the [Integration Guide](doc/integration-guide.md).
- **Deferred deep links:** route users to specific content even after App Store or Play Store install.
- **Install attribution:** deterministic and probabilistic matching with confidence scores.
- **Typed API:** sealed events and exceptions that work with exhaustive `switch`.
- **No ATT required:** uses IDFV on iOS, exempt from App Tracking Transparency. No IDFA, no GAID, no user prompts.
- **Native SDK version:** `await WarpLink.sdkVersion()` returns the version the native SDK reports.
- **Attribution completion:** `await WarpLink.isAttributionComplete()` tells you whether the install check has finished.
- **Zero dependencies:** no third-party runtime dependencies. Only the Flutter SDK.

## Documentation

| Guide | Description |
|-------|-------------|
| [Integration Guide](doc/integration-guide.md) | Step-by-step setup from zero to working deep links |
| [API Reference](doc/api-reference.md) | Complete reference for all public types and methods |
| [Routing with go_router](doc/go-router.md) | Navigate from `onLink` with the deep-linking flag off |
| [Deferred Deep Links](doc/deferred-deep-links.md) | How deferred deep linking works and how to use it |
| [Attribution](doc/attribution.md) | Install attribution tiers and confidence scores |
| [Error Handling](doc/error-handling.md) | Every error case with recommended recovery actions |
| [Troubleshooting](doc/troubleshooting.md) | Common issues and solutions |
| [Firebase Migration](doc/firebase-migration.md) | Migrate from Firebase Dynamic Links to WarpLink |
| [Channel contract](doc/channel-contract.md) | How the Dart layer talks to the native SDKs |

Full documentation lives at [warplink.app/docs/sdks/flutter](https://warplink.app/docs/sdks/flutter).

## Links

- [WarpLink Dashboard](https://warplink.app)
- [Changelog](CHANGELOG.md)

## License

MIT License. See [LICENSE](LICENSE) for details.
