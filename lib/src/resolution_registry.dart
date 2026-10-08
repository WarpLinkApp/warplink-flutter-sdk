import 'package:warplink_flutter/src/channel_adapter.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/events.dart';

/// Gives each arrival exactly one native resolve and one shared outcome.
///
/// Every feed that wants an arrival's answer asks here, so `onLink` and every
/// `onDeepLink` subscriber see the same parsed result from one native call.
final class ResolutionRegistry {
  /// Creates a registry that resolves through [adapter].
  ResolutionRegistry(this._adapter);

  final ChannelAdapter _adapter;
  final Map<String, Future<WarpLinkEvent?>> _outcomes =
      <String, Future<WarpLinkEvent?>>{};

  /// The outcome of [arrivalId]: a [LinkEvent], an [ErrorEvent], or `null` when
  /// native resolved nothing. Never throws.
  ///
  /// The first call claims the arrival natively. Later calls return the same
  /// future until [forget].
  Future<WarpLinkEvent?> resolve(String arrivalId) =>
      _outcomes.putIfAbsent(arrivalId, () => _claim(arrivalId));

  /// Drops the stored outcome of [arrivalId], after the arrival is finished.
  void forget(String arrivalId) => _outcomes.remove(arrivalId);

  Future<WarpLinkEvent?> _claim(String arrivalId) async {
    try {
      final deepLink = await _adapter.resolveArrival(arrivalId);
      return deepLink == null ? null : LinkEvent(deepLink);
    } on WarpLinkException catch (error) {
      return ErrorEvent(error);
    }
  }
}
