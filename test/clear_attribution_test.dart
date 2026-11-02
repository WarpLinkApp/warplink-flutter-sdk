import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

const String testKey = 'wl_test_abcdefghijklmnopqrstuvwxyz012345';
const String liveKey = 'wl_live_abcdefghijklmnopqrstuvwxyz012345';

Map<String, Object?> deferredLink(String id) =>
    linkMap(linkId: id)..['isDeferred'] = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;
  late List<WarpLinkEvent> events;

  setUpNative((value) => native = value);
  setUp(() {
    events = <WarpLinkEvent>[];
    native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => false;
    native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) => null;
    native.handlers[WarpLinkMethod.clearAttribution] = (_) => null;
  });

  Future<void> configure(
    String apiKey, {
    bool automaticDeferredDeepLinks = true,
  }) => WarpLink.configure(
    apiKey: apiKey,
    automaticDeferredDeepLinks: automaticDeferredDeepLinks,
    onLink: events.add,
  );

  int checks() => native.callsTo(WarpLinkMethod.checkDeferredDeepLink).length;
  int clears() => native.callsTo(WarpLinkMethod.clearAttribution).length;

  group('clearAttribution', () {
    test('WL-S50 forwards the reset to native and completes', () async {
      await configure(testKey);
      await pump();

      await WarpLink.clearAttribution();

      expect(clears(), 1);
    });

    test('WL-S50 a live key reset starts no new deferred check', () async {
      await configure(validKey);
      await pump();
      final before = checks();

      await WarpLink.clearAttribution();
      await pump();

      expect(clears(), 1);
      expect(checks(), before);
    });

    test('WL-S50 a live key reset keeps a check in flight', () async {
      final gate = Completer<Object?>();
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          gate.future;
      await configure(validKey);
      await pump();

      await WarpLink.clearAttribution();
      gate.complete(deferredLink('kept'));
      await pump();

      expect(linkIds(events), ['kept']);
    });

    test('WL-S50 a refusal before configure reaches the caller', () async {
      native.handlers[WarpLinkMethod.clearAttribution] = (_) =>
          throw PlatformException(code: 'E_NOT_CONFIGURED', message: 'no');

      await expectLater(
        WarpLink.clearAttribution(),
        throwsA(isA<WarpLinkNotConfiguredException>()),
      );
    });

    test('WL-S51 a Test reset starts a fresh check and delivers it', () async {
      await configure(testKey);
      await pump();
      expect(checks(), 1);
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          deferredLink('fresh');

      await WarpLink.clearAttribution();
      await pump();

      expect(checks(), 2);
      expect(linkIds(events), ['fresh']);
    });

    test('WL-S51 a Test reset discards the check in flight', () async {
      final stale = Completer<Object?>();
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          stale.future;
      await configure(testKey);
      await pump();
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          deferredLink('fresh');

      await WarpLink.clearAttribution();
      await pump();
      stale.complete(deferredLink('stale'));
      await pump();

      expect(linkIds(events), ['fresh']);
    });

    test(
      'WL-S51 a reset while the completion status is pending starts no check',
      () async {
        final status = Completer<Object?>();
        native.handlers[WarpLinkMethod.isAttributionComplete] = (_) =>
            status.future;
        await configure(testKey);
        await pump();
        native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => true;

        await WarpLink.clearAttribution();
        status.complete(false);
        await pump();

        expect(checks(), 0);
        expect(events, isEmpty);
      },
    );

    test(
      'WL-S51 a key change while the completion status is pending starts no check',
      () async {
        final status = Completer<Object?>();
        native.handlers[WarpLinkMethod.isAttributionComplete] = (_) =>
            status.future;
        await configure(testKey);
        await pump();
        native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => true;

        await configure(liveKey);
        status.complete(false);
        await pump();

        expect(checks(), 0);
        expect(events, isEmpty);
      },
    );

    test(
      'WL-S51 a change between two Test keys while the status is pending starts no check',
      () async {
        final status = Completer<Object?>();
        native.handlers[WarpLinkMethod.isAttributionComplete] = (_) =>
            status.future;
        await configure(testKey);
        await pump();
        native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => true;

        await configure('wl_test_zyxwvutsrqponmlkjihgfedcba987654');
        status.complete(false);
        await pump();

        expect(checks(), 0);
        expect(events, isEmpty);
      },
    );

    test(
      'WL-S51 a Test reset with the automatic check off starts none',
      () async {
        await configure(testKey, automaticDeferredDeepLinks: false);
        await pump();

        await WarpLink.clearAttribution();
        await pump();

        expect(clears(), 1);
        expect(checks(), 0);
      },
    );

    test('WL-S52 a storage failure throws WarpLinkDecodingException', () async {
      native.handlers[WarpLinkMethod.clearAttribution] = (_) =>
          throw PlatformException(
            code: 'E_DECODING_ERROR',
            message: 'Could not clear stored attribution data.',
          );
      await configure(testKey);
      await pump();

      await expectLater(
        WarpLink.clearAttribution(),
        throwsA(
          isA<WarpLinkDecodingException>().having(
            (error) => error.message,
            'message',
            'Could not clear stored attribution data.',
          ),
        ),
      );
    });

    test('WL-S52 a failed reset still lets the next call succeed', () async {
      var attempts = 0;
      native.handlers[WarpLinkMethod.clearAttribution] = (_) {
        attempts++;
        if (attempts == 1) {
          throw PlatformException(
            code: 'E_DECODING_ERROR',
            message: 'Could not clear stored attribution data.',
          );
        }
        return null;
      };
      await configure(testKey);
      await pump();

      await expectLater(
        WarpLink.clearAttribution(),
        throwsA(isA<WarpLinkDecodingException>()),
      );
      await WarpLink.clearAttribution();

      expect(clears(), 2);
    });
  });
}
