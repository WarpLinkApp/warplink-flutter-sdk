import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;
  late List<WarpLinkEvent> events;

  setUpNative((value) => native = value);
  setUp(() => events = <WarpLinkEvent>[]);

  Future<void> configure([List<WarpLinkEvent>? into]) =>
      WarpLink.configure(apiKey: validKey, onLink: (into ?? events).add);

  group('handshake', () {
    test('the ledger is requested only after native signals ready', () async {
      native.readyOnListen = false;
      native.arrive('https://aplnk.to/one');
      await configure();
      await pump();
      expect(native.arrivalsListens, 1);
      expect(native.callsTo(WarpLinkMethod.getPendingArrivals), isEmpty);
      native.sendReady();
      await pump();
      expect(native.callsTo(WarpLinkMethod.getPendingArrivals), hasLength(1));
      expect(linkIds(events), ['one']);
    });

    test('an arrival and the replay of it deliver once', () async {
      native.pendingGate = Completer<void>();
      native.arrive('https://aplnk.to/one', id: 'x');
      await configure();
      await pump();
      native.arrive('https://aplnk.to/one', id: 'x');
      native.pendingGate!.complete();
      await pump();
      expect(linkIds(events), ['one']);
      expect(native.resolveStarts, hasLength(1));
    });
  });

  group('order and timing come from native', () {
    test(
      'a replay that lands after a newer announcement keeps tap order',
      () async {
        native.pendingGate = Completer<void>();
        native.arrive('https://aplnk.to/older', id: 'older');
        await configure();
        await pump();
        native.arrive('https://aplnk.to/newer', id: 'newer');
        await pump();
        native.pendingGate!.complete();
        await pump();
        expect(linkIds(events), ['older', 'newer']);
        expect(native.resolveStarts, [
          'https://aplnk.to/older',
          'https://aplnk.to/newer',
        ]);
      },
    );

    test('a late replay keeps the native gap between two taps', () async {
      native.pendingGate = Completer<void>();
      native.arrive('https://aplnk.to/same', atMs: 100);
      native.arrive('https://aplnk.to/same', atMs: 2100);
      await configure();
      await pump();
      native.pendingGate!.complete();
      await pump();
      expect(linkIds(events), ['same', 'same']);
    });

    test(
      'a late replay keeps two taps inside the window as a repeat',
      () async {
        native.pendingGate = Completer<void>();
        native.arrive('https://aplnk.to/same', atMs: 100);
        native.arrive('https://aplnk.to/same', atMs: 600);
        await configure();
        await pump();
        native.advanceClock(const Duration(seconds: 30));
        native.pendingGate!.complete();
        await pump();
        expect(linkIds(events), ['same']);
      },
    );

    test('an arrival without a sequence number is a decoding error', () async {
      final reported = captureReportedErrors();
      await configure();
      await pump();
      native.arrivalsSink!.success(<String, Object?>{
        'arrivalId': 'x',
        'url': 'https://aplnk.to/one',
        'arrivedAtMs': 0,
      });
      await pump();
      expect(reported.single.exception, isA<WarpLinkDecodingException>());
      expect(events, isEmpty);
    });
  });

  group('delivery claim', () {
    test(
      'a failed claim delivers nothing and the next replay retries it',
      () async {
        var failures = 1;
        native.handlers[WarpLinkMethod.claimDelivery] = (args) {
          if (failures-- > 0) {
            throw PlatformException(code: 'E_SERVER_ERROR', message: 'busy');
          }
          return native.entries.single.delivered = true;
        };
        final reported = captureReportedErrors();
        native.arrive('https://aplnk.to/one', id: 'x');
        await configure();
        await pump();
        expect(events, isEmpty);
        expect(native.ledger, hasLength(1));
        expect(reported, hasLength(1));
        final later = <WarpLinkEvent>[];
        await configure(later);
        await pump();
        expect(linkIds(later), ['one']);
        expect(native.ledger, isEmpty);
        expect(events, isEmpty);
        expect(native.resolveStarts, hasLength(1));
      },
    );

    test('a hot restart does not deliver an arrival again', () async {
      native.arrive('https://aplnk.to/one', id: 'x');
      await configure();
      await pump();
      await WarpLink.resetForTesting();
      final restarted = <WarpLinkEvent>[];
      await configure(restarted);
      await pump();
      expect(linkIds(events), ['one']);
      expect(restarted, isEmpty);
      expect(native.claimed, ['x']);
    });

    test('a claim another engine won delivers nothing', () async {
      native.arrive('https://aplnk.to/one', id: 'x');
      native.handlers[WarpLinkMethod.claimDelivery] = (_) => false;
      await configure();
      await pump();
      expect(events, isEmpty);
    });

    test(
      'a failed claim of the launch link throws and a retry succeeds',
      () async {
        native.arrive('https://aplnk.to/launch', id: 'l', isLaunch: true);
        await WarpLink.configure(apiKey: validKey);
        var failures = 1;
        native.handlers[WarpLinkMethod.claimDelivery] = (args) {
          if (failures-- > 0) {
            throw PlatformException(code: 'E_SERVER_ERROR', message: 'busy');
          }
          return native.entries.single.delivered = true;
        };
        await expectLater(
          WarpLink.getInitialDeepLink(),
          throwsA(isA<WarpLinkServerException>()),
        );
        expect((await WarpLink.getInitialDeepLink())!.linkId, 'launch');
        expect(await WarpLink.getInitialDeepLink(), isNull);
      },
    );

    test(
      'a launch link another engine delivered is not offered again',
      () async {
        native.arrive('https://aplnk.to/launch', id: 'l', isLaunch: true);
        native.entries.single.delivered = true;
        await WarpLink.configure(apiKey: validKey);
        expect(await WarpLink.getInitialDeepLink(), isNull);
      },
    );
  });
}
