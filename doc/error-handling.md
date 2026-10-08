# Error Handling

The WarpLink Flutter SDK reports every failure as a `WarpLinkException`. It is a sealed class with nine subclasses, so a `switch` is checked for exhaustiveness at compile time. Every exception has a `code` (a `WarpLinkErrorCode`), a `wireCode` string such as `E_NETWORK_ERROR`, and a human-readable `message`. The `E_*` strings match the iOS, Android, and React Native SDKs.

## Where errors appear

- **Thrown from async methods:** `handleDeepLink`, `checkDeferredDeepLink`, `getAttributionResult`, `getInitialDeepLink`, and the other `Future` methods throw a `WarpLinkException`.
- **Delivered as events:** `onLink` and the `onDeepLink` stream receive an `ErrorEvent` carrying the exception.
- **Never thrown by `configure` for a bad key:** it prints a warning, reports `E_INVALID_API_KEY_FORMAT` to `onLink`, and returns.

## Error Codes

### `E_NOT_CONFIGURED` (`WarpLinkNotConfiguredException`)

**When:** Any SDK method is called before a successful `WarpLink.configure()`.

**Fix:** Call `configure()` from the `initState` of your root widget, before any other SDK call.

```dart
class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    unawaited(
      WarpLink.configure(apiKey: 'wl_live_yoursdkkeyhere000000000000000000'),
    );
  }

  // build as in the Integration Guide
}
```

---

### `E_INVALID_API_KEY_FORMAT` (`WarpLinkInvalidApiKeyFormatException`)

**When:** The SDK key passed to `configure()` does not match the expected format: `wl_live_` or `wl_test_` followed by exactly 32 alphanumeric characters.

**Regex:** `^wl_(live|test)_[a-zA-Z0-9]{32}$`

**Fix:** Verify your SDK key in the [WarpLink dashboard](https://warplink.app) under **Keys** > **SDK keys**. Make sure you copied the full key.

**Note:** `configure()` does not throw. It prints a warning that is visible in release builds, reports the error through your `onLink` callback, and leaves the SDK unconfigured. iOS and Android behave the same way.

```dart
await WarpLink.configure(
  apiKey: 'invalid_key',
  onLink: (event) {
    if (event case ErrorEvent(:final error)
        when error is WarpLinkInvalidApiKeyFormatException) {
      debugPrint('Invalid API key format: ${error.message}');
      return;
    }
    // ...handle the link
  },
);
```

---

### `E_INVALID_API_KEY` (`WarpLinkInvalidApiKeyException`)

**When:** The server rejects the key (HTTP 401 or 403). The key may be revoked, incorrect, or of the wrong type.

**Fix:**
1. Check that you passed an **SDK key**, not an API key. Install attribution requires an SDK key. An API key cannot record installs, whatever scopes it holds
2. Verify the key is still active in the dashboard under **Keys** > **SDK keys**
3. Create a new SDK key if the current one was revoked

**Telltale symptom of the wrong key type:** deep links resolve normally, but no installs appear in your dashboard. Both credentials share the `wl_live_` prefix, so check the key type in the dashboard rather than reading the string.

---

### `E_NETWORK_ERROR` (`WarpLinkNetworkException`)

**When:** A request fails after the native SDK's retries: no connectivity, DNS failure, or timeout.

**Fix:** Check device connectivity before retrying. The native SDK already retries transient failures a few times within a bounded budget, so do not add your own tight retry loop.

```dart
try {
  final link = await WarpLink.handleDeepLink(url);
} on WarpLinkNetworkException catch (error) {
  debugPrint('Network error: ${error.message}');
}
```

---

### `E_SERVER_ERROR` (`WarpLinkServerException`)

**When:** The WarpLink API answers with an unexpected status, or the failure is unknown.

**Fix:** Retry after a delay. `statusCode` holds the HTTP status when the native SDK knows it, and is `null` otherwise.

#### Server Status Code Reference

| Status Code | Meaning | Action |
|-------------|---------|--------|
| 401 | Unauthorized | Check the SDK key. Surfaces as `E_INVALID_API_KEY` |
| 403 | Forbidden | A password protected link returns `E_PASSWORD_REQUIRED`, otherwise confirm it is an SDK key, not an API key |
| 404 | Not found | Link does not exist. Surfaces as `E_LINK_NOT_FOUND` |
| 429 | Rate limited | Retry after a delay |
| 500 | Server error | Retry later, report if persistent |
| 503 | Service unavailable | Retry later |

---

### `E_INVALID_URL` (`WarpLinkInvalidUrlException`)

**When:** A URL passed to `handleDeepLink()` is not a WarpLink link. A WarpLink link has a host the SDK recognizes (`aplnk.to` plus your verified custom domains) and a path of exactly one segment.

**Fix:** Verify the URL host is `aplnk.to` or one of your verified custom domains. Custom domains must be verified and live in the dashboard.

If a custom-domain link fails only on the first launch after install, or only offline, the fetched domain list had not arrived yet. Declare the domain locally so it is recognized from the first line of `configure()`: `linkDomains: ['links.yourapp.com']`, a `WarpLinkDomains` array in `Info.plist`, or an `app.warplink.DOMAINS` manifest entry on Android. See [Custom link domains](api-reference.md#custom-link-domains).

Do not pre-filter URLs against a hardcoded host. That discards the custom-domain links the SDK resolves. Pass the URL to `handleDeepLink()`, or check it with `WarpLink.isWarpLinkUrl(url)`, and treat `E_INVALID_URL` as "not a WarpLink URL".

---

### `E_LINK_NOT_FOUND` (`WarpLinkLinkNotFoundException`)

**When:** The link slug does not exist, or the link has been deactivated or has expired (HTTP 404).

**Fix:**
1. Verify the link exists in the [WarpLink dashboard](https://warplink.app)
2. Check that the link is active
3. Make sure the slug in the URL matches

---

### `E_PASSWORD_REQUIRED` (`WarpLinkPasswordRequiredException`)

**When:** The link is password protected (HTTP 403). Resolving it returns no destination and no platform URLs, because the password is checked in the browser and the app never sees it.

**Fix:** Open the short URL itself in a browser. The password form lives there, and a correct password redirects on to the destination.

```dart
case WarpLinkPasswordRequiredException():
  openInBrowser(tappedUrl); // for example, with url_launcher in your app
```

---

### `E_DECODING_ERROR` (`WarpLinkDecodingException`)

**When:** A response or native payload could not be decoded. This can mean an SDK version mismatch with the API.

**Fix:** Update the SDK to the latest version. If the issue persists, enable `debugLogging` and report the error.

---

## Complete Error Handling Example

```dart
void handleWarpLinkError(WarpLinkException error, {String? tappedUrl}) {
  switch (error) {
    case WarpLinkNotConfiguredException():
      // Programming error: configure the SDK earlier in the app lifecycle.
      debugPrint('WarpLink SDK not configured');
    case WarpLinkInvalidApiKeyFormatException():
      // Programming error: check the key format.
      debugPrint('Invalid WarpLink key format');
    case WarpLinkInvalidApiKeyException():
      // SDK key revoked, incorrect, or an API key was passed instead.
      showMessage('Authentication error. Please update the app.');
    case WarpLinkNetworkException():
      showMessage('No internet connection. Please try again.');
    case WarpLinkServerException(:final statusCode):
      debugPrint('WarpLink server error: $statusCode');
      showMessage('Server error. Please try again later.');
    case WarpLinkInvalidUrlException():
      // Not a WarpLink URL: ignore or hand it to another handler.
      break;
    case WarpLinkLinkNotFoundException():
      showMessage('This link is no longer available.');
    case WarpLinkPasswordRequiredException():
      // The password is checked in the browser, never in the app.
      if (tappedUrl != null) openInBrowser(tappedUrl);
    case WarpLinkDecodingException():
      showMessage('Please update the app to the latest version.');
  }
}
```

### Usage with async methods

```dart
try {
  final link = await WarpLink.handleDeepLink(url);
  if (link != null) navigateTo(link.destination);
} on WarpLinkException catch (error) {
  handleWarpLinkError(error, tappedUrl: url);
}
```

### Usage with `onLink` and streams

```dart
await WarpLink.configure(
  apiKey: 'wl_live_yoursdkkeyhere000000000000000000',
  onLink: (event) {
    switch (event) {
      case LinkEvent(:final deepLink):
        navigateTo(deepLink.destination);
      case ErrorEvent(:final error):
        handleWarpLinkError(error);
    }
  },
);
```

Listener errors occur when the native layer receives a URL but resolution fails (network error, link not found, and so on). A failing background deferred check on a launch with no network also arrives here. The gate stays open and the next launch retries, so treat that error as a report.

## Related Guides

- [API Reference](api-reference.md): `WarpLinkException` and `WarpLinkErrorCode` documentation
- [Troubleshooting](troubleshooting.md): common issues and solutions
