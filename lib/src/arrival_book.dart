import 'package:warplink_flutter/src/arrival.dart';

/// How many finished arrival ids are remembered, to refuse a late replay.
const int _finishedMemory = 256;

/// Remembers which arrivals are being dispatched, finished, or taken.
///
/// An announcement and a ledger replay can both carry one arrival, and a new
/// configuration must see arrivals no earlier configuration delivered. This
/// book answers both: an arrival is admitted once while it is live, never
/// after it finished, and never after a manual caller took it.
///
/// Native owns whether an arrival was delivered. The book only keeps a bounded
/// memory of finished ids, so a late announcement of one is refused here
/// before it costs a call.
final class ArrivalBook {
  final Set<String> _live = <String>{};
  final Set<String> _finished = <String>{};
  final Set<String> _taken = <String>{};

  /// Records [id] as live.
  ///
  /// Returns `false` when [id] needs no admission: it is live, it finished, or
  /// a manual caller took it.
  bool admit(String id) =>
      !_finished.contains(id) && !_taken.contains(id) && _live.add(id);

  /// Whether a manual caller may take [arrival]: the launch arrival, not live,
  /// finished, or taken.
  bool isTakeable(Arrival arrival) =>
      arrival.isLaunch &&
      !_live.contains(arrival.arrivalId) &&
      !_finished.contains(arrival.arrivalId) &&
      !_taken.contains(arrival.arrivalId);

  /// Marks [id] as taken by a manual caller.
  void take(String id) => _taken.add(id);

  /// Returns [id] to the manual callers, after the take failed.
  void untake(String id) => _taken.remove(id);

  /// Forgets that [id] is live, so the next replay admits it again.
  void release(String id) => _live.remove(id);

  /// Marks [id] as finished.
  void finish(String id) {
    _live.remove(id);
    if (_finished.add(id) && _finished.length > _finishedMemory) {
      _finished.remove(_finished.first);
    }
  }
}
