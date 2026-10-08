import 'package:warplink_flutter/src/answer_router.dart';
import 'package:warplink_flutter/src/arrival.dart';
import 'package:warplink_flutter/src/arrival_delivery.dart';
import 'package:warplink_flutter/src/arrival_jobs.dart';
import 'package:warplink_flutter/src/arrival_planner.dart';
import 'package:warplink_flutter/src/channel_adapter.dart';
import 'package:warplink_flutter/src/dispatch_config.dart';
import 'package:warplink_flutter/src/dispatch_state.dart';
import 'package:warplink_flutter/src/event_queue.dart';
import 'package:warplink_flutter/src/events.dart';
import 'package:warplink_flutter/src/link_classifier.dart';
import 'package:warplink_flutter/src/resolution_registry.dart';
import 'package:warplink_flutter/src/tap_policy.dart';

/// The dispatch actor: one handler per input, none waiting.
///
/// Every public method is a handler body that [EventQueue] runs alone. A
/// native call starts from a handler and its answer returns as a new event.
/// Recipients are read from [DispatchState] only inside handlers: a claim is
/// issued only when someone could take the answer, and the answer goes to
/// whoever exists when native confirmed the claim.
final class LinkDispatcher {
  /// Creates a dispatcher. Subscribers receive answers through [emit].
  LinkDispatcher({
    required this.state,
    required EventQueue queue,
    required ChannelAdapter adapter,
    required LinkClassifier classifier,
    required TapPolicy policy,
    required ResolutionRegistry registry,
    required this.jobs,
    required void Function(WarpLinkEvent event) emit,
  }) : _queue = queue,
       _policy = policy,
       _router = AnswerRouter(emit) {
    _delivery = ArrivalDelivery(
      state: state,
      queue: queue,
      adapter: adapter,
      policy: policy,
      registry: registry,
      jobs: jobs,
      router: _router,
    );
    _planner = ArrivalPlanner(
      state: state,
      queue: queue,
      classifier: classifier,
      policy: policy,
      onPlanned: _delivery.start,
      onUnwanted: jobs.leave,
    );
  }

  /// The recipients' state.
  final DispatchState state;

  /// The live jobs.
  final ArrivalJobs jobs;

  final EventQueue _queue;
  final TapPolicy _policy;
  final AnswerRouter _router;
  late final ArrivalDelivery _delivery;
  late final ArrivalPlanner _planner;
  bool _isFlushQueued = false;

  /// Applies a new configuration. Arrivals wait for [configured].
  void begin(DispatchConfig config) {
    state
      ..config = config
      ..isConfigured = false;
    _policy.reset();
  }

  /// Applies the outcome of native `configure` for [config].
  ///
  /// After a failure the waiting arrivals stay in the ledger.
  void configured(DispatchConfig config, Outbox outbox, {required bool ok}) {
    if (!identical(config, state.config)) {
      return;
    }
    state.isConfigured = ok;
    _delivery.resume(ok: ok);
    if (ok) {
      _planner.pump();
      _scheduleFlush(outbox);
    } else {
      _planner.clear().forEach(jobs.leave);
    }
  }

  /// Applies that the subscriber set became non-empty or empty.
  void subscribersChanged(Outbox outbox, {required bool present}) {
    state.hasSubscribers = present;
    if (present) {
      _planner.pump();
      _scheduleFlush(outbox);
    }
  }

  /// Admits [arrival] unless it is live, finished, or taken.
  void arrived(Arrival arrival) {
    final job = jobs.admit(arrival);
    if (job != null) {
      _planner.add(job);
      _planner.pump();
    }
  }

  /// Gives one held answer to a recipient and schedules the next.
  void flushHeld(Outbox outbox) {
    _isFlushQueued = false;
    if (_router.flushOne(state, outbox)) {
      _scheduleFlush(outbox);
    }
  }

  /// Removes and returns the held launch answer `getInitialDeepLink` may take.
  WarpLinkEvent? takeHeldLaunch() => _router.takeLaunch();

  /// Queues the next flush unless one is already queued, so a single chain
  /// delivers one answer per event.
  void _scheduleFlush(Outbox outbox) {
    if (_isFlushQueued) {
      return;
    }
    _isFlushQueued = true;
    outbox.add(() => _queue.post(flushHeld));
  }
}
