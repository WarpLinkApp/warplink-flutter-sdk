# Firebase Dynamic Links Migration Guide

Firebase Dynamic Links was deprecated on August 25, 2025. This guide walks you through migrating your Flutter app from the `firebase_dynamic_links` package to `warplink_flutter`.

## Concept Mapping

| Firebase Dynamic Links | WarpLink |
|----------------------|----------|
| Dynamic Links | Links |
| Firebase console | [WarpLink dashboard](https://warplink.app) |
| `firebase_dynamic_links` | `warplink_flutter` |
| `yourapp.page.link` domain | `aplnk.to` domain |
| `FirebaseDynamicLinks.instance` | `WarpLink` (static class) |
| Link parameters (social metadata, analytics) | Link fields (destination, deep link URL, custom params) |
| Firebase Analytics integration | WarpLink attribution |

## Step 1: Recreate Your Links

Recreate your Firebase Dynamic Links as WarpLink links through the [dashboard](https://warplink.app) or the [REST API](https://api.warplink.app/v1).

### Parameter Mapping

| Firebase Parameter | WarpLink Field |
|-------------------|----------------|
| `link` (deep link URL) | `destination_url` |
| `isi` (iOS App Store ID) | Configured per app in the dashboard |
| `ibi` (iOS bundle ID) | Configured per app in the dashboard |
| `ifl` (iOS fallback link) | `ios_fallback_url` |
| `apn` (Android package name) | Configured per app in the dashboard |
| `afl` (Android fallback link) | `android_fallback_url` |
| `efr` (skip preview page) | N/A (WarpLink uses 302 redirects by default) |
| `st` / `sd` / `si` (social metadata) | OG tags on the destination page |
| Custom parameters | `custom_params` JSON object |

### Via Dashboard

1. Go to **Links** > **Create Link**
2. Set the destination URL
3. Add iOS and/or Android deep link URLs if needed
4. Add any custom parameters

### Via API

```bash
curl -X POST https://api.warplink.app/v1/links \
  -H "Authorization: Bearer wl_live_YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "destination_url": "https://yourapp.com/product/123",
    "ios_url": "myapp://product/123",
    "android_url": "myapp://product/123",
    "custom_params": { "referrer": "campaign_spring" }
  }'
```

## Step 2: Swap the Package

### Remove Firebase Dynamic Links

```bash
flutter pub remove firebase_dynamic_links
```

If you do not use any other Firebase packages, also remove `firebase_core` and the Firebase initialization code that only served Dynamic Links.

Remove the Dynamic Links entries from your native projects: the `*.page.link` associated domain in your iOS entitlements, and the `*.page.link` intent filter in `AndroidManifest.xml`, once your old links are redirected (see Step 6).

### Add WarpLink

```bash
flutter pub add warplink_flutter
```

There is no Podfile change. The iOS side uses Swift Package Manager: Flutter 3.44 and later enable it by default, and on Flutter 3.38 to 3.43 you run `flutter config --enable-swift-package-manager` once. Set Android `minSdk` to 26. See the [Integration Guide](integration-guide.md) for the platform setup.

### Update imports

Remove the Firebase import:

```dart
// Remove this
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
```

Add the WarpLink import:

```dart
import 'package:warplink_flutter/warplink_flutter.dart';
```

## Step 3: Update SDK Initialization

**Firebase:**

```dart
// Dynamic Links needed Firebase.initializeApp() at startup.
await Firebase.initializeApp();
```

**WarpLink:**

```dart
class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    unawaited(
      WarpLink.configure(
        apiKey: 'wl_live_yoursdkkeyhere000000000000000000',
        onLink: handleLink,
      ),
    );
  }

  // build: MaterialApp(navigatorKey: navigatorKey, ...)
}
```

Call `configure` from the `initState` of your root widget, and give `MaterialApp` a `navigatorKey`, so a cold-start link waits for the navigator instead of being lost. The [Integration Guide](integration-guide.md#step-8-configure-the-sdk-opt-out-model) has the full sample.

`apiKey` takes an **SDK key**, created under **Keys** > **SDK keys** in the dashboard. It is pre-scoped for link resolution and install attribution. API keys are a separate credential for backend scripts and CI, and they cannot record installs.

## Step 4: Migrate Deep Link Handling

With WarpLink's default options, one `onLink` callback replaces both the cold-start and the warm-start code.

### Get Initial Link (Cold Start)

**Firebase:**

```dart
final PendingDynamicLinkData? initial =
    await FirebaseDynamicLinks.instance.getInitialLink();
if (initial != null) {
  handleDeepLink(initial.link);
}
```

**WarpLink:**

```dart
// Automatic: the launch link reaches onLink from configure().
// Manual mode (automaticDeepLinks: false):
final link = await WarpLink.getInitialDeepLink();
if (link != null) {
  navigateTo(link.destination);
}
```

### Listen for Links (Warm Start)

**Firebase:**

```dart
FirebaseDynamicLinks.instance.onLink.listen((PendingDynamicLinkData data) {
  handleDeepLink(data.link);
});
```

**WarpLink:**

```dart
// Automatic: warm-start links reach onLink.
// Manual mode (automaticDeepLinks: false):
final subscription = WarpLink.onDeepLink.listen((event) {
  switch (event) {
    case LinkEvent(:final deepLink):
      navigateTo(deepLink.destination);
    case ErrorEvent(:final error):
      debugPrint('Deep link error: ${error.message}');
  }
});
```

### Key Differences

| | Firebase | WarpLink |
|-|---------|----------|
| Cold start | `getInitialLink()` | `onLink` (automatic) or `WarpLink.getInitialDeepLink()` |
| Warm start | `onLink` stream | `onLink` (automatic) or `WarpLink.onDeepLink` stream |
| Return type | `PendingDynamicLinkData` | `WarpLinkDeepLink` |
| Deep link URL | `data.link` | `deepLink.destination` or `deepLink.deepLinkUrl` |
| Error handling | Stream errors | Sealed `WarpLinkException` with `wireCode` |
| Custom parameters | Embedded in the URL as query params | `deepLink.customParams` map |
| Unsubscribe | Cancel the subscription | Cancel the subscription (same pattern) |

### Accessing Link Parameters

**Firebase:**

```dart
// Firebase: parameters embedded in the URL
final initial = await FirebaseDynamicLinks.instance.getInitialLink();
if (initial != null) {
  final productId = initial.link.queryParameters['product_id'];
  final referrer = initial.link.queryParameters['referrer'];
}
```

**WarpLink:**

```dart
// WarpLink: parameters in a typed map
final link = await WarpLink.getInitialDeepLink();
if (link != null) {
  final productId = link.customParams['product_id'] as String?;
  final referrer = link.customParams['referrer'] as String?;
  // Also available:
  debugPrint('Destination: ${link.destination}');
  debugPrint('Link ID: ${link.linkId}');
}
```

## Step 5: Migrate Deferred Deep Links

**Firebase:**

```dart
// Firebase handled deferred deep links through getInitialLink() on first launch.
final initial = await FirebaseDynamicLinks.instance.getInitialLink();
if (initial != null) {
  // Could be a deferred deep link. No way to distinguish.
  handleDeepLink(initial.link);
}
```

**WarpLink:**

```dart
// WarpLink: an explicit deferred deep link API with attribution data.
// Automatic by default: the match reaches onLink with isDeferred == true.
// Manual:
final link = await WarpLink.checkDeferredDeepLink();
if (link != null && link.isDeferred) {
  debugPrint('Match confidence: ${link.matchConfidence}');
  navigateTo(link.deepLinkUrl ?? link.destination);
}
```

### Key Differences

| | Firebase | WarpLink |
|-|---------|----------|
| API | `getInitialLink()` (same as cold start) | Automatic through `onLink`, or `checkDeferredDeepLink()` |
| Deferred detection | No `isDeferred` flag | `link.isDeferred == true` |
| Attribution data | None | `matchType`, `matchConfidence`, `matchGuaranteed` |
| Caching | Manual | Automatic (cached after the first check) |

## Step 6: Link Migration Strategy

### Redirect Existing Firebase Links

If you have Firebase Dynamic Links in the wild (shared on social media, in emails, and so on), you can redirect them to WarpLink:

1. Set up a redirect from your Firebase `*.page.link` domain to the equivalent WarpLink short link
2. Or update the destination in the Firebase console to point to the WarpLink short URL

### Bulk Create via API

For large numbers of links, use the WarpLink REST API:

```bash
for url in "${urls[@]}"; do
  curl -X POST https://api.warplink.app/v1/links \
    -H "Authorization: Bearer wl_live_YOUR_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"destination_url\": \"$url\"}"
done
```

### Transition Period

During migration you can keep both packages temporarily:
1. Keep `firebase_dynamic_links` for existing links
2. Add `warplink_flutter` for the links you create from now on
3. Once all links are migrated, remove Firebase

## Step 7: Feature Comparison

| Feature | Firebase Dynamic Links | WarpLink |
|---------|----------------------|----------|
| Short links | Yes | Yes |
| Deferred deep links | Yes (limited data) | Yes (with confidence scores) |
| Install attribution | No | Yes (deterministic + probabilistic) |
| Custom domains | Yes | Yes |
| Analytics | Through Firebase Analytics | Built-in click analytics |
| Social previews (OG tags) | Built-in | Built-in (through bot detection) |
| Cross-platform | iOS + Android + web | iOS + Android + Flutter + web |
| Pricing | Free (deprecated) | Free tier (10K clicks/mo) |
| Open source SDK | No | Yes (MIT) |

## Step 8: Testing Checklist

After migration, verify each flow:

- [ ] **SDK initializes**: enable `debugLogging: true` and check the console
- [ ] **Cold start deep link**: the launch link reaches `onLink` (or `getInitialDeepLink()` returns it)
- [ ] **Warm start deep link**: `onLink` (or `onDeepLink`) fires when a link is tapped while the app is running
- [ ] **Custom parameters preserved**: `deepLink.customParams` matches what you configured
- [ ] **Deferred deep links work**: uninstall the app on either platform, tap the link, install, launch, and verify the match arrives. A reinstall retests on iOS and on Android
- [ ] **iOS Universal Links work**: tap a WarpLink URL on a physical iOS device
- [ ] **Android App Links work**: tap a WarpLink URL on an Android device
- [ ] **Error handling works**: test with an invalid URL, an expired link, and no connectivity
- [ ] **Old Firebase code fully removed**: no remaining `firebase_dynamic_links` imports
- [ ] **Build succeeds**: a clean build with no Firebase Dynamic Links dependencies

## Related Guides

- [Integration Guide](integration-guide.md): full setup walkthrough
- [API Reference](api-reference.md): all public types and methods
- [Troubleshooting](troubleshooting.md): common issues after migration
