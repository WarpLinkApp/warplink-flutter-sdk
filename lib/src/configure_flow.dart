import 'dart:async';

import 'package:warplink_flutter/src/api_key.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/src/dispatch_config.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/events.dart';
import 'package:warplink_flutter/src/link_runtime.dart';
import 'package:warplink_flutter/src/tether/tether_enums.dart';

/// The body of `WarpLink.configure`: see its documentation.
///
/// Native is always configured with its own automatic dispatch off. Dart owns
/// the launch link and the deferred check, so one ledger decides delivery.
Future<void> configureSdk(
  LinkRuntime runtime, {
  required String apiKey,
  required String apiEndpoint,
  required bool debugLogging,
  required List<String> linkDomains,
  required bool automaticDeepLinks,
  required bool automaticDeferredDeepLinks,
  required TetherReadMode tetherReadMode,
  required WarpLinkListener? onLink,
}) async {
  if (!isValidApiKey(apiKey)) {
    reportInvalidApiKey(onLink);
    return;
  }
  final config = DispatchConfig(
    onLink: onLink,
    automaticDeepLinks: automaticDeepLinks,
    automaticDeferredDeepLinks: automaticDeferredDeepLinks,
    isTestKey: isTestApiKey(apiKey),
    apiKey: apiKey,
  );
  final previousKey = runtime.arrivals.config.apiKey;
  if (previousKey != null && previousKey != apiKey) {
    runtime.deferred.discard();
  }
  final arguments = <String, Object?>{
    'apiKey': apiKey,
    'apiEndpoint': apiEndpoint,
    'debugLogging': debugLogging,
    'linkDomains': List<String>.of(linkDomains),
    'automaticDeepLinks': false,
    'automaticDeferredDeepLinks': false,
    'tetherReadMode': tetherReadMode.wireValue,
  };
  // The same key and options again is the session already running: native is
  // not configured and no second session starts. `onLink` is replaced, and an
  // unfinished check gets one more chance.
  final isRepeat = runtime.nativeSession.isRepeat(arguments);
  if (!isRepeat) {
    runtime.deferred.startSession();
  }
  runtime.arrivals.begin(config);
  try {
    await runtime.nativeSession.configure(
      arguments,
      () => runtime.channel.invoke(WarpLinkMethod.configure, arguments),
    );
  } on WarpLinkException catch (error) {
    runtime.arrivals.markConfigured(config, ok: false);
    if (onLink == null) rethrow;
    if (runtime.arrivals.isCurrent(config)) onLink(ErrorEvent(error));
    return;
  }
  runtime.arrivals.markConfigured(config, ok: true);
  unawaited(runtime.dispatchAutomatic(config, repeat: isRepeat));
}
