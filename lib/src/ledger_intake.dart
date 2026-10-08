import 'dart:async';

import 'package:warplink_flutter/src/arrival.dart';
import 'package:warplink_flutter/src/channel_adapter.dart';
import 'package:warplink_flutter/src/ledger_error.dart';
import 'package:warplink_flutter/src/ledger_signal.dart';

/// Feeds arrivals from the native ledger to one consumer, in native order.
///
/// Listens for announcements and replays the ledger. The replay is requested
/// only after native signalled that its listener is open, so no arrival falls
/// between the snapshot and the listener. An arrival can come by both routes.
/// While a replay is in flight the announcements are held, and the replay and
/// the held announcements are handed over together: joined by arrival id and
/// sorted by native sequence number.
final class LedgerIntake {
  /// Creates an intake that hands every arrival it learns of to [onArrival].
  LedgerIntake(this._adapter, this._onArrival);

  final ChannelAdapter _adapter;
  final void Function(Arrival arrival) _onArrival;
  final List<Arrival> _held = <Arrival>[];
  StreamSubscription<LedgerSignal>? _listening;
  Completer<void> _ready = Completer<void>();
  int _replaysOpen = 0;

  /// Completes when the latest replay has handed over every entry.
  Future<void> replayed = Future<void>.value();

  /// Listens for announcements, if not yet, and replays the ledger.
  void start() {
    _listening ??= _adapter.signals.listen(
      _onSignal,
      onError: reportLedgerError,
    );
    _replaysOpen++;
    replayed = replayed.then((_) => _replay());
  }

  /// Stops listening. The ledger keeps what arrives.
  Future<void> stop() async {
    final listening = _listening;
    _listening = null;
    final ready = _ready;
    _ready = Completer<void>();
    if (!ready.isCompleted) {
      ready.complete();
    }
    await listening?.cancel();
  }

  void _onSignal(LedgerSignal signal) {
    switch (signal) {
      case ListenerReady():
        if (!_ready.isCompleted) {
          _ready.complete();
        }
      case ArrivalAnnounced(:final arrival):
        if (_replaysOpen > 0) {
          _held.add(arrival);
        } else {
          _onArrival(arrival);
        }
    }
  }

  Future<void> _replay() async {
    var pending = const <Arrival>[];
    try {
      await _ready.future;
      pending = await _adapter.pendingArrivals();
    } on Exception catch (error) {
      reportLedgerError(error);
    }
    _replaysOpen--;
    final batch = <Arrival>[...pending, ..._held];
    _held.clear();
    _handOver(batch);
  }

  void _handOver(List<Arrival> batch) {
    final seen = <String>{};
    batch.where((arrival) => seen.add(arrival.arrivalId)).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq))
      ..forEach(_onArrival);
  }
}
