import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/events.dart';

final RegExp _apiKeyPattern = RegExp(r'^wl_(live|test)_[a-zA-Z0-9]{32}$');

/// The text reported for a key that fails [isValidApiKey].
const String invalidApiKeyMessage =
    'Invalid API key format. Expected: wl_live_xxx or wl_test_xxx '
    '(32 alphanumeric characters after prefix)';

/// Whether [apiKey] has the `wl_live_` or `wl_test_` format.
bool isValidApiKey(String apiKey) => _apiKeyPattern.hasMatch(apiKey);

/// Logs the format error and hands it to [onLink].
///
/// The log line uses `print` because `debugPrint` and `developer.log` do not
/// reach release builds, and a bad key must be visible there too.
void reportInvalidApiKey(WarpLinkListener? onLink) {
  // ignore: avoid_print
  print('[WarpLink] $invalidApiKeyMessage');
  onLink?.call(
    const ErrorEvent(
      WarpLinkInvalidApiKeyFormatException(invalidApiKeyMessage),
    ),
  );
}
