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
  });

  /// The configuration before any `configure`: nothing is automatic.
  static const DispatchConfig none = DispatchConfig(
    onLink: null,
    automaticDeepLinks: false,
    automaticDeferredDeepLinks: false,
  );

  /// The single sink for cold-start, warm-start, and deferred links.
  final WarpLinkListener? onLink;

  /// The host's own option. It takes effect only with [onLink].
  final bool automaticDeepLinks;

  /// Whether to run the deferred check from `configure`.
  final bool automaticDeferredDeepLinks;

  /// Whether arrivals are dispatched to [onLink] automatically.
  bool get autoDeliversLinks => onLink != null && automaticDeepLinks;
}
