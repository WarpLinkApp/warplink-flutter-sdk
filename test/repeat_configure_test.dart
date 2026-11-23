import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

const String otherKey = 'wl_live_zyxwvutsrqponmlkjihgfedcba987654';

Map<String, Object?> deferredLink([String id = 'deferred']) =>
    linkMap(linkId: id)..['isDeferred'] = true;

/// Configure twice with the same key and options is one session.
///
/// Native Android and iOS 1.4.0 ignore a repeated configure and keep the check
/// that is running. Dart turns the native automatic check off and drives the
/// check itself, so it has to hold the same rule: no second native configure
/// and no second check while one is running. A different key or different
/// options still rebuilds the session. The retry of a finished check is in
/// `repeat_configure_retry_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUpNative((value) => native = value);
  setUp(() {
    native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => false;
    native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) => null;
  });

  int configures() => native.callsTo(WarpLinkMethod.configure).length;
  int checks() => native.callsTo(WarpLinkMethod.checkDeferredDeepLink).length;

  group('a repeated configure with the same key and options', () {
    test('configures native once and checks once', () async {
      await WarpLink.configure(apiKey: validKey, onLink: (_) {});
      await pump();
      await WarpLink.configure(apiKey: validKey, onLink: (_) {});
      await pump();
      expect(configures(), 1);
      expect(checks(), 1);
    });

    test(
      'keeps the check in flight and delivers it to the newer callback',
      () async {
        final answer = Completer<Object?>();
        native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
            answer.future;
        final first = <WarpLinkEvent>[];
        final second = <WarpLinkEvent>[];
        await WarpLink.configure(apiKey: validKey, onLink: first.add);
        await pump();
        await WarpLink.configure(apiKey: validKey, onLink: second.add);
        answer.complete(deferredLink());
        await pump();
        expect(checks(), 1);
        expect(first, isEmpty);
        expect(linkIds(second), ['deferred']);
      },
    );

    test('still runs the check an earlier configure switched off', () async {
      await WarpLink.configure(
        apiKey: validKey,
        automaticDeferredDeepLinks: false,
      );
      await pump();
      expect(checks(), 0);
      await WarpLink.configure(apiKey: validKey);
      await pump();
      expect(configures(), 1);
      expect(checks(), 1);
    });

    test(
      'shares one native configure while the first is still pending',
      () async {
        final nativeDone = Completer<Object?>();
        native.handlers[WarpLinkMethod.configure] = (_) => nativeDone.future;
        final first = WarpLink.configure(apiKey: validKey, onLink: (_) {});
        final second = WarpLink.configure(apiKey: validKey, onLink: (_) {});
        await pump();
        nativeDone.complete(null);
        await Future.wait(<Future<void>>[first, second]);
        expect(configures(), 1);
      },
    );
  });

  group('a configure that is not a repeat', () {
    test('rebuilds for a different key', () async {
      await WarpLink.configure(apiKey: validKey, onLink: (_) {});
      await pump();
      await WarpLink.configure(apiKey: otherKey, onLink: (_) {});
      await pump();
      expect(configures(), 2);
      expect(checks(), 2);
    });

    test('rebuilds for different options', () async {
      await WarpLink.configure(apiKey: validKey, onLink: (_) {});
      await pump();
      await WarpLink.configure(
        apiKey: validKey,
        debugLogging: true,
        onLink: (_) {},
      );
      await pump();
      expect(configures(), 2);
      expect(checks(), 2);
    });

    test('retries after native refused the first configure', () async {
      var calls = 0;
      native.handlers[WarpLinkMethod.configure] = (_) {
        calls++;
        if (calls == 1) {
          throw PlatformException(code: 'E_NETWORK_ERROR', message: 'no');
        }
        return null;
      };
      final events = <WarpLinkEvent>[];
      await WarpLink.configure(apiKey: validKey, onLink: events.add);
      await pump();
      await WarpLink.configure(apiKey: validKey, onLink: events.add);
      await pump();
      expect(configures(), 2);
      expect(checks(), 1);
    });
  });
}
