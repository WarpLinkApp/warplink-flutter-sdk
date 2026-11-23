import 'package:warplink_flutter/src/channel_adapter.dart';
import 'package:warplink_flutter/src/deferred_check_status.dart';

/// The states in which a repeat `configure` asks native for one more check.
/// `waiting`, `skippedOldInstall` and `stopped` are in the set on purpose: the
/// native backoff and the age and give-up limits answer those without a
/// request, and Dart keeps no copy of those rules.
const Set<DeferredCheckState> _retryable = {
  DeferredCheckState.notChecked,
  DeferredCheckState.waiting,
  DeferredCheckState.skippedOldInstall,
  DeferredCheckState.stopped,
};

/// Decides whether a repeat `configure` may ask native for one more check.
final class RetryGate {
  /// Creates a gate that reads the status through [_adapter] and the time from
  /// [now].
  RetryGate(this._adapter, {DateTime Function() now = DateTime.now})
    : _now = now;

  /// How long a repeat waits after one that asked native.
  static const Duration window = Duration(minutes: 1);

  final ChannelAdapter _adapter;
  final DateTime Function() _now;
  DateTime? _lastAskedAt;

  /// Whether a repeat may ask native now: at most once a window per process,
  /// and only while native says the check is neither finished nor running.
  ///
  /// The elapsed time is a range check. The wall clock can move backwards, and
  /// a negative value then counts as a new window instead of holding every
  /// repeat back until the clock catches up.
  Future<bool> mayRetry() async {
    final lastAskedAt = _lastAskedAt;
    if (lastAskedAt != null) {
      final elapsed = _now().difference(lastAskedAt);
      if (!elapsed.isNegative && elapsed < window) {
        return false;
      }
    }
    final state = (await _adapter.deferredCheckStatus()).state;
    final retryable = _retryable.contains(state);
    if (retryable) {
      _lastAskedAt = _now();
    }
    return retryable;
  }
}
