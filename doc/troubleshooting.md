# Troubleshooting

Common issues and solutions when integrating the WarpLink Flutter SDK.

## 1. Universal Links Not Working (iOS)

**Symptoms:** Tapping a WarpLink URL opens Safari instead of your app, or the app opens but `onLink` never fires.

### Check the Associated Domains entitlement

Verify `applinks:yourapp.aplnk.to` (your app's own link host, and `applinks:aplnk.to` too if your links live on the apex) is listed in your Runner target under **Signing & Capabilities** > **Associated Domains**, and in the built `Runner.entitlements`. Without it iOS never offers the link to your app.

### Your own delegate does not call super

The plugin receives links through Flutter's application and scene delegate chain, so you add no code. If your own `AppDelegate` or `SceneDelegate` overrides `application(_:continue:restorationHandler:)`, `application(_:open:options:)`, `scene(_:continue:)`, or `scene(_:openURLContexts:)`, it must call `super`. An override that returns without calling `super` stops the chain, and the plugin never sees the URL.

```swift
override func application(
  _ application: UIApplication,
  continue userActivity: NSUserActivity,
  restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
) -> Bool {
  // ...your own handling...
  return super.application(
    application, continue: userActivity, restorationHandler: restorationHandler)
}
```

If you combine results from several handlers, store each result in a local first. A `||` chain short-circuits, so a handler placed after one that returns `true` never runs.

### AASA not configured

Your iOS app must be registered in the WarpLink dashboard (**Apps**) with the correct bundle ID and team ID. Verify the AASA file:

```bash
curl -s https://yourapp.aplnk.to/.well-known/apple-app-site-association | python3 -m json.tool
```

Look for your bundle ID and team ID in the `applinks.details` array.

### Testing on the iOS Simulator

**Universal Links do not work on the iOS Simulator.** Test on a physical device.

### Apple Developer portal

Verify that the **Associated Domains** capability is enabled for your App ID in the [Apple Developer portal](https://developer.apple.com). Regenerate your provisioning profile if needed.

### Domain mismatch

The plugin recognizes `aplnk.to` and your app's `{handle}.aplnk.to` host on iOS. Android learns the app host during validation, or from a local domain declaration. The SDK also recognizes your organization's verified custom domains, which it fetches at `configure` and caches for offline launches. A URL on any other host returns `E_INVALID_URL`. If you test a custom domain, confirm it is verified and live in the dashboard and listed in your Associated Domains entitlement (`applinks:go.yourbrand.com`), or iOS will not open your app for it.

If it only fails on the first launch after install, or with no network, the fetch had not completed when the link arrived. Declare the domain locally: `linkDomains: ['go.yourbrand.com']`, a `WarpLinkDomains` array in `Info.plist`, or an `app.warplink.DOMAINS` manifest entry on Android. See [Custom link domains](api-reference.md#custom-link-domains).

---

## 2. Swift Package Manager Errors (iOS)

**Symptoms:** The iOS build fails with a missing package or "no such module" error, or Flutter reports the plugin has no CocoaPods support.

The plugin integrates through Swift Package Manager only. There is no podspec.

- Flutter 3.38 to 3.43: run `flutter config --enable-swift-package-manager` once, then `flutter clean` and rebuild.
- Flutter 3.44 and later: Swift Package Manager is on by default. If you turned it off, turn it back on.
- Run `flutter pub get` after a change, so Flutter regenerates its package manifest for the Runner project.
- Build with `flutter build ios` or `flutter run` at least once so Xcode resolves the packages. Opening `Runner.xcworkspace` before the first Flutter build can show unresolved packages.
- The first resolve needs network access to fetch the WarpLink iOS SDK. Check that your proxy or firewall allows GitHub.

---

## 3. App Links Not Verified (Android)

**Symptoms:** Tapping a WarpLink URL shows a disambiguation dialog instead of opening your app directly.

### Manifest merge fails on minSdk

If the build fails with a message that `minSdkVersion` cannot be smaller than the version 26 declared in the library, set `minSdk = 26` in `android/app/build.gradle.kts`. Flutter's default can be lower.

### Warm-start links lost (launch mode)

If cold-start links work but tapping a link while the app is running does nothing, check `android:launchMode` on `MainActivity`. It must be `singleTop` (the `flutter create` default) or `singleTask`. With `standard`, Android starts another Activity instead of delivering the Intent to the running one, so the SDK never sees the warm-start URL. `singleInstance` is not supported.

### Check assetlinks.json

```bash
curl -s https://yourapp.aplnk.to/.well-known/assetlinks.json | python3 -m json.tool
```

Look for your package name and SHA256 fingerprint.

### SHA256 fingerprint mismatch

Get your actual signing certificate fingerprint:

```bash
# Debug keystore
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android

# Release keystore
keytool -list -v -keystore your-release-key.keystore -alias your-alias
```

Compare the **SHA256** fingerprint with what is registered in the WarpLink dashboard. They must match exactly. If you publish through Google Play App Signing, register Google's app signing fingerprint as well.

### Missing autoVerify

Make sure `android:autoVerify="true"` is set on the intent filter in `AndroidManifest.xml`, and that the intent filter sits inside the main `<activity>`, not inside `<application>` directly.

### Clear the App Links verification cache

After updating assetlinks.json or the fingerprint, reset verification on the test device:

```bash
adb shell pm set-app-links --package com.yourcompany.yourapp 0 all
adb shell pm verify-app-links --re-verify com.yourcompany.yourapp
```

---

## 4. Router Shows an Unknown Route

**Symptoms:** Tapping a WarpLink URL opens your app, `onLink` fires, and your router also shows an "unknown route" or "page not found" screen for the slug.

Flutter's own deep link handler is enabled by default and forwards `https://yourapp.aplnk.to/<slug>` to your router as a route. Switch it off: set `FlutterDeepLinkingEnabled` to `false` in `Info.plist`, and `flutter_deeplinking_enabled` to `false` in the manifest. Then navigate from `onLink`. See [Routing with go_router](go-router.md).

---

## 5. Deep Link Not Resolving

**Symptoms:** `handleDeepLink()` or `getInitialDeepLink()` returns `null` or throws.

### SDK not configured

Make sure `WarpLink.configure()` ran and completed before any other call. Check for `E_NOT_CONFIGURED`, or call `await WarpLink.isConfigured()`.

### The launch link was already taken

`getInitialDeepLink()` returns the launch URL once. With `automaticDeepLinks` on and an `onLink` callback, the launch link goes to `onLink` and `getInitialDeepLink()` returns `null`. Use one path or the other.

### Network issues

The SDK makes a network request to resolve the link. Check device connectivity and enable debug logging:

```dart
await WarpLink.configure(
  apiKey: 'wl_live_yoursdkkeyhere000000000000000000',
  debugLogging: true,
);
```

### Invalid URL format

`handleDeepLink()` expects a full URL such as `https://aplnk.to/abc123`, with a host the SDK recognizes and exactly one path segment. Anything else throws `WarpLinkInvalidUrlException`.

### Link not found

The link may have been deleted or deactivated. Verify it in the WarpLink dashboard.

### A second tap did nothing

A second tap on the same URL within 1.5 seconds counts as the same tap, so `onLink` receives it once. A tap on a different link while the first still resolves supersedes the first: only the newer link reaches `onLink`. An `onDeepLink` subscriber still receives both.

---

## 6. Deferred Deep Link Returns `null`

**Symptoms:** `checkDeferredDeepLink()` returns `null` when you expect a match, or deep links resolve fine but no installs appear in your dashboard.

### Wrong key type (most common)

Install attribution requires an **SDK key**. An API key cannot record installs, whatever scopes it holds, so the attribution request is rejected and no match comes back. Deep links keep resolving normally, which makes this one hard to spot.

Create an SDK key under **Keys** > **SDK keys** in the dashboard and pass it to `WarpLink.configure()`. Both credentials use the `wl_live_` prefix followed by 32 alphanumeric characters, so check the key type in the dashboard rather than reading the string.

### Match window expired

The default match window is 6 hours, and the ceiling is 24 hours. If the user installs the app after the window expires, no match is found. The window is set per link in the dashboard.

### Fingerprint mismatch

The user's network conditions may have changed between tapping the link and installing the app (VPN, different Wi-Fi network, carrier-grade NAT). This reduces fingerprint accuracy.

### Not first launch

The check runs once per install. After a definitive server answer it returns the cached result from that completed check, which is `null` when that check found no match. The gate is scoped to one install on both platforms, so deleting the app and installing it again always retests.

To test deferred deep links:
1. Uninstall the app (iOS and Android both work; erasing the simulator also works)
2. Tap a WarpLink URL in the browser
3. Install the app (through Xcode, Android Studio, or `flutter run`)
4. Launch the app. The match arrives at `onLink`, or `checkDeferredDeepLink()` returns it

If the check still does not run after a reinstall, the device most likely restored from a backup that carried the gate. That is a bug: file it. The gate is stored where neither an uninstall nor a restore can bring it back.

### Offline first launch

The check fails with `E_NETWORK_ERROR` and the gate stays open. The next launch retries without any code from you.

### Marker storage

Each native SDK keeps two separate markers, and neither is readable from Dart.

The **gate** answers "has attribution already completed for this install?". On Android it lives in `noBackupFilesDir`. On iOS it is a file marked as excluded from backup. Neither survives an uninstall, and neither is restored from a backup, so a reinstall always runs a fresh check.

The **device-seen marker** answers "has this device ever completed attribution?". On iOS it is a Keychain entry. On Android it is a backed-up shared preference. It survives an uninstall and a restore by design and gates nothing. It only tags the attribution request, so a reinstall can be counted separately.

---

## 7. Another Plugin Handles Links First (iOS)

**Symptoms:** On iOS, a link that launches the app from a closed state never reaches `onLink` or `getInitialDeepLink()`. Links tapped while the app runs work.

Another plugin in the app, such as a second link or authentication plugin, can handle the launch link before WarpLink sees it. WarpLink cannot see a URL that another plugin has already taken. This is a Flutter platform limit.

If that plugin exposes the launch URL, pass it to WarpLink yourself:

```dart
final launchUrl = await otherPlugin.initialLink();
if (launchUrl != null && await WarpLink.isWarpLinkUrl(launchUrl)) {
  final link = await WarpLink.handleDeepLink(launchUrl);
  if (link != null) navigateTo(link.deepLinkUrl ?? link.destination);
}
```

---

## 8. Unsupported Targets

**Symptoms:** `UnsupportedError: WarpLink supports iOS and Android only`.

The plugin runs on iOS and Android only. Guard calls on web and desktop targets:

```dart
import 'package:flutter/foundation.dart';

final supported = !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);
if (supported) {
  await WarpLink.configure(apiKey: 'wl_live_yoursdkkeyhere000000000000000000');
}
```

Call every method from the root isolate. Background isolates are not supported.

---

## 9. Debug Logging Setup

**Symptoms:** You need to trace SDK behavior but see no log output.

### Enable debug logging

```dart
await WarpLink.configure(
  apiKey: 'wl_live_yoursdkkeyhere000000000000000000',
  debugLogging: true,
);
```

### iOS: Xcode console

With `debugLogging: true`, the native SDK prints lines with a `[WarpLink]` prefix:

- `[WarpLink] Configured with API key: wl_live_****xxxx`: the SDK initialized
- `[WarpLink] API key validated successfully`: the server accepted the key
- `[WarpLink] Resolving Universal Link: <url>`: a link is being resolved
- `[WarpLink] First launch: collecting device signals for attribution`: the install check started
- `[WarpLink] Deferred deep link matched: <linkId>`: the install matched a tap
- `[WarpLink] No deferred deep link match`: the install had no match

### Android: logcat

```bash
adb logcat -s WarpLink
```

With `debugLogging: true`, the native SDK logs under the `WarpLink` tag:

- `Configured with API key: <masked key>` and `WarpLink SDK configured (v1.1.1)`: the SDK initialized
- `API key validated successfully`: the server accepted the key
- `Resolving deep link: <slug>@<domain>` and `Deep link resolved: <linkId>`: a link was resolved
- `First launch: collecting device signals`: the install check started
- `Deferred deep link matched: <linkId>`: the install matched a tap
- `No deferred deep link match`: the install had no match

### Warnings

These print even with `debugLogging` off:

- `[WarpLink] Invalid API key format. Expected: wl_live_xxx or wl_test_xxx (32 alphanumeric characters after prefix)`: the key failed the format check. The same error reaches `onLink`.
- iOS: `[WarpLink] WARNING: API key rejected by server (invalid or revoked). Deep linking and attribution will not work until a valid key is supplied.`
- Android: `WarpLink API key was rejected by the server; deep links and attribution will not work. Replace it with an active SDK key from your dashboard.`

The Dart layer does not intercept native logs. The SDK only ever logs the masked form of your key.

---

## 10. Version Questions

`await WarpLink.sdkVersion()` returns the version the native SDK reports, which is also what appears on the wire. `warplinkFlutterVersion` is the version of the Dart package. They match at every release (1.1.1 for both).

## Related Guides

- [Integration Guide](integration-guide.md): step-by-step setup
- [Routing with go_router](go-router.md): routing with Flutter's deep-linking flag off
- [Error Handling](error-handling.md): handling SDK errors in code
- [Deferred Deep Links](deferred-deep-links.md): how deferred attribution works
