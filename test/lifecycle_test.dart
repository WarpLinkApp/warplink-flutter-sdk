import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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

  group('engine restart', () {
    test('replays a pending and a settled entry once each', () async {
      native.arrive('https://aplnk.to/pending', id: 'pending');
      native.arrive('https://aplnk.to/settled', id: 'settled').answer =
          Future<Object?>.value(linkMap(linkId: 'settled'));
      await configure();
      await pump();
      expect(linkIds(events), ['pending', 'settled']);
      expect(native.resolveStarts, ['https://aplnk.to/pending']);
      expect(native.claimed, ['pending', 'settled']);

      await WarpLink.resetForTesting();
      final restarted = <WarpLinkEvent>[];
      await configure(restarted);
      await pump();
      expect(restarted, isEmpty);
      expect(native.ledger, isEmpty);
    });

    test(
      'an entry a restarted engine cannot deliver stays in the ledger',
      () async {
        native.arrive('https://aplnk.to/one');
        await WarpLink.configure(apiKey: validKey);
        await pump();
        expect(native.ledger, hasLength(1));
        await configure();
        await pump();
        expect(linkIds(events), ['one']);
      },
    );

    test(
      'an engine that restarts mid-resolve joins the stored answer',
      () async {
        final gate = native.gates['https://aplnk.to/slow'] = Completer<void>();
        native.arrive('https://aplnk.to/slow');
        await configure();
        await pump();
        await WarpLink.resetForTesting();
        final restarted = <WarpLinkEvent>[];
        await configure(restarted);
        await pump();
        gate.complete();
        await pump();
        expect(linkIds([...events, ...restarted]), ['slow']);
        expect(native.claimed, hasLength(1));
        expect(native.resolveStarts, hasLength(1));
      },
    );
  });

  group('launch verdict', () {
    test('the cold start waits for a pre-warmed engine verdict', () async {
      native.pendingGate = Completer<void>();
      await configure();
      await pump();
      expect(events, isEmpty);
      native.arrive('https://aplnk.to/launch', isLaunch: true);
      native.pendingGate!.complete();
      await pump();
      expect(linkIds(events), ['launch']);
    });

    test(
      'getInitialDeepLink waits for the verdict instead of answering null',
      () async {
        native.pendingGate = Completer<void>();
        final pending = WarpLink.getInitialDeepLink();
        await pump();
        native.arrive('https://aplnk.to/launch', isLaunch: true);
        native.pendingGate!.complete();
        expect((await pending)!.linkId, 'launch');
      },
    );
  });

  group('generation', () {
    test('WL-S07 a reconfigure keeps the tap and delivers it once, to the '
        'newer callback', () async {
      final older = <WarpLinkEvent>[];
      final newer = <WarpLinkEvent>[];
      await configure(older);
      final gate = native.gates['https://aplnk.to/tap'] = Completer<void>();
      native.arrive('https://aplnk.to/tap');
      await pump();
      await configure(newer);
      await pump();
      gate.complete();
      await pump();
      expect(older, isEmpty);
      expect(linkIds(newer), ['tap']);
      expect(native.resolveStarts, hasLength(1));
      expect(native.claimed, hasLength(1));
    });

    test('an answer that lands between the configures is adopted', () async {
      final older = <WarpLinkEvent>[];
      final newer = <WarpLinkEvent>[];
      await configure(older);
      final gate = native.gates['https://aplnk.to/tap'] = Completer<void>();
      native.arrive('https://aplnk.to/tap');
      await pump();
      final secondConfigure = Completer<Object?>();
      native.handlers['configure'] = (_) => secondConfigure.future;
      final done = configure(newer);
      await pump();
      gate.complete();
      await pump();
      expect(older, isEmpty);
      expect(native.ledger, hasLength(1));
      secondConfigure.complete(null);
      await done;
      await pump();
      expect(linkIds(newer), ['tap']);
      expect(native.resolveStarts, hasLength(1));
      expect(native.ledger, isEmpty);
    });

    test('a new configuration forgets the old dedupe window', () async {
      await configure();
      native.arrive('https://aplnk.to/same');
      await pump();
      final newer = <WarpLinkEvent>[];
      await configure(newer);
      native.arrive('https://aplnk.to/same');
      await pump();
      expect(linkIds(newer), ['same']);
    });
  });

  group('disposal', () {
    test(
      'a claim in flight at disposal loses that one delivery, silently',
      () async {
        final reported = captureReportedErrors();
        final gate = native.claimGates['one'] = Completer<void>();
        await configure();
        native.arrive('https://aplnk.to/one', id: 'one');
        await pump();
        await WarpLink.resetForTesting();
        gate.complete();
        await pump();
        final restarted = <WarpLinkEvent>[];
        await configure(restarted);
        await pump();
        expect(events, isEmpty);
        expect(restarted, isEmpty);
        expect(native.claimed, ['one']);
        expect(reported, isEmpty);
      },
    );
  });

  group('malformed announcements', () {
    test('are reported and never stop later arrivals', () async {
      final reported = captureReportedErrors();
      await configure();
      native.arrivalsSink!.success(<String, Object?>{'url': 'no id'});
      await pump();
      native.arrive('https://aplnk.to/after');
      await pump();
      expect(reported.single.exception, isA<WarpLinkDecodingException>());
      expect(linkIds(events), ['after']);
    });
  });
}
