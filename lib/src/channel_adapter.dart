import 'package:warplink_flutter/src/arrival.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/src/deep_link.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/ledger_signal.dart';

/// Speaks the arrival ledger half of the channel contract.
///
/// Decodes payloads and keeps every failure a [WarpLinkException]. It holds no
/// dispatch policy: who claims, resolves, or delivers an arrival is decided
/// by the callers.
final class ChannelAdapter {
  /// Creates an adapter over [channel].
  ChannelAdapter(this._channel);

  final WarpLinkChannel _channel;

  /// The handshake and the arrivals announced while a listener exists.
  ///
  /// A malformed payload arrives as a stream error holding a
  /// [WarpLinkDecodingException].
  Stream<LedgerSignal> get signals =>
      _channel.arrivals.map(LedgerSignal.fromMap);

  /// Every arrival the ledger still holds, oldest first.
  ///
  /// Native answers only once it knows whether this process has a launch
  /// arrival, so the list is never missing a launch URL that is still coming.
  Future<List<Arrival>> pendingArrivals() async {
    final raw = await _channel.invoke(WarpLinkMethod.getPendingArrivals);
    if (raw is! List<Object?>) {
      throw const WarpLinkDecodingException('Pending arrivals are not a list');
    }
    return raw.map(Arrival.fromMap).toList(growable: false);
  }

  /// Claims [arrivalId] and resolves it.
  ///
  /// A repeated claim joins the first: native makes one resolve and every
  /// caller sees its answer, a link, `null`, or the same error. An id native
  /// no longer holds answers `null`.
  Future<WarpLinkDeepLink?> resolveArrival(String arrivalId) =>
      _decodeLink(WarpLinkMethod.resolveArrival, {'arrivalId': arrivalId});

  /// Resolves [url] as an independent manual request, outside the ledger.
  Future<WarpLinkDeepLink?> handleDeepLink(String url) =>
      _decodeLink(WarpLinkMethod.handleDeepLink, {'url': url});

  /// Claims the one delivery of [arrivalId].
  ///
  /// Native answers `true` to the first claim only. `false` means another
  /// engine, or an earlier run of this one, already delivered the arrival, or
  /// native no longer holds it. A failed call throws.
  Future<bool> claimDelivery(String arrivalId) async {
    final raw = await _channel.invoke(WarpLinkMethod.claimDelivery, {
      'arrivalId': arrivalId,
    });
    return raw == true;
  }

  /// Whether native treats [url] as a WarpLink link.
  ///
  /// Native answers `false` for an unparsable string. A failed call throws.
  Future<bool> isWarpLinkUrl(String url) async {
    final raw = await _channel.invoke(WarpLinkMethod.isWarpLinkUrl, {
      'url': url,
    });
    return raw == true;
  }

  /// Whether install attribution has completed for this install.
  Future<bool> isAttributionComplete() async =>
      await _channel.invoke(WarpLinkMethod.isAttributionComplete) == true;

  /// Runs the native deferred check. `null` is a confirmed no-match.
  Future<WarpLinkDeepLink?> checkDeferredDeepLink() =>
      _decodeLink(WarpLinkMethod.checkDeferredDeepLink);

  Future<WarpLinkDeepLink?> _decodeLink(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final raw = await _channel.invoke(method, arguments);
    return raw == null ? null : WarpLinkDeepLink.fromMap(raw);
  }
}
