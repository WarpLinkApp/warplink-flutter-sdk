import 'package:warplink_flutter/src/channel_adapter.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/events.dart';

/// The answer of one deferred check, delivered at most once.
final class _Outcome {
  _Outcome(this.event, this.epoch);

  /// The link or error to deliver, or `null` for nothing to deliver.
  final WarpLinkEvent? event;
  bool delivered = false;

  /// The reset epoch the check started under.
  final int epoch;
}

/// Runs the install attribution check after cold dispatch.
///
/// Native keeps its own once-per-install gate and answers the stored match on
/// every call after it completes, so the automatic path asks
/// `isAttributionComplete` first and dispatches only while it is open. One
/// process-wide claim keeps a reconfigure from losing or repeating the answer.
final class DeferredCoordinator {
  /// Creates a coordinator that talks through [adapter].
  DeferredCoordinator(this._adapter);

  final ChannelAdapter _adapter;
  Future<_Outcome>? _inFlight;
  _Outcome? _undelivered;
  int _epoch = 0;

  /// Discards the check in flight and any link held for a later call.
  ///
  /// Their answers belong to attribution that has been cleared. The next [run]
  /// asks native again.
  void discard() {
    _epoch++;
    _inFlight = null;
    _undelivered = null;
  }

  /// Runs the deferred check and delivers its answer through [deliver].
  ///
  /// The check runs once however many configurations overlap: a later call
  /// joins the one in flight. Only a call whose [isCurrent] is still true at
  /// the answer delivers. A link no current call could take is held for the
  /// next call, so a reconfigure neither drops nor repeats it. A no-match
  /// delivers nothing. A failure delivers an error and leaves native's gate
  /// open, so the next launch retries.
  ///
  /// With a `null` [deliver] the check still runs, because the request is what
  /// attributes the install.
  Future<void> run({
    required bool Function() isCurrent,
    void Function(WarpLinkEvent event)? deliver,
  }) async {
    final outcome = await _outcome();
    final event = outcome.event;
    if (outcome.epoch != _epoch ||
        event == null ||
        deliver == null ||
        outcome.delivered) {
      return;
    }
    if (isCurrent()) {
      outcome.delivered = true;
      if (identical(_undelivered, outcome)) {
        _undelivered = null;
      }
      deliver(event);
    } else if (event is LinkEvent) {
      _undelivered = outcome;
    }
  }

  Future<_Outcome> _outcome() {
    final held = _undelivered;
    if (held != null) {
      return Future<_Outcome>.value(held);
    }
    final running = _inFlight;
    if (running != null) {
      return running;
    }
    late final Future<_Outcome> check;
    check = _check().whenComplete(() {
      if (identical(_inFlight, check)) {
        _inFlight = null;
      }
    });
    return _inFlight = check;
  }

  Future<_Outcome> _check() async {
    final epoch = _epoch;
    try {
      final complete = await _adapter.isAttributionComplete();
      // A reset can land during the await: the native check would refill
      // cleared state or touch the session configured since.
      if (complete || epoch != _epoch) {
        return _Outcome(null, epoch);
      }
      final deepLink = await _adapter.checkDeferredDeepLink();
      return _Outcome(deepLink == null ? null : LinkEvent(deepLink), epoch);
    } on WarpLinkException catch (error) {
      return _Outcome(ErrorEvent(error), epoch);
    }
  }
}
