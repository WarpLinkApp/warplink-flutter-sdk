import 'dart:async';

import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/src/link_runtime.dart';

/// The body of `WarpLink.clearAttribution`.
///
/// Only a Test session discards the deferred check in flight and starts a
/// fresh one. With a live key the native call is a no-op, and dropping a live
/// match that is about to be delivered would lose a real attribution.
Future<void> clearAttributionOf(LinkRuntime runtime) async {
  final config = runtime.arrivals.config;
  final isTest = config.isTestKey;
  if (isTest) {
    runtime.deferred.discard();
  }
  await runtime.channel.invoke(WarpLinkMethod.clearAttribution);
  if (isTest &&
      config.automaticDeferredDeepLinks &&
      runtime.arrivals.isCurrent(config)) {
    unawaited(
      runtime.deferred.run(
        isCurrent: () => runtime.arrivals.isCurrent(config),
        deliver: config.onLink,
      ),
    );
  }
}
