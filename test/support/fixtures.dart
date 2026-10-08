import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'fake_native.dart';

/// A native deep link map with every field set.
Map<String, Object?> linkMap({
  String linkId = 'link-1',
  String destination = 'https://example.com/a',
  Object? matchGuaranteed = true,
}) => <String, Object?>{
  'linkId': linkId,
  'destination': destination,
  'deepLinkUrl': 'myapp://a',
  'customParams': <Object?, Object?>{
    'plan': 'pro',
    'nested': <Object?, Object?>{
      'tags': <Object?>['a', 1, 2.5, null, true],
    },
  },
  'isDeferred': false,
  'matchType': 'deterministic',
  'matchConfidence': 1,
  'matchGuaranteed': ?matchGuaranteed,
};

const String validKey = 'wl_live_abcdefghijklmnopqrstuvwxyz012345';

/// Lets queued platform messages and stream events settle.
Future<void> pump() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Collects what the SDK reports through `FlutterError.onError` until the
/// test ends.
List<FlutterErrorDetails> captureReportedErrors() {
  final reported = <FlutterErrorDetails>[];
  final original = FlutterError.onError;
  FlutterError.onError = reported.add;
  addTearDown(() => FlutterError.onError = original);
  return reported;
}

/// The link ids a list of events carries, in order.
List<String> linkIds(List<WarpLinkEvent> events) =>
    events.map((event) => (event as LinkEvent).deepLink.linkId).toList();

/// Installs a [FakeNative] before each test and removes it after.
///
/// A successful `configure` and a complete attribution are scripted by
/// default. [assign] receives the fresh fake so the test file can keep it in a
/// `late` variable.
void setUpNative(void Function(FakeNative native) assign) {
  late FakeNative current;
  setUp(() async {
    current = FakeNative();
    assign(current);
    await WarpLink.resetForTesting();
  });
  tearDown(() async {
    await WarpLink.resetForTesting();
    current.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
