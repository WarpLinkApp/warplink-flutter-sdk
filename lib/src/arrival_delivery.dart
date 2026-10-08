import 'dart:async';

import 'package:warplink_flutter/src/answer_router.dart';
import 'package:warplink_flutter/src/arrival_job.dart';
import 'package:warplink_flutter/src/arrival_jobs.dart';
import 'package:warplink_flutter/src/channel_adapter.dart';
import 'package:warplink_flutter/src/dispatch_state.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/event_queue.dart';
import 'package:warplink_flutter/src/events.dart';
import 'package:warplink_flutter/src/held_answers.dart';
import 'package:warplink_flutter/src/ledger_error.dart';
import 'package:warplink_flutter/src/resolution_registry.dart';
import 'package:warplink_flutter/src/tap_policy.dart';

/// Takes a planned job through resolve, claim, and delivery.
///
/// Each step starts a native call and ends in a handler of its own. The claim
/// is issued only when some recipient could take the answer then, or when the
/// answer is a superseded error that no recipient ever takes, so it is claimed
/// and dropped instead of replayed. The answer
/// goes to the recipients that exist when native confirmed the claim, or into
/// the held queue.
final class ArrivalDelivery {
  /// Creates the delivery stage.
  ArrivalDelivery({
    required DispatchState state,
    required EventQueue queue,
    required ChannelAdapter adapter,
    required TapPolicy policy,
    required ResolutionRegistry registry,
    required ArrivalJobs jobs,
    required AnswerRouter router,
  }) : _state = state,
       _queue = queue,
       _adapter = adapter,
       _policy = policy,
       _registry = registry,
       _jobs = jobs,
       _router = router;

  final DispatchState _state;
  final EventQueue _queue;
  final ChannelAdapter _adapter;
  final TapPolicy _policy;
  final ResolutionRegistry _registry;
  final ArrivalJobs _jobs;
  final AnswerRouter _router;

  /// Resolves a planned [job], or claims it to discard it.
  void start(ArrivalJob job) =>
      job.resolves ? _resolve(job) : _claimIfWanted(job);

  void _resolve(ArrivalJob job) {
    unawaited(
      _registry.resolve(job.arrival.arrivalId).then((event) {
        _queue.post((outbox) => _onResolved(job, event, outbox));
      }),
    );
  }

  void _onResolved(ArrivalJob job, WarpLinkEvent? event, Outbox outbox) {
    final tap = job.tap;
    if (tap != null) {
      _policy.settle(tap, failed: event is ErrorEvent);
    }
    if (job.isDone) {
      return;
    }
    job.isResolved = true;
    if (event != null) {
      job.answer = Answer(event, isLaunch: job.arrival.isLaunch, tap: tap);
    }
    if (job.isClaimed) {
      _deliver(job, outbox);
    } else if (_state.isConfigured) {
      _claimIfWanted(job);
    }
  }

  /// Settles the jobs whose answer came while native `configure` was open.
  ///
  /// With [ok] false they leave, so the next replay offers them again.
  void resume({required bool ok}) {
    for (final job in _jobs.live.where((job) => job.isResolved)) {
      if (job.isClaiming) {
        continue;
      }
      ok ? _claimIfWanted(job) : _jobs.leave(job);
    }
  }

  void _claimIfWanted(ArrivalJob job) =>
      _state.wants(job.arrival) || (job.answer?.isSupersededError ?? false)
      ? _claim(job)
      : _jobs.leave(job);

  void _claim(ArrivalJob job) {
    job.isClaiming = true;
    unawaited(_requestClaim(job));
  }

  Future<void> _requestClaim(ArrivalJob job) async {
    try {
      final claimed = await _adapter.claimDelivery(job.arrival.arrivalId);
      _queue.post((outbox) => _onClaimed(job, outbox, claimed: claimed));
    } on WarpLinkException catch (error) {
      _queue.post((_) => _onClaimFailed(job, error));
    }
  }

  void _onClaimed(ArrivalJob job, Outbox outbox, {required bool claimed}) {
    if (job.isDone) {
      return;
    }
    final isForSubscribers = _state.hasSubscribers && !job.arrival.isLaunch;
    if (claimed && job.isResolved) {
      job.isClaimed = true;
      _deliver(job, outbox);
    } else if (claimed && isForSubscribers) {
      job.isClaimed = true;
      _resolve(job);
    } else {
      _jobs.finish(job);
    }
  }

  void _onClaimFailed(ArrivalJob job, WarpLinkException error) {
    reportLedgerError(error);
    final tap = job.tap;
    if (tap != null) {
      _policy.settle(tap, failed: true);
    }
    _jobs.leave(job);
  }

  void _deliver(ArrivalJob job, Outbox outbox) {
    final answer = job.answer;
    if (answer != null) {
      _router.route(job.arrival.arrivalId, answer, _state, outbox);
    }
    _jobs.finish(job);
  }
}
