import 'dart:async';

import 'package:warplink_flutter/src/channel_adapter.dart';
import 'package:warplink_flutter/src/deep_link.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/events.dart';
import 'package:warplink_flutter/src/retry_gate.dart';

/// The answer of one deferred check, delivered at most once.
final class _Outcome {
  _Outcome(this.event, this.epoch);

  /// The link or error to deliver, or `null` for nothing to deliver.
  final WarpLinkEvent? event;
  bool delivered = false;

  /// The reset epoch the check started under.
  final int epoch;
}

/// The last link given to `onLink` by the deferred check, and how to give it
/// another.
final class _Route {
  _Route(this.link, this.deliver, this.isCurrent);

  final WarpLinkDeepLink link;
  final void Function(WarpLinkEvent event) deliver;
  final bool Function() isCurrent;
}

bool _sameRoute(WarpLinkDeepLink a, WarpLinkDeepLink b) => a.linkId.isNotEmpty
    ? a.linkId == b.linkId
    : b.linkId.isEmpty && a.destination == b.destination;

/// Runs the install attribution check after cold dispatch.
///
/// Native keeps its own once-per-install gate and answers the stored match on
/// every call after it completes, so the automatic path asks
/// `isAttributionComplete` first and dispatches only while it is open. One
/// process-wide claim keeps a reconfigure from losing or repeating the answer.
/// A repeat `configure` of the live session may ask once more, through
/// `run(retry: true)`.
final class DeferredCoordinator {
  /// Creates a coordinator that talks through [adapter].
  DeferredCoordinator(
    ChannelAdapter adapter, {
    DateTime Function() now = DateTime.now,
  }) : _adapter = adapter,
       _gate = RetryGate(adapter, now: now);

  final ChannelAdapter _adapter;
  final RetryGate _gate;
  Future<_Outcome>? _inFlight;
  _Outcome? _undelivered;
  _Route? _routed;
  int _epoch = 0;

  /// Whether a check has started under the native session now live. A session
  /// asks once by itself. A repeat `configure` may ask again, and native's own
  /// backoff and limits decide whether that sends a request.
  bool _checked = false;

  /// Discards the check in flight and any link held for a later call.
  ///
  /// Their answers belong to attribution that has been cleared. The next [run]
  /// asks native again.
  void discard() {
    _epoch++;
    _inFlight = null;
    _undelivered = null;
    _routed = null;
    _checked = false;
  }

  /// Opens the way for one more check: native took a configuration that
  /// rebuilt its session. A link held for a later call stays held.
  void startSession() => _checked = false;

  /// Gives `onLink` the exact link a Tether read resolved, when the deferred
  /// check already gave it a different one, usually an estimate.
  ///
  /// Does nothing when `onLink` was never given a link, was replaced by a
  /// newer configuration, or already holds this link. Links are the same when
  /// their link id matches, or their destination when there is no id: stronger
  /// evidence for the same link is not a new route. An exception from the
  /// host's callback goes to the zone's error handler, never into the read.
  void routeTetherMatch(WarpLinkDeepLink link) {
    final route = _routed;
    if (route == null || !route.isCurrent() || _sameRoute(route.link, link)) {
      return;
    }
    _routed = _Route(link, route.deliver, route.isCurrent);
    try {
      route.deliver(LinkEvent(link));
    } on Object catch (error, stack) {
      Zone.current.handleUncaughtError(error, stack);
    }
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
  ///
  /// A [retry] is a repeat `configure` of the live session. When a check
  /// already started it asks native once more, but only while native says the
  /// check is neither finished nor running.
  Future<void> run({
    required bool Function() isCurrent,
    void Function(WarpLinkEvent event)? deliver,
    bool retry = false,
  }) async {
    final outcome = await _outcome(retry: retry);
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
      if (event is LinkEvent) {
        _routed = _Route(event.deepLink, deliver, isCurrent);
      }
      deliver(event);
    } else if (event is LinkEvent) {
      _undelivered = outcome;
    }
  }

  Future<_Outcome> _outcome({required bool retry}) {
    final held = _undelivered;
    if (held != null) {
      return Future<_Outcome>.value(held);
    }
    final running = _inFlight;
    if (running != null) {
      return running;
    }
    final isRetry = _checked;
    if (isRetry && !retry) {
      return Future<_Outcome>.value(_Outcome(null, _epoch));
    }
    late final Future<_Outcome> check;
    check = _check(isRetry: isRetry).whenComplete(() {
      if (identical(_inFlight, check)) {
        _inFlight = null;
      }
    });
    return _inFlight = check;
  }

  Future<_Outcome> _check({required bool isRetry}) async {
    final epoch = _epoch;
    _checked = true;
    try {
      final skip = isRetry
          ? !await _gate.mayRetry()
          : await _adapter.isAttributionComplete();
      // A reset can land during the await: the native check would refill
      // cleared state or touch the session configured since.
      if (skip || epoch != _epoch) {
        return _Outcome(null, epoch);
      }
      final deepLink = await _adapter.checkDeferredDeepLink();
      return _Outcome(deepLink == null ? null : LinkEvent(deepLink), epoch);
    } on WarpLinkException catch (error) {
      return _Outcome(ErrorEvent(error), epoch);
    }
  }
}
