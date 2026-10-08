import 'dart:async';

import 'package:warplink_flutter/src/arrival.dart';
import 'package:warplink_flutter/src/channel_adapter.dart';
import 'package:warplink_flutter/src/dispatch_config.dart';
import 'package:warplink_flutter/src/event_queue.dart';
import 'package:warplink_flutter/src/events.dart';
import 'package:warplink_flutter/src/ledger_intake.dart';
import 'package:warplink_flutter/src/link_dispatcher.dart';
import 'package:warplink_flutter/src/manual_resolver.dart';
import 'package:warplink_flutter/src/subscriber_feed.dart';

/// Turns host actions and ledger arrivals into events for the dispatcher.
///
/// Order and timing come from the native sequence number and arrival time,
/// never from when Dart learned of an arrival.
///
/// A new configuration replays the ledger, so an arrival that no earlier
/// configuration delivered is adopted by the newest one, and a duplicate
/// announcement joins the first.
final class ArrivalCoordinator {
  /// Creates a coordinator.
  ArrivalCoordinator({
    required ChannelAdapter adapter,
    required LinkDispatcher dispatcher,
    required EventQueue queue,
    required ManualResolver manual,
  }) : _adapter = adapter,
       _dispatcher = dispatcher,
       _queue = queue,
       _manual = manual {
    _intake = LedgerIntake(
      adapter,
      (arrival) => queue.post((_) => dispatcher.arrived(arrival)),
    );
    _feed = SubscriberFeed(
      onFirstListen: () => queue.postDeferred(_onSubscriberAdded),
      onLastCancel: () => queue.post(_onSubscriberRemoved),
    );
  }

  final ChannelAdapter _adapter;
  final LinkDispatcher _dispatcher;
  final EventQueue _queue;
  final ManualResolver _manual;
  late final LedgerIntake _intake;
  late final SubscriberFeed _feed;

  /// Every URL the host receives, resolved. See `WarpLink.onDeepLink`.
  Stream<WarpLinkEvent> get subscribers => _feed.stream;

  /// Pushes [event] to every subscriber.
  void emit(WarpLinkEvent event) => _feed.emit(event);

  /// The newest configuration.
  DispatchConfig get config => _dispatcher.state.config;

  /// Whether [config] is the newest configuration.
  bool isCurrent(DispatchConfig config) => identical(config, this.config);

  /// Starts a configuration and replays the ledger under it.
  ///
  /// Arrivals wait for [markConfigured] before they resolve.
  void begin(DispatchConfig config) => _queue.post((_) {
    _dispatcher.begin(config);
    _refresh();
  });

  /// Releases the arrivals of [config] once native configure finished.
  ///
  /// With `ok` false the arrivals stay in the ledger unresolved.
  void markConfigured(DispatchConfig config, {required bool ok}) =>
      _queue.post((outbox) => _dispatcher.configured(config, outbox, ok: ok));

  /// Completes when the launch arrival, if the automatic path owns it, is done.
  Future<void> coldDispatch() async {
    await _intake.replayed;
    final launch = await _queue.ask((_) => _dispatcher.jobs.launch);
    await launch?.done;
  }

  /// Takes the launch arrival for a manual caller, once, and resolves it.
  ///
  /// Returns `null` when the automatic path owns it, or there is none left.
  Future<WarpLinkEvent?> takeInitial() async {
    final busy = await _queue.ask((_) => _dispatcher.jobs.launch);
    await busy?.done;
    final (:isAutomatic, :held) = await _queue.ask(
      (_) => (
        isAutomatic: _dispatcher.state.config.autoDeliversLinks,
        held: _dispatcher.takeHeldLaunch(),
      ),
    );
    if (isAutomatic) {
      return null;
    }
    if (held != null) {
      return held;
    }
    final pending = await _adapter.pendingArrivals();
    final launch = pending.where((a) => a.isLaunch).firstOrNull;
    if (launch == null) {
      return null;
    }
    final isTaken = await _queue.ask((_) => _dispatcher.jobs.take(launch));
    if (isTaken) {
      return _resolveTaken(launch);
    }
    final isBusy = await _queue.ask((_) => _dispatcher.jobs.launch != null);
    return isBusy ? takeInitial() : null;
  }

  /// Releases the native listener and closes the subscriber stream.
  Future<void> dispose() async {
    _queue.close();
    await _intake.stop();
    await _feed.close();
  }

  Future<WarpLinkEvent?> _resolveTaken(Arrival launch) async {
    try {
      final event = await _manual.resolveArrival(launch);
      _queue.post((_) => _dispatcher.jobs.finishTaken(launch));
      return event;
    } on Exception {
      _queue.post((_) => _dispatcher.jobs.untake(launch));
      rethrow;
    }
  }

  void _onSubscriberAdded(Outbox outbox) {
    _dispatcher.subscribersChanged(outbox, present: true);
    _refresh();
  }

  void _onSubscriberRemoved(Outbox outbox) {
    _dispatcher.subscribersChanged(outbox, present: false);
    if (!_dispatcher.state.wantsArrivals) {
      unawaited(_intake.stop());
    }
  }

  void _refresh() {
    if (_dispatcher.state.wantsArrivals) {
      _intake.start();
    } else {
      unawaited(_intake.stop());
    }
  }
}
