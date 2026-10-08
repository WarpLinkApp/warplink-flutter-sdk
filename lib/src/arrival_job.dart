import 'dart:async';

import 'package:warplink_flutter/src/arrival.dart';
import 'package:warplink_flutter/src/held_answers.dart';
import 'package:warplink_flutter/src/tap_policy.dart';

/// One arrival on its way to a recipient, from admission to its end.
///
/// Dispatch events advance it. It holds facts about the arrival and its
/// native answers, and no recipient: those come from the state at each step.
final class ArrivalJob {
  /// Creates a job for [arrival].
  ArrivalJob(this.arrival);

  /// The ledger entry.
  final Arrival arrival;

  /// Whether native classified the URL as a WarpLink link, once asked.
  bool? isLink;

  /// Whether the classification is in flight.
  bool isClassifying = false;

  /// The tap of a planned resolve, when the URL is a WarpLink link.
  Tap? tap;

  /// Whether the plan resolves the arrival. Otherwise it is claimed and
  /// discarded.
  bool resolves = false;

  /// Whether the native resolve answered.
  bool isResolved = false;

  /// The answer, when the resolve produced one.
  Answer? answer;

  /// Whether the delivery claim was requested.
  bool isClaiming = false;

  /// Whether native granted the delivery claim.
  bool isClaimed = false;

  final Completer<void> _end = Completer<void>();

  /// Completes when the job ends: delivered, held, left, or dropped.
  Future<void> get done => _end.future;

  /// Whether the job ended.
  bool get isDone => _end.isCompleted;

  /// Ends the job.
  void end() {
    if (!isDone) {
      _end.complete();
    }
  }
}
