import 'package:flutter/foundation.dart';
import 'package:warplink_flutter/src/errors.dart';

/// Where the first-launch link check stands for this install.
enum DeferredCheckState {
  /// No check has finished yet and none is running. A failed check whose wait
  /// is over reads this too.
  notChecked,

  /// A check is running, or waiting for the app to come on screen.
  checking,

  /// The check finished and found a link.
  matched,

  /// The check finished and found no link.
  noMatch,

  /// A check failed. No request is sent before [DeferredCheckStatus.retryAt].
  waiting,

  /// The install is older than 30 days by default, so no request is sent.
  skippedOldInstall,

  /// The SDK gave up, 3 days by default after the first failure. No request is
  /// sent.
  stopped,
}

/// The state of the first-launch link check, read without sending anything.
///
/// It tells a skipped check from no match, and it comes from state stored on
/// the device, so it survives a relaunch. A `wl_test_` key never reports
/// [DeferredCheckState.waiting], [DeferredCheckState.skippedOldInstall] or
/// [DeferredCheckState.stopped].
@immutable
final class DeferredCheckStatus {
  /// Creates a status.
  const DeferredCheckStatus({required this.state, this.retryAt});

  /// Decodes a platform channel map: `state`, plus `retryAt` in epoch
  /// milliseconds for `waiting`.
  ///
  /// Throws [WarpLinkDecodingException] when [raw] is not a map, the state is
  /// unknown, or a waiting state has no retry time.
  factory DeferredCheckStatus.fromMap(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      throw const WarpLinkDecodingException(
        'Native deferred check status is not a map',
      );
    }
    final state = DeferredCheckState.values
        .where((known) => known.name == raw['state'])
        .firstOrNull;
    if (state == null) {
      throw const WarpLinkDecodingException(
        'Native deferred check status has an unknown state',
      );
    }
    if (state != DeferredCheckState.waiting) {
      return DeferredCheckStatus(state: state);
    }
    final retryAt = raw['retryAt'];
    if (retryAt is! num) {
      throw const WarpLinkDecodingException(
        'Native waiting status has no retry time',
      );
    }
    return DeferredCheckStatus(
      state: state,
      retryAt: DateTime.fromMillisecondsSinceEpoch(
        retryAt.toInt(),
        isUtc: true,
      ),
    );
  }

  /// Where the check stands.
  final DeferredCheckState state;

  /// When the next check is allowed. Set only for
  /// [DeferredCheckState.waiting].
  final DateTime? retryAt;

  @override
  bool operator ==(Object other) =>
      other is DeferredCheckStatus &&
      other.state == state &&
      other.retryAt == retryAt;

  @override
  int get hashCode => Object.hash(state, retryAt);

  @override
  String toString() => 'DeferredCheckStatus($state, retryAt: $retryAt)';
}
