import 'package:warplink_flutter/src/events.dart';

/// The options of one `configure` call, as dispatch sees them.
///
/// Each accepted `configure` creates a new instance. Identity is the
/// generation: work that started under an older instance may not deliver to
/// the newer one's callback.
final class DispatchConfig {
  /// Creates a configuration.
  const DispatchConfig({
    required this.onLink,
    required this.automaticDeepLinks,
    required this.automaticDeferredDeepLinks,
    this.isTestKey = false,
    this.apiKey,
  });

  /// The configuration before any `configure`: nothing is automatic.
  static const DispatchConfig none = DispatchConfig(
    onLink: null,
    automaticDeepLinks: false,
    automaticDeferredDeepLinks: false,
  );

  /// The single sink for cold-start, warm-start, and deferred links.
  final WarpLinkListener? onLink;

  /// The API key of the configuration, or `null` before any `configure`.
  ///
  /// Compared only to tell a key change from a repeat; never logged.
  final String? apiKey;

  /// Whether the configuration uses a `wl_test_` key.
  final bool isTestKey;

  /// The host's own option. It takes effect only with [onLink].
  final bool automaticDeepLinks;

  /// Whether to run the deferred check from `configure`.
  final bool automaticDeferredDeepLinks;

  /// Whether arrivals are dispatched to [onLink] automatically.
  bool get autoDeliversLinks => onLink != null && automaticDeepLinks;
}
