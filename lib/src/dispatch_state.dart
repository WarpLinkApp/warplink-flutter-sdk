import 'package:warplink_flutter/src/arrival.dart';
import 'package:warplink_flutter/src/dispatch_config.dart';
import 'package:warplink_flutter/src/events.dart';

/// What dispatch knows about its recipients, as of the last handled event.
///
/// Only handlers write it, and only handlers read it to decide. A host
/// action changes it through an event, so no decision ever sees it mid-change.
final class DispatchState {
  /// The newest configuration.
  DispatchConfig config = DispatchConfig.none;

  /// Whether native `configure` succeeded for [config].
  bool isConfigured = false;

  /// Whether an `onDeepLink` subscriber is attached.
  bool hasSubscribers = false;

  /// The `onLink` callback, when the automatic path is on and native
  /// `configure` succeeded.
  WarpLinkListener? get automaticSink =>
      isConfigured && config.autoDeliversLinks ? config.onLink : null;

  /// Whether the native listener has a reason to run.
  bool get wantsArrivals => config.autoDeliversLinks || hasSubscribers;

  /// Whether some recipient could take the answer of [arrival].
  ///
  /// The launch arrival belongs to the automatic path alone.
  bool wants(Arrival arrival) =>
      automaticSink != null || (hasSubscribers && !arrival.isLaunch);
}
