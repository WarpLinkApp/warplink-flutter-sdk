import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

const String testKey = 'wl_test_abcdefghijklmnopqrstuvwxyz012345';
const Duration minute = Duration(minutes: 1);

Map<String, Object?> deferredLink([String id = 'deferred']) =>
    linkMap(linkId: id)..['isDeferred'] = true;

PlatformException offline() =>
    PlatformException(code: 'E_NETWORK_ERROR', message: 'offline');

/// A same-key repeat asks native at most once a minute per process, and a
/// repeat never asks for a check that is already running.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;
  var now = DateTime.utc(2026, 11, 22);

  setUpNative((value) => native = value);
  setUp(() async {
    now = DateTime.utc(2026, 11, 22);
    await WarpLink.resetForTesting(null, () => now);
    native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => false;
    native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) => null;
    native.handlers[WarpLinkMethod.getDeferredCheckStatus] = (_) =>
        <String, Object?>{'state': 'notChecked'};
  });

  int configures() => native.callsTo(WarpLinkMethod.configure).length;
  int checks() => native.callsTo(WarpLinkMethod.checkDeferredDeepLink).length;

  Future<void> configure([String apiKey = validKey]) async {
    await WarpLink.configure(apiKey: apiKey, onLink: (_) {});
    await pump();
  }

  group('the once-a-minute limit on repeats', () {
    test(
      'asks on the first repeat and holds back one inside the minute',
      () async {
        await configure();
        await configure();
        now = now.add(minute - const Duration(milliseconds: 1));
        await configure();

        expect(configures(), 1);
        expect(checks(), 2);
      },
    );

    test('asks again once a minute has passed', () async {
      await configure();
      await configure();
      now = now.add(minute);
      await configure();

      expect(checks(), 3);
    });

    test('limits a wl_test_ key too', () async {
      await configure(testKey);
      await configure(testKey);
      await configure(testKey);

      expect(configures(), 1);
      expect(checks(), 2);
    });

    test(
      'counts the minute from the last request, not the last status read',
      () async {
        await configure();
        native.handlers[WarpLinkMethod.getDeferredCheckStatus] = (_) =>
            <String, Object?>{'state': 'checking'};
        await configure();
        native.handlers[WarpLinkMethod.getDeferredCheckStatus] = (_) =>
            <String, Object?>{'state': 'notChecked'};
        await configure();

        expect(checks(), 2);
      },
    );

    test('treats a clock that moved backwards as a new minute', () async {
      await configure();
      await configure();
      now = now.subtract(minute);
      await configure();

      expect(checks(), 3);
    });
  });

  group('a repeat after a first run that had no onLink', () {
    test('joins the check the first run started', () async {
      final answer = Completer<Object?>();
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          answer.future;
      final events = <WarpLinkEvent>[];

      await WarpLink.configure(apiKey: validKey, automaticDeepLinks: false);
      await pump();
      await WarpLink.configure(
        apiKey: validKey,
        automaticDeepLinks: false,
        onLink: events.add,
      );
      await pump();
      answer.complete(deferredLink());
      await pump();

      expect(configures(), 1);
      expect(checks(), 1);
      expect(linkIds(events), ['deferred']);
    });
  });

  group('the earlier repeat fixes still hold', () {
    test(
      'a failed first check gets one error, and a repeat asks once',
      () async {
        native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
            throw offline();
        final first = <WarpLinkEvent>[];
        final second = <WarpLinkEvent>[];

        await WarpLink.configure(apiKey: validKey, onLink: first.add);
        await pump();
        native.handlers[WarpLinkMethod.getDeferredCheckStatus] = (_) =>
            <String, Object?>{
              'state': 'waiting',
              'retryAt': now.millisecondsSinceEpoch,
            };
        native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) => null;
        await WarpLink.configure(apiKey: validKey, onLink: second.add);
        await pump();

        expect(first.whereType<ErrorEvent>(), hasLength(1));
        expect(second, isEmpty);
        expect(checks(), 2);
        expect(configures(), 1);
      },
    );

    test('a failed native configure lets the next call retry', () async {
      var calls = 0;
      native.handlers[WarpLinkMethod.configure] = (_) {
        if (++calls == 1) throw offline();
        return null;
      };
      final events = <WarpLinkEvent>[];

      await WarpLink.configure(apiKey: validKey, onLink: events.add);
      await pump();
      await WarpLink.configure(apiKey: validKey, onLink: events.add);
      await pump();

      expect(configures(), 2);
      expect(events.whereType<ErrorEvent>(), hasLength(1));
      expect(native.callsTo(WarpLinkMethod.getDeferredCheckStatus), isEmpty);
    });

    test('a failed native configure without onLink throws', () async {
      native.handlers[WarpLinkMethod.configure] = (_) => throw offline();

      await expectLater(
        WarpLink.configure(apiKey: validKey),
        throwsA(isA<WarpLinkException>()),
      );
    });
  });
}
