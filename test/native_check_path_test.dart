import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

/// The traffic rules of SDK 1.4.0 (install age, backoff, foreground wait, give
/// up) sit in the native check path. The plugin turns the native automatic
/// check off and drives the check by hand, so it inherits those rules only
/// while every deferred check goes through the native `checkDeferredDeepLink`,
/// once, with no gate, retry or request of its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUpNative((value) => native = value);
  setUp(() {
    native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => false;
  });

  int checks() => native.callsTo(WarpLinkMethod.checkDeferredDeepLink).length;

  test(
    'a failure is left to the native backoff: one call, no retry here',
    () async {
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          throw PlatformException(code: 'E_NETWORK_ERROR', message: 'offline');
      final events = <WarpLinkEvent>[];

      await WarpLink.configure(apiKey: validKey, onLink: events.add);
      await pump();

      expect(checks(), 1);
      expect(events.single, isA<ErrorEvent>());
    },
  );

  test(
    'the answer native gives inside a wait, no match, delivers nothing',
    () async {
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) => null;
      final events = <WarpLinkEvent>[];

      await WarpLink.configure(apiKey: validKey, onLink: events.add);
      await pump();

      expect(checks(), 1);
      expect(events, isEmpty);
    },
  );

  test('Dart sends no request and keeps no timer of its own', () {
    final dart = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(dart, isNot(contains('HttpClient')));
    expect(dart, isNot(contains('package:http')));
    expect(dart, isNot(contains('Future.delayed')));
  });

  test(
    'both native plugins turn the automatic check off and call the shared one',
    () {
      String read(String path) => File(path).readAsStringSync();

      expect(
        read(
          'android/src/main/kotlin/app/warplink/flutter/AndroidNativeSdk.kt',
        ),
        contains('automaticDeferredDeepLinks = false'),
      );
      expect(
        read(
          'android/src/main/kotlin/app/warplink/flutter/AndroidNativeSdk.kt',
        ),
        contains('WarpLink.checkDeferredDeepLink'),
      );
      expect(
        read(
          'ios/warplink_flutter/Sources/warplink_flutter/ConfigureRequest.swift',
        ),
        contains('autoDeferredCheck: false'),
      );
      expect(
        read(
          'ios/warplink_flutter/Sources/warplink_flutter/LiveWarpLinkNative.swift',
        ),
        contains('WarpLink.checkDeferredDeepLink('),
      );
    },
  );
}
