import 'package:flutter/foundation.dart';
import 'package:warplink_flutter/src/errors.dart';

/// One URL the host app received, as recorded by the native arrival ledger.
///
/// The [arrivalId] is native's identity for one OS delivery. Two taps on the
/// same URL have two ids. One OS delivery has one id however many times native
/// reports it. [seq] and [arrivedAtMs] come from native, so order and timing
/// do not depend on when Dart learns of the arrival.
@immutable
final class Arrival {
  /// Creates an arrival.
  const Arrival({
    required this.arrivalId,
    required this.url,
    required this.source,
    required this.isLaunch,
    required this.seq,
    required this.arrivedAtMs,
  });

  /// Decodes a ledger entry or an arrivals event payload.
  ///
  /// Throws [WarpLinkDecodingException] for a payload that lacks an id, a URL,
  /// or a native sequence number and arrival time.
  factory Arrival.fromMap(Object? raw) {
    if (raw is Map<Object?, Object?>) {
      final arrivalId = raw['arrivalId'];
      final url = raw['url'];
      final seq = raw['seq'];
      final arrivedAtMs = raw['arrivedAtMs'];
      if (arrivalId is String &&
          url is String &&
          seq is int &&
          arrivedAtMs is int) {
        return Arrival(
          arrivalId: arrivalId,
          url: url,
          source: raw['source']?.toString() ?? '',
          isLaunch: raw['isLaunch'] == true,
          seq: seq,
          arrivedAtMs: arrivedAtMs,
        );
      }
    }
    throw const WarpLinkDecodingException('Malformed arrival payload');
  }

  /// Native identity of the OS delivery.
  final String arrivalId;

  /// The URL as the OS delivered it.
  final String url;

  /// Diagnostic label of the OS entry point. Dart never branches on it.
  final String source;

  /// Whether this arrival launched the process.
  final bool isLaunch;

  /// Position in native's recording order, unique per process.
  final int seq;

  /// When native recorded the arrival, in milliseconds on a native monotonic
  /// clock that is only comparable within one process.
  final int arrivedAtMs;

  /// [arrivedAtMs] as a duration, the time base of the dedupe window.
  Duration get arrivedAt => Duration(milliseconds: arrivedAtMs);

  @override
  bool operator ==(Object other) =>
      other is Arrival &&
      other.arrivalId == arrivalId &&
      other.url == url &&
      other.source == source &&
      other.isLaunch == isLaunch &&
      other.seq == seq &&
      other.arrivedAtMs == arrivedAtMs;

  @override
  int get hashCode =>
      Object.hash(arrivalId, url, source, isLaunch, seq, arrivedAtMs);

  @override
  String toString() => 'Arrival($arrivalId, #$seq, $url, launch: $isLaunch)';
}
