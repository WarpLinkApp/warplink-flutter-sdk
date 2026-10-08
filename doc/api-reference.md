# API Reference

Complete reference for the public API of `warplink_flutter`. Import everything from one library:

```dart
import 'package:warplink_flutter/warplink_flutter.dart';
```

All methods run in the root isolate and work on iOS and Android only. On any other target they throw `UnsupportedError('WarpLink supports iOS and Android only')`.

## WarpLink

`WarpLink` is an `abstract final class` with static members. You never instantiate it.

### Methods

#### `configure`

Initializes the SDK. Call it once, from the `initState` of your root widget.

```dart
static Future<void> configure({
  required String apiKey,
  String apiEndpoint = defaultApiEndpoint,
  bool debugLogging = false,
  List<String> linkDomains = const <String>[],
  bool automaticDeepLinks = true,
  bool automaticDeferredDeepLinks = true,
  WarpLinkListener? onLink,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `apiKey` | `String` | required | An SDK key (`wl_live_` or `wl_test_` plus 32 alphanumeric characters), created under **Keys** > **SDK keys** |
| `apiEndpoint` | `String` | `https://api.warplink.app/v1` | API base URL |
| `debugLogging` | `bool` | `false` | Trace SDK behavior in the Xcode console and logcat |
| `linkDomains` | `List<String>` | `[]` | Extra hosts that serve your links, on top of `aplnk.to` |
| `automaticDeepLinks` | `bool` | `true` | Deliver cold-start and warm-start links to `onLink`. Only takes effect when `onLink` is set |
| `automaticDeferredDeepLinks` | `bool` | `true` | Run the install attribution check from `configure`. Runs with or without `onLink` |
| `onLink` | `WarpLinkListener?` | `null` | The single sink for cold-start, warm-start, and deferred links |

**Behavior**

- A malformed key never throws. The SDK prints a warning (visible in release builds), delivers an `ErrorEvent` with `E_INVALID_API_KEY_FORMAT` to `onLink`, leaves the SDK unconfigured, and returns a completed future.
- With `onLink`, a native configuration failure arrives as an `ErrorEvent` and the future completes normally. Without `onLink`, the future completes with a `WarpLinkException`.
- An exception thrown by your `onLink` while `configure` delivers a rejected key or a configuration error propagates out of the future. For a link that arrives later, an exception from `onLink` surfaces as an uncaught error and does not stop the SDK. That link is not delivered again.
- The future completes when native configuration completes. It does not wait for the first cold-start or deferred delivery.
- Calling `configure` again replaces the earlier configuration and callback. Only the newest `onLink` receives links. A link that was still resolving goes to the newest callback and is not delivered twice.
- The deferred check starts after the launch link is delivered or dropped. A match reaches `onLink` once. A check that fails (for example offline) reaches `onLink` as an `ErrorEvent` and leaves the once-per-install gate open, so the next launch retries.

#### `handleDeepLink`

Resolves a WarpLink URL to its destination.

```dart
static Future<WarpLinkDeepLink?> handleDeepLink(String url)
```

Throws a `WarpLinkException`, for example `WarpLinkInvalidUrlException` for a URL that is not a WarpLink link, `WarpLinkLinkNotFoundException`, or `WarpLinkNetworkException`. A manual call always makes its own request, and its answer goes to the caller alone. A call for a WarpLink URL supersedes an automatic tap that is still resolving.

```dart
try {
  final link = await WarpLink.handleDeepLink('https://aplnk.to/abc123');
  if (link != null) navigateTo(link.destination);
} on WarpLinkException catch (error) {
  debugPrint('${error.wireCode}: ${error.message}');
}
```

#### `checkDeferredDeepLink`

Runs the deferred deep link check.

```dart
static Future<WarpLinkDeepLink?> checkDeferredDeepLink()
```

Returns the stored result on every call once attribution completed, and `null` for a confirmed no-match. A manual call that races the automatic check receives the same result, from one request.

```dart
final link = await WarpLink.checkDeferredDeepLink();
if (link != null && link.isDeferred) {
  navigateTo(link.deepLinkUrl ?? link.destination);
}
```

#### `getAttributionResult`

Reads the stored install attribution result.

```dart
static Future<AttributionResult?> getAttributionResult()
```

Returns `null` when the install had no match. Throws `WarpLinkNotConfiguredException` before `configure`. A non-null but malformed native payload throws `WarpLinkDecodingException`, so "no attribution" and "the data could not be read" stay distinct.

#### `isAttributionComplete`

```dart
static Future<bool> isAttributionComplete()
```

`true` once the install check has finished with a definitive server answer, a match or a confirmed no-match. A failed check leaves it `false`.

#### `isConfigured`

```dart
static Future<bool> isConfigured()
```

`true` after a successful `configure`. `false` after a rejected key format.

#### `isWarpLinkUrl`

```dart
static Future<bool> isWarpLinkUrl(String url)
```

`true` when the host belongs to a known WarpLink domain and the path is exactly one segment. Never throws for a bad URL: an unparsable string returns `false`.

#### `sdkVersion`

```dart
static Future<String> sdkVersion()
```

The version the native SDK reports, for example `1.1.0`. This is the version sent on the wire, not the package version. The package constant is `warplinkFlutterVersion`.

#### `onDeepLink`

```dart
static Stream<WarpLinkEvent> get onDeepLink
```

Every URL the app receives while it runs, resolved, for manual wiring. Emits a `LinkEvent` for a WarpLink link and an `ErrorEvent` for a failure, including `WarpLinkInvalidUrlException` for a foreign URL. Events are not deduplicated and are independent of `onLink`. The launch URL is not part of this stream: read it with `getInitialDeepLink`. A URL received before the first listener attaches is delivered when it does. The stream is a broadcast stream. Cancel your subscription to stop listening.

```dart
final subscription = WarpLink.onDeepLink.listen((event) {
  if (event case LinkEvent(:final deepLink)) {
    navigateTo(deepLink.destination);
  }
});
```

#### `getInitialDeepLink`

```dart
static Future<WarpLinkDeepLink?> getInitialDeepLink()
```

Takes the URL that launched the app, once, and resolves it. The second call returns `null`. With `automaticDeepLinks` and an `onLink` callback, the launch link goes to `onLink` and this returns `null`. With `automaticDeepLinks: false`, the URL waits until you read it here. If the call throws, call it again: the URL is still waiting. On iOS, a launch link that reaches the app only after it became active arrives on `onDeepLink` instead.

### Constants

| Name | Value | Description |
|------|-------|-------------|
| `defaultApiEndpoint` | `https://api.warplink.app/v1` | Default `apiEndpoint` |
| `warplinkFlutterVersion` | `1.1.0` | Version of the Dart package |

## Types

### `WarpLinkListener`

```dart
typedef WarpLinkListener = void Function(WarpLinkEvent event);
```

### Custom link domains

`linkDomains` lists hosts that serve your links, on top of `aplnk.to`. Values are trimmed, lowercased, and reduced to their host natively. `www.` is kept. The SDK merges these sources: `aplnk.to`, the `linkDomains` list, the iOS `Info.plist` key `WarpLinkDomains` (an array of strings), the Android manifest `<meta-data android:name="app.warplink.DOMAINS">` (comma separated), and the verified-domain list the SDK fetches from the server and caches for offline launches. Declaring a domain in more than one place is safe.

Declaring a domain tells the SDK the link is yours. It does not make the OS open your app. The domain must also be verified in the dashboard, listed in your Associated Domains entitlement, and present in your Android intent filter.

### `WarpLinkEvent`

A sealed class. Either a `LinkEvent` or an `ErrorEvent`. Use a `switch` to handle both.

```dart
sealed class WarpLinkEvent {}

final class LinkEvent extends WarpLinkEvent {
  final WarpLinkDeepLink deepLink;
}

final class ErrorEvent extends WarpLinkEvent {
  final WarpLinkException error;
}
```

### `WarpLinkDeepLink`

A resolved WarpLink link.

| Property | Type | Description |
|----------|------|-------------|
| `linkId` | `String` | Identifier of the link in the dashboard |
| `destination` | `String` | The web destination URL |
| `deepLinkUrl` | `String?` | The in-app URL for this OS, or `null` when the link has none |
| `customParams` | `Map<String, Object?>` | Custom key and value pairs set on the link. Values are JSON values: `String`, `bool`, `int`, `double`, `null`, nested `Map`, nested `List`. Empty map when none. Unmodifiable |
| `isDeferred` | `bool` | `true` when the link came from the install attribution check rather than a tap in the running app |
| `matchType` | `MatchType?` | How the link was matched, or `null` when it was not matched at all |
| `matchConfidence` | `double?` | Confidence from 0 to 1, or `null` when not matched |
| `matchGuaranteed` | `bool` | `true` only for a deterministic match |

A link resolved by a tap has `isDeferred: false`, `matchType: MatchType.deterministic`, `matchConfidence: 1.0`, and `matchGuaranteed: true`. The class has value equality.

```dart
final productId = link.customParams['product_id'] as String?;
```

### `AttributionResult`

The stored result of the install attribution check.

| Property | Type | Description |
|----------|------|-------------|
| `linkId` | `String` | Identifier of the link that attributed the install |
| `matchType` | `MatchType` | How the install was matched |
| `matchConfidence` | `double` | Confidence from 0 to 1 |
| `matchGuaranteed` | `bool` | `true` only for a deterministic match |
| `isDeferred` | `bool` | `true` when the deferred check attributed the install |

### `MatchType`

```dart
enum MatchType { deterministic, probabilistic }
```

`deterministic` matches by a stable identifier (IDFV or Play Install Referrer), has confidence 1.0, and is guaranteed. `probabilistic` matches by a device fingerprint and is a best guess. `wireValue` holds the lowercase string.

> **Use `matchGuaranteed`, like `matchConfidence`, to pick a destination. It is not a credential.** A probabilistic match can name the wrong user. Authenticate the user and check authorization separately before showing private data or doing anything sensitive, guaranteed match or not.

## Error Types

### `WarpLinkException`

The base type of every error the SDK reports. It is a sealed class that implements `Exception`.

| Member | Type | Description |
|--------|------|-------------|
| `message` | `String` | Human-readable description |
| `code` | `WarpLinkErrorCode` | The machine-readable code |
| `wireCode` | `String` | The `E_*` string, for example `E_NETWORK_ERROR`. The same strings the iOS, Android, and React Native SDKs use |

An unknown code from the native layer becomes a `WarpLinkServerException`, matching the other SDKs.

### Subclasses

| Class | `wireCode` |
|-------|-----------|
| `WarpLinkNotConfiguredException` | `E_NOT_CONFIGURED` |
| `WarpLinkInvalidApiKeyFormatException` | `E_INVALID_API_KEY_FORMAT` |
| `WarpLinkInvalidApiKeyException` | `E_INVALID_API_KEY` |
| `WarpLinkNetworkException` | `E_NETWORK_ERROR` |
| `WarpLinkServerException` | `E_SERVER_ERROR` |
| `WarpLinkInvalidUrlException` | `E_INVALID_URL` |
| `WarpLinkLinkNotFoundException` | `E_LINK_NOT_FOUND` |
| `WarpLinkPasswordRequiredException` | `E_PASSWORD_REQUIRED` |
| `WarpLinkDecodingException` | `E_DECODING_ERROR` |

`WarpLinkServerException` also has `statusCode`, the HTTP status when known and `null` when the failure had no response.

Because the hierarchy is sealed, a `switch` over a `WarpLinkException` is checked for exhaustiveness at compile time:

```dart
String describe(WarpLinkException error) => switch (error) {
  WarpLinkNotConfiguredException() => 'Call configure first',
  WarpLinkInvalidApiKeyFormatException() => 'Check the key format',
  WarpLinkInvalidApiKeyException() => 'Key rejected',
  WarpLinkNetworkException() => 'No connection',
  WarpLinkServerException(:final statusCode) => 'Server error $statusCode',
  WarpLinkInvalidUrlException() => 'Not a WarpLink URL',
  WarpLinkLinkNotFoundException() => 'Link not found',
  WarpLinkPasswordRequiredException() => 'Open in a browser',
  WarpLinkDecodingException() => 'Update the app',
};
```

### `WarpLinkErrorCode`

An enum with one value per code: `notConfigured`, `invalidApiKeyFormat`, `invalidApiKey`, `networkError`, `serverError`, `invalidUrl`, `linkNotFound`, `passwordRequired`, `decodingError`. Each has a `wireCode` string. `WarpLinkErrorCode.fromWire` finds a value for a wire string and returns `null` when unknown.

See [Error Handling](error-handling.md) for what causes each code and how to recover.

## Behavior notes

- **Foreign URLs are ignored by the automatic path.** They never reach `onLink`. `onDeepLink` still emits them as `WarpLinkInvalidUrlException` events.
- **Cold start, then the deferred check.** On a launch by link, the deferred check starts after the launch link is delivered or dropped.
- **Match window.** The window is set per link in the dashboard. There is no client-side setting.
- **Threading.** Results arrive on the main isolate. Background isolates are not supported.
- **Wire identity.** Requests carry the native identity (`WarpLink-iOS/<version>` or `WarpLink-Android/<version>`). The plugin adds no signal of its own.

## Delivery and limits

- **One delivery per tap.** `onLink` receives each tap once. A second tap on the same URL within 1.5 seconds counts as the same tap, on iOS and Android, and is not delivered again. A newer tap supersedes an older one that is still resolving: the older result never reaches `onLink`.
- **`onLink` and `onDeepLink`.** `onLink` is the automatic path and receives WarpLink links only. `onDeepLink` receives every URL the app is opened with and ignores the 1.5 second rule. A tap resolves once, and both see the same result. A superseded link still reaches `onDeepLink`.
- **`getInitialDeepLink`.** Returns the launch link when `automaticDeepLinks` is off or no `onLink` is set. It returns `null` the second time, and always `null` while the automatic path delivers the launch link.
- **At most once.** A delivered link is never offered again. A process death or an engine disposal while a tap's final step is in flight can lose that one delivery, and so can an `onLink` that throws before it navigates. If the process dies after the server recorded the click and before the app received the answer, the relaunch is a new launch and the click can be counted a second time.
- **iOS supersede is navigation only.** The older request still completes and can still be counted. On Android, a newer tap cancels the older request.
- **Another plugin can hide a cold-start link on iOS.** See [Another plugin handles links first](troubleshooting.md#7-another-plugin-handles-links-first-ios).

The channel between Dart and the native SDKs is described in [Channel contract](channel-contract.md).

## Related Guides

- [Integration Guide](integration-guide.md)
- [Error Handling](error-handling.md)
- [Attribution](attribution.md)
- [Deferred Deep Links](deferred-deep-links.md)
