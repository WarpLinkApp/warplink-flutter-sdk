# Integration Guide

Step-by-step guide to integrate the WarpLink Flutter SDK into your app. You go from zero to working deep links in under 30 minutes, with no native code.

## Prerequisites

- Flutter 3.38.0 or later, Dart 3.10.0 or later
- iOS 15+ and/or Android API 26+ (Android 8.0)
- Swift Package Manager enabled for Flutter iOS builds (see Step 4)
- A physical iOS device (Universal Links do not work on the iOS Simulator)
- An Android device or emulator (App Links verification requires network access)

## Step 1: Create a WarpLink Account

Sign up at [warplink.app](https://warplink.app). The free tier includes 10,000 clicks per month.

## Step 2: Register Your App

A Flutter app is one WarpLink app that covers both platforms. Register the app once with both platforms selected. Do not create a second app for the other platform.

1. In the WarpLink dashboard, go to **Apps**
2. Click **Register App** and select both **iOS** and **Android** in the same form
3. Fill in the iOS details:
   - **Bundle ID** (for example, `com.yourcompany.yourapp`)
   - **Team ID** (found in the Apple Developer portal under Membership)
   - **App Store URL** (or leave blank during development)
4. Fill in the Android details in the same form:
   - **Package name** (for example, `com.yourcompany.yourapp`)
   - **SHA256 fingerprint** (see [how to get your SHA256 fingerprint](#get-sha256-fingerprint) below)
   - **Play Store URL** (or leave blank during development)
5. Save the app. The form does not save while a selected platform has no Bundle ID or Package name. WarpLink then generates the Apple App Site Association (AASA) file and the `assetlinks.json` file automatically. Both files need the Team ID and the SHA256 fingerprint, so enter them before you test links.

## Step 3: Create an SDK Key

WarpLink issues two kinds of credentials. Mobile apps need an **SDK key**, which is pre-scoped for link resolution and install attribution. API keys are for backend scripts, CI, and AI agents, and they cannot record installs.

1. Go to **Keys** in the dashboard
2. Open the **SDK keys** tab and click **Create SDK key**
3. Name it (for example, `Flutter production`) and create it
4. Copy the key. It is shown once, so store it securely

> **Using an API key here is the most common setup mistake.** Deep links still resolve, so the integration looks healthy, but every attribution call is rejected and no installs appear in your dashboard.

## Step 4: Install the SDK

```bash
flutter pub add warplink_flutter
```

The iOS side of the plugin is delivered through Swift Package Manager. Flutter 3.44 and later enable Swift Package Manager by default. On Flutter 3.38 to 3.43, run this once on the machine that builds the app:

```bash
flutter config --enable-swift-package-manager
```

There is no Podfile change and no `pod install` step. Android links automatically through Gradle.

## Step 5: iOS Setup

### Add the Associated Domains entitlement

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select the **Runner** target
3. Go to **Signing & Capabilities**
4. Click **+ Capability** and add **Associated Domains**
5. Add the domain: `applinks:aplnk.to`

If you manage entitlements by hand, add this to `ios/Runner/Runner.entitlements`:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:aplnk.to</string>
</array>
```

### Apple Developer portal

1. Go to [developer.apple.com](https://developer.apple.com) > **Certificates, Identifiers & Profiles**
2. Select your App ID
3. Enable the **Associated Domains** capability
4. Regenerate your provisioning profile if needed

### No AppDelegate or SceneDelegate edits

The plugin registers with Flutter's application and scene delegate chain, so incoming Universal Links and custom-scheme URLs reach the SDK on their own. This holds for apps on the `AppDelegate` life cycle and apps on the `UIScene` life cycle. Cold start and warm start are both covered.

One rule applies if your app already overrides link methods. If your own `AppDelegate` or `SceneDelegate` implements `application(_:continue:restorationHandler:)`, `application(_:open:options:)`, `scene(_:continue:)`, or `scene(_:openURLContexts:)`, call `super` from it. Flutter's chain delivers the URL to plugins from `super`. See [Troubleshooting](troubleshooting.md#1-universal-links-not-working-ios).

## Step 6: Android Setup

### Set minSdk to 26

The WarpLink Android SDK needs API 26. Flutter's default `minSdk` can be lower, and the manifest merge then fails. In `android/app/build.gradle.kts`:

```kotlin
android {
    defaultConfig {
        minSdk = 26
    }
}
```

If your project uses the Groovy file `android/app/build.gradle`, use `minSdkVersion 26` instead.

### Add the App Links intent filter

Add this inside your main `<activity>` in `android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https" android:host="aplnk.to" />
</intent-filter>
```

### Launch mode

A link tapped while the app runs must reach the running Activity, which needs `singleTop` or `singleTask`. The `flutter create` template already declares `android:launchMode="singleTop"` on `MainActivity`. Keep it. `standard` and `singleInstance` are not supported.

### No MainActivity code

The plugin attaches to the Activity itself. It reads the launch Intent once and listens for new Intents, so `MainActivity` stays as Flutter generated it.

### Get SHA256 Fingerprint

Get your signing certificate's SHA256 fingerprint:

```bash
# Debug keystore
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android

# Release keystore
keytool -list -v -keystore your-release-key.keystore -alias your-alias
```

Copy the **SHA256** fingerprint and add it to your app registration in the WarpLink dashboard. Add the Play App Signing fingerprint too if you publish through Google Play.

## Step 7: Decide on Flutter's deep-linking flag

Flutter has its own deep link handler. When it is enabled, Flutter also forwards `https://aplnk.to/<slug>` to your router as a route. On Android cold start the route can reach the router without its host, so the router cannot tell a WarpLink URL from any other path. Apps on `go_router` or `Navigator` 2 then show an "unknown route" page next to the WarpLink delivery.

Switch Flutter's handler off and let `onLink` drive navigation.

iOS, in `ios/Runner/Info.plist`:

```xml
<key>FlutterDeepLinkingEnabled</key>
<false/>
```

Android, inside `<activity>` in `AndroidManifest.xml`:

```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
```

If your app must keep Flutter's own deep linking for other, non-WarpLink domains, WarpLink cannot share the same links safely. Keep the WarpLink domains out of Flutter's route table. See [Routing with go_router](go-router.md).

## Step 8: Configure the SDK (opt-out model)

Call `configure` once, from the `initState` of your root widget, and pass an `onLink` callback. This single sink receives **cold-start, warm-start, and deferred** deep links.

Give `MaterialApp` a `navigatorKey`. A cold-start link can arrive before the first frame, when no navigator exists. `navigateTo` below waits for the navigator, so that link is never lost.

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
              // deepLink.isDeferred is true only for a first-launch install match.
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

`navigateTo` in the samples that follow is the function above. With this one call and the configuration from Steps 5 to 7 in place, deep linking and attribution are fully wired. Skip Steps 9 and 10 unless you want manual control. [Delivery and limits](api-reference.md#delivery-and-limits) lists what one tap delivers and where delivery can be lost.

`apiKey` takes the **SDK key** from Step 3. An API key passes the format check and resolves deep links, but it cannot record installs, so attribution stays empty.

Call `configure` from the root isolate. Background isolates are not supported.

### Configuration options

```dart
await WarpLink.configure(
  apiKey: 'wl_live_yoursdkkeyhere000000000000000000',
  onLink: handleLink,
  debugLogging: true,                  // default: false
  automaticDeepLinks: true,            // cold and warm start, default: true
  automaticDeferredDeepLinks: true,    // install check, default: true
  linkDomains: ['links.yourapp.com'],  // your custom domains, default: none
);
```

See the [API Reference](api-reference.md#configure) for every parameter.

### Using a custom link domain

Skip this if all your links are on `aplnk.to`.

The SDK recognizes `aplnk.to` from the start and fetches your verified custom domains in the background. That fetch is a network round trip, and a link that opens your app has to be identified as yours right then. On a first launch, or any launch that starts offline, the fetched list is not there yet and a link on your custom domain is passed back unresolved.

Declare the domain locally to close that gap. Any of these three work, and all of them are merged with each other and with the fetched list:

```dart
// Dart, at configure time.
await WarpLink.configure(
  apiKey: 'wl_live_yoursdkkeyhere000000000000000000',
  linkDomains: ['links.yourapp.com'],
  onLink: handleLink,
);
```

```xml
<!-- iOS: ios/Runner/Info.plist -->
<key>WarpLinkDomains</key>
<array>
  <string>links.yourapp.com</string>
</array>
```

```xml
<!-- Android: android/app/src/main/AndroidManifest.xml, inside <application> -->
<meta-data
    android:name="app.warplink.DOMAINS"
    android:value="links.yourapp.com,go.yourapp.com" />
```

Values are trimmed, lowercased, and reduced to their host natively, so `https://Links.YourApp.com/` and `links.yourapp.com` are the same domain. `www.yourapp.com` is a different host and is never rewritten.

This tells the SDK which links are yours. It does not make iOS or Android open your app. The custom domain must also be verified and live in the dashboard, listed in your Associated Domains entitlement (`applinks:links.yourapp.com`) in Step 5, and added as a host in your intent filter in Step 6.

> **Note:** `configure` returns a `Future<void>` and does not throw for a malformed SDK key. The key format is checked before any native call. A bad key is printed as a warning and reported to `onLink` as an `ErrorEvent` with code `E_INVALID_API_KEY_FORMAT`, and the SDK stays unconfigured.
>
> When `onLink` is provided, a native configuration failure arrives at `onLink` as an `ErrorEvent`, and the future completes normally. When `onLink` is omitted, the future completes with a `WarpLinkException`, so `await configure(...)` inside a `try` block is recommended in the manual model.
>
> The future completes when native configuration completes. It does not wait for the first cold-start or deferred delivery.

## Step 9: Handle Deep Links Manually (opt-out)

**You only need this step if you set `automaticDeepLinks: false`** (or omitted `onLink`). Otherwise cold-start and warm-start links already flow into your `onLink` callback from Step 8.

Deep links arrive in two situations:

- **Cold start**: the app was not running and a link launches it. Read it with `getInitialDeepLink()`.
- **Warm start**: the app is running or in the background and a link brings it to the foreground. Listen to `onDeepLink`.

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

    // Warm-start links (app already running).
    _subscription = WarpLink.onDeepLink.listen((event) {
      switch (event) {
        case LinkEvent(:final deepLink):
          navigateTo(deepLink.destination);
        case ErrorEvent(:final error):
          debugPrint('Deep link error: ${error.message}');
      }
    });

    // Cold-start link (app launched by a link). Returns null the second time.
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

  // build as in Step 8
}
```

`onDeepLink` emits every URL the app is opened with, including URLs that are not WarpLink links. A foreign URL arrives as an `ErrorEvent` with `E_INVALID_URL`. Ignore it, or use it to hand the URL to another handler. A link that arrives before the first listener attaches is held and delivered when it does.

`getInitialDeepLink()` is read-once. If it throws, call it again: the launch link is still waiting. With `automaticDeepLinks` on and an `onLink` callback, the launch link goes to `onLink` and `getInitialDeepLink()` returns `null`, so no link is handled twice.

See [Routing with go_router](go-router.md) for navigation examples.

## Step 10: Deferred Deep Links (automatic)

Deferred deep links work when a user taps a WarpLink URL, installs your app, and opens it for the first time. The SDK matches the install back to the original tap and delivers it through `onLink` with `isDeferred: true`, automatically, as part of Step 8. On a launch by link, the check starts after that link is delivered or dropped.

If you set `automaticDeferredDeepLinks: false`, or you omitted `onLink` and so have nowhere for the match to arrive, call `checkDeferredDeepLink()` yourself once at startup. Omitting `onLink` does not stop the check: the install is attributed either way, and the manual call reads the result.

```dart
final link = await WarpLink.checkDeferredDeepLink();
if (link != null && link.isDeferred) {
  navigateTo(link.deepLinkUrl ?? link.destination);
}
```

The SDK performs the attribution request once and caches whatever came back. Later calls return that cached result with no network request: the same match if one was found, `null` if there was none.

See [Deferred Deep Links](deferred-deep-links.md) for confidence scores and edge cases.

## Step 11: Create a Test Link

### Via Dashboard

1. Go to **Links** in the WarpLink dashboard
2. Click **Create Link**
3. Set the destination URL (for example, `https://yourapp.com/product/123`)
4. Optionally set an iOS deep link URL and/or Android deep link URL
5. Copy the generated short link (for example, `https://aplnk.to/abc123`)

### Via API

```bash
curl -X POST https://api.warplink.app/v1/links \
  -H "Authorization: Bearer wl_live_YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "destination_url": "https://yourapp.com/product/123",
    "ios_url": "myapp://product/123",
    "android_url": "myapp://product/123"
  }'
```

## Step 12: Test on Physical Devices

### iOS

> **Universal Links do not work on the iOS Simulator.** Test on a physical device.

1. Build and run your app on a physical iOS device (`flutter run --release` or a debug build)
2. Open the test link in Safari (or send it through Messages or Notes)
3. Tap the link. Your app opens and the deep link callback fires
4. Check the Xcode console for `[WarpLink]` messages if you enabled `debugLogging`

### Android

1. Build and run your app on a device or emulator
2. Open the test link in Chrome
3. Tap the link. Your app opens directly if App Links verification succeeded
4. Run `adb logcat -s WarpLink` if you enabled `debugLogging`

You can fire a link at a running emulator without a browser:

```bash
adb shell am start -a android.intent.action.VIEW \
  -c android.intent.category.BROWSABLE -d "https://aplnk.to/abc123"
```

### Testing Deferred Deep Links

1. Uninstall the app. That is enough on both platforms: the deferred check is scoped to one install, so a reinstall runs it again. Erasing the simulator also works if you want a device with no history at all. On Android, a Play referrer from an install that began more than seven days earlier is attributed but not delivered as a deferred link.
2. Open the test link in the browser. You are redirected to the App Store or Play Store (or a fallback URL during development)
3. Install the app (through Xcode, Android Studio, `flutter run`, or TestFlight and internal testing)
4. Launch the app. The match arrives at `onLink`, or `checkDeferredDeepLink()` returns it

## Step 13: Debugging Tips

- Enable debug logging: `WarpLink.configure(apiKey: '...', debugLogging: true)`
- **iOS:** check the Xcode console for `[WarpLink]` prefixed messages
- **Android:** run `adb logcat -s WarpLink`
- Check the native version in use: `await WarpLink.sdkVersion()`
- Verify AASA is served correctly: `curl https://aplnk.to/.well-known/apple-app-site-association`
- Verify assetlinks.json: `curl https://aplnk.to/.well-known/assetlinks.json`
- See [Troubleshooting](troubleshooting.md) for common issues

## Next Steps

- [API Reference](api-reference.md): full documentation of all public types and methods
- [Routing with go_router](go-router.md): navigate from `onLink` and switch Flutter's deep-linking flag off
- [Error Handling](error-handling.md): how to handle every error case
- [Attribution](attribution.md): confidence scores and match types
- [Deferred Deep Links](deferred-deep-links.md): in-depth deferred deep link guide
