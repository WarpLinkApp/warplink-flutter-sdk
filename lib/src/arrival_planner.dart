import 'dart:async';
import 'dart:collection';

import 'package:warplink_flutter/src/arrival_job.dart';
import 'package:warplink_flutter/src/dispatch_state.dart';
import 'package:warplink_flutter/src/event_queue.dart';
import 'package:warplink_flutter/src/link_classifier.dart';
import 'package:warplink_flutter/src/tap_policy.dart';

/// Decides, one arrival at a time and in admission order, what to do with it.
///
/// Planning is a lane: the head arrival is classified, admitted by the tap
/// policy, and handed on before the next one starts, so each decision sees the
/// state the previous arrival left. Resolving and claiming run unordered after
/// that, which is the case supersede exists for.
final class ArrivalPlanner {
  /// Creates a planner. It hands a planned job to [onPlanned] and a job nobody
  /// wants to [onUnwanted].
  ArrivalPlanner({
    required DispatchState state,
    required EventQueue queue,
    required LinkClassifier classifier,
    required TapPolicy policy,
    required void Function(ArrivalJob job) onPlanned,
    required void Function(ArrivalJob job) onUnwanted,
  }) : _state = state,
       _queue = queue,
       _classifier = classifier,
       _policy = policy,
       _onPlanned = onPlanned,
       _onUnwanted = onUnwanted;

  final DispatchState _state;
  final EventQueue _queue;
  final LinkClassifier _classifier;
  final TapPolicy _policy;
  final void Function(ArrivalJob job) _onPlanned;
  final void Function(ArrivalJob job) _onUnwanted;
  final Queue<ArrivalJob> _lane = Queue<ArrivalJob>();

  /// Adds [job] behind the arrivals already waiting.
  void add(ArrivalJob job) => _lane.add(job);

  /// Removes and returns every waiting job.
  List<ArrivalJob> clear() {
    final waiting = _lane.toList();
    _lane.clear();
    return waiting;
  }

  /// Plans the head of the lane while native `configure` has succeeded and
  /// the head needs no answer it is still waiting for.
  void pump() {
    while (_state.isConfigured && _lane.isNotEmpty) {
      final job = _lane.first;
      if (!_state.wants(job.arrival)) {
        _lane.removeFirst();
        _onUnwanted(job);
      } else if (job.isLink == null) {
        _classify(job);
        return;
      } else {
        _lane.removeFirst();
        _plan(job);
      }
    }
  }

  void _classify(ArrivalJob job) {
    if (job.isClassifying) {
      return;
    }
    job.isClassifying = true;
    unawaited(
      _classifier.isWarpLink(job.arrival.url).then((isLink) {
        _queue.post((_) {
          job.isLink = isLink;
          pump();
        });
      }),
    );
  }

  void _plan(ArrivalJob job) {
    final arrival = job.arrival;
    final subscribers = _state.hasSubscribers && !arrival.isLaunch;
    if (job.isLink == true) {
      job.tap = _policy.admit(
        arrival.url,
        at: arrival.arrivedAt,
        autoEnabled: _state.config.autoDeliversLinks,
        hasSubscribers: subscribers,
      );
      job.resolves = job.tap != null;
    } else {
      job.resolves = subscribers;
    }
    _onPlanned(job);
  }
}
