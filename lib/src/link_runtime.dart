import 'package:warplink_flutter/src/arrival_coordinator.dart';
import 'package:warplink_flutter/src/arrival_jobs.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/src/channel_adapter.dart';
import 'package:warplink_flutter/src/deferred_coordinator.dart';
import 'package:warplink_flutter/src/dispatch_config.dart';
import 'package:warplink_flutter/src/deep_link.dart';
import 'package:warplink_flutter/src/dispatch_state.dart';
import 'package:warplink_flutter/src/event_queue.dart';
import 'package:warplink_flutter/src/events.dart';
import 'package:warplink_flutter/src/link_classifier.dart';
import 'package:warplink_flutter/src/link_dispatcher.dart';
import 'package:warplink_flutter/src/manual_resolver.dart';
import 'package:warplink_flutter/src/native_session.dart';
import 'package:warplink_flutter/src/resolution_registry.dart';
import 'package:warplink_flutter/src/tap_policy.dart';
import 'package:warplink_flutter/src/tether/tether_route.dart';

/// The object graph behind the `WarpLink` facade.
///
/// One instance per engine and per test. It holds no logic of its own.
final class LinkRuntime {
  /// Builds the graph over [channel]. [now] is the clock of the repeat limit.
  factory LinkRuntime(
    WarpLinkChannel channel, {
    DateTime Function() now = DateTime.now,
  }) {
    final adapter = ChannelAdapter(channel);
    final policy = TapPolicy();
    late final ArrivalCoordinator arrivals;
    final classifier = LinkClassifier(adapter);
    final registry = ResolutionRegistry(adapter);
    final queue = EventQueue();
    final dispatcher = LinkDispatcher(
      state: DispatchState(),
      queue: queue,
      adapter: adapter,
      classifier: classifier,
      policy: policy,
      registry: registry,
      jobs: ArrivalJobs(registry),
      emit: (event) => arrivals.emit(event),
    );
    final manual = ManualResolver(
      adapter: adapter,
      classifier: classifier,
      policy: policy,
      registry: registry,
    );
    arrivals = ArrivalCoordinator(
      adapter: adapter,
      dispatcher: dispatcher,
      queue: queue,
      manual: manual,
    );
    final deferred = DeferredCoordinator(adapter, now: now);
    bindTetherRoute(deferred);
    return LinkRuntime._(channel, arrivals, manual, deferred);
  }

  LinkRuntime._(this.channel, this.arrivals, this.manual, this.deferred);

  /// The native configuration this runtime asked for last.
  final NativeSession nativeSession = NativeSession();

  /// The raw channel, for calls that carry no dispatch.
  final WarpLinkChannel channel;

  /// Admission of arrivals.
  final ArrivalCoordinator arrivals;

  /// Manual resolves, outside the automatic path.
  final ManualResolver manual;

  /// The automatic deferred check.
  final DeferredCoordinator deferred;

  /// The launch link, once: its deep link, `null` for none, or its error thrown.
  Future<WarpLinkDeepLink?> takeInitialLink() async =>
      switch (await arrivals.takeInitial()) {
        LinkEvent(:final deepLink) => deepLink,
        ErrorEvent(:final error) => throw error,
        null => null,
      };

  /// Runs what follows a successful native configure for [config]: the launch
  /// link first, then the deferred check.
  ///
  /// The deferred check runs even when the host's callback threw for the launch
  /// link, because that request is what attributes the install.
  ///
  /// A [repeat] is a configure of the session already live: it asks the
  /// deferred check for one more chance.
  Future<void> dispatchAutomatic(
    DispatchConfig config, {
    bool repeat = false,
  }) async {
    try {
      await arrivals.coldDispatch();
    } finally {
      if (config.automaticDeferredDeepLinks && arrivals.isCurrent(config)) {
        await deferred.run(
          isCurrent: () => arrivals.isCurrent(config),
          deliver: config.onLink,
          retry: repeat,
        );
      }
    }
  }
}
