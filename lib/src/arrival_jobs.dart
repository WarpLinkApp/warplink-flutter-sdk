import 'package:warplink_flutter/src/arrival.dart';
import 'package:warplink_flutter/src/arrival_book.dart';
import 'package:warplink_flutter/src/arrival_job.dart';
import 'package:warplink_flutter/src/resolution_registry.dart';

/// The live jobs, one per arrival, and how a job leaves them.
///
/// A job ends in one of two ways. A finished job is remembered and never
/// admitted again, and its stored resolve is forgotten. A job that left is
/// forgotten, so the next ledger replay offers the arrival again.
final class ArrivalJobs {
  /// Creates the set. Finished arrivals forget their resolve in [registry].
  ArrivalJobs(this._registry);

  final ResolutionRegistry _registry;
  final ArrivalBook _book = ArrivalBook();
  final Map<String, ArrivalJob> _live = <String, ArrivalJob>{};

  /// The live jobs, as of now.
  List<ArrivalJob> get live => _live.values.toList();

  /// The live launch job, if any.
  ArrivalJob? get launch =>
      live.where((job) => job.arrival.isLaunch).firstOrNull;

  /// Starts a job for [arrival], unless it is live, finished, or taken.
  ArrivalJob? admit(Arrival arrival) {
    if (!_book.admit(arrival.arrivalId)) {
      return null;
    }
    return _live[arrival.arrivalId] = ArrivalJob(arrival);
  }

  /// Ends [job] without delivering, so a later replay offers it again.
  void leave(ArrivalJob job) {
    if (_forget(job)) {
      _book.release(job.arrival.arrivalId);
    }
    job.end();
  }

  /// Ends [job] for good.
  void finish(ArrivalJob job) {
    _forget(job);
    _finished(job.arrival);
    job.end();
  }

  /// Takes the launch [arrival] for a manual caller, if nothing else has it.
  bool take(Arrival arrival) {
    final isTakeable = _book.isTakeable(arrival);
    if (isTakeable) {
      _book.take(arrival.arrivalId);
    }
    return isTakeable;
  }

  /// Returns [arrival] to manual callers, after the take failed.
  void untake(Arrival arrival) => _book.untake(arrival.arrivalId);

  /// Ends a manual take of [arrival] that delivered its answer.
  void finishTaken(Arrival arrival) => _finished(arrival);

  bool _forget(ArrivalJob job) {
    final isLive = identical(_live[job.arrival.arrivalId], job);
    if (isLive) {
      _live.remove(job.arrival.arrivalId);
    }
    return isLive;
  }

  void _finished(Arrival arrival) {
    _book.finish(arrival.arrivalId);
    _registry.forget(arrival.arrivalId);
  }
}
