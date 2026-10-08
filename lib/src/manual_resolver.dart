import 'package:warplink_flutter/src/arrival.dart';
import 'package:warplink_flutter/src/channel_adapter.dart';
import 'package:warplink_flutter/src/deep_link.dart';
import 'package:warplink_flutter/src/events.dart';
import 'package:warplink_flutter/src/link_classifier.dart';
import 'package:warplink_flutter/src/resolution_registry.dart';
import 'package:warplink_flutter/src/tap_policy.dart';

/// Resolves links for manual callers, outside the automatic path.
///
/// A manual resolve of a WarpLink link claims a silent tap first, so it
/// supersedes older automatic taps and never delivers to `onLink`.
final class ManualResolver {
  /// Creates a resolver.
  ManualResolver({
    required ChannelAdapter adapter,
    required LinkClassifier classifier,
    required TapPolicy policy,
    required ResolutionRegistry registry,
  }) : _adapter = adapter,
       _classifier = classifier,
       _policy = policy,
       _registry = registry;

  final ChannelAdapter _adapter;
  final LinkClassifier _classifier;
  final TapPolicy _policy;
  final ResolutionRegistry _registry;

  /// Resolves the ledger entry [arrival] for a manual caller.
  ///
  /// Returns `null` when native had already delivered the arrival. A failed
  /// claim throws, and the caller may try again.
  Future<WarpLinkEvent?> resolveArrival(Arrival arrival) async {
    final tap = await _claimSilently(arrival.url);
    final event = await _registry.resolve(arrival.arrivalId);
    _settleSilently(tap);
    return await _adapter.claimDelivery(arrival.arrivalId) ? event : null;
  }

  /// Resolves [url] as an independent manual request.
  ///
  /// A WarpLink link supersedes older automatic taps, even one of the same
  /// URL, because the native resolve cancels the request still in flight. The
  /// answer is the caller's alone.
  Future<WarpLinkDeepLink?> handleDeepLink(String url) async {
    final tap = await _claimSilently(url);
    try {
      return await _adapter.handleDeepLink(url);
    } finally {
      _settleSilently(tap);
    }
  }

  Future<Tap?> _claimSilently(String url) async =>
      await _classifier.isWarpLink(url) ? _policy.claimSilent() : null;

  void _settleSilently(Tap? tap) {
    if (tap != null) {
      _policy.settle(tap, failed: false);
    }
  }
}
