import 'package:warplink_flutter/src/channel_adapter.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/events.dart';

/// The answer of one deferred check, delivered at most once.
final class _Outcome {
  _Outcome(this.event);

  /// The link or error to deliver, or `null` for nothing to deliver.
  final WarpLinkEvent? event;
  bool delivered = false;
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
    if (event == null || deliver == null || outcome.delivered) {
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
    return _inFlight ??= _check().whenComplete(() => _inFlight = null);
  }

  Future<_Outcome> _check() async {
    try {
      if (await _adapter.isAttributionComplete()) {
        return _Outcome(null);
      }
      final deepLink = await _adapter.checkDeferredDeepLink();
      return _Outcome(deepLink == null ? null : LinkEvent(deepLink));
    } on WarpLinkException catch (error) {
      return _Outcome(ErrorEvent(error));
    }
  }
}
