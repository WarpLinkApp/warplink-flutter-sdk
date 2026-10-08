import 'dart:async';

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

  Future<void> configure({
    bool automaticDeepLinks = true,
    List<String> linkDomains = const <String>[],
  }) => WarpLink.configure(
    apiKey: validKey,
    automaticDeepLinks: automaticDeepLinks,
    linkDomains: linkDomains,
    onLink: events.add,
  );

  Completer<void> hold(String url) => native.gates[url] = Completer<void>();

  group('automatic dispatch', () {
    test('WL-S01 a cold start delivers exactly one event', () async {
      native.arrive('https://aplnk.to/launch', id: 'launch', isLaunch: true);
      await configure();
      await pump();
      native.arrive('https://aplnk.to/launch', id: 'launch', isLaunch: true);
      await pump();
      expect(linkIds(events), ['launch']);
      expect(native.resolveStarts, ['https://aplnk.to/launch']);
      expect(native.claimed, ['launch']);
    });

    test('WL-S02 a warm start delivers one more event', () async {
      native.arrive('https://aplnk.to/launch', isLaunch: true);
      await configure();
      await pump();
      native.arrive('https://aplnk.to/warm');
      await pump();
      expect(linkIds(events), ['launch', 'warm']);
    });

    test('WL-S14 automatic deep links default to on', () async {
      await WarpLink.configure(apiKey: validKey, onLink: events.add);
      native.arrive('https://aplnk.to/warm');
      await pump();
      expect(linkIds(events), ['warm']);
    });

    test(
      'WL-S19 opting out stops the cold start and every warm arrival',
      () async {
        native.arrive('https://aplnk.to/launch', id: 'launch', isLaunch: true);
        await configure(automaticDeepLinks: false);
        native.arrive('https://aplnk.to/warm');
        await pump();
        expect(events, isEmpty);
        expect(native.resolveStarts, isEmpty);
        expect(native.arrivalsListens, 0);
        expect(native.ledger, hasLength(2));
        final manual = await WarpLink.handleDeepLink('https://aplnk.to/warm');
        expect(manual!.linkId, 'warm');
        expect((await WarpLink.getInitialDeepLink())!.linkId, 'launch');
      },
    );

    test('without onLink an arrival stays in the ledger', () async {
      await WarpLink.configure(apiKey: validKey);
      native.arrive('https://aplnk.to/warm');
      await pump();
      expect(native.resolveStarts, isEmpty);
      expect(native.ledger, hasLength(1));
    });

    test(
      'a custom domain from linkDomains resolves on the first launch',
      () async {
        native.isWarpLink = (url) => Uri.parse(url).host == 'links.example.com';
        native.arrive('https://links.example.com/promo', isLaunch: true);
        await configure(linkDomains: const ['links.example.com']);
        await pump();
        expect(linkIds(events), ['promo']);
        expect(native.argumentsOf('configure')['linkDomains'], [
          'links.example.com',
        ]);
      },
    );
  });

  group('one resolve for every feed', () {
    test('both feeds share one native call', () async {
      await configure();
      final streamed = <WarpLinkEvent>[];
      final sub = WarpLink.onDeepLink.listen(streamed.add);
      await pump();
      native.arrive('https://aplnk.to/shared');
      await pump();
      expect(linkIds(events), ['shared']);
      expect(linkIds(streamed), ['shared']);
      expect(native.resolveStarts, hasLength(1));
      await sub.cancel();
    });

    test('a duplicate announcement of one arrival joins the first', () async {
      await configure();
      final gate = hold('https://aplnk.to/once');
      native.arrive('https://aplnk.to/once', id: 'x');
      native.arrive('https://aplnk.to/once', id: 'x');
      await pump();
      gate.complete();
      await pump();
      native.arrive('https://aplnk.to/once', id: 'x');
      await pump();
      expect(linkIds(events), ['once']);
      expect(native.resolveStarts, hasLength(1));
    });

    test('WL-S03 a distinct arrival of the same URL inside the window '
        'delivers once', () async {
      await configure();
      native.arrive('https://aplnk.to/same');
      native.arrive('https://aplnk.to/same');
      await pump();
      expect(linkIds(events), ['same']);
      expect(native.resolveStarts, hasLength(1));
    });

    test('WL-S03 the same URL by the manual and the automatic path delivers '
        'once', () async {
      await configure();
      native.arrive('https://aplnk.to/shared');
      await pump();
      final manual = await WarpLink.handleDeepLink('https://aplnk.to/shared');
      await pump();
      expect(manual!.linkId, 'shared');
      expect(linkIds(events), ['shared']);
    });

    test('WL-S03 a manual call that overlaps the automatic resolve '
        'supersedes it, as in React Native', () async {
      await configure();
      final gate = hold('https://aplnk.to/shared');
      native.handlers[WarpLinkMethod.handleDeepLink] = (_) =>
          linkMap(linkId: 'manual');
      native.arrive('https://aplnk.to/shared');
      await pump();
      final manual = await WarpLink.handleDeepLink('https://aplnk.to/shared');
      expect(manual!.linkId, 'manual');
      expect(native.callsTo(WarpLinkMethod.handleDeepLink), hasLength(1));
      gate.complete();
      await pump();
      expect(events, isEmpty);
      expect(native.resolveStarts, hasLength(1));
      expect(native.claimed, hasLength(1));
    });

    test('a configuration that replaces the claiming one hands it the launch '
        'answer', () async {
      native.arrive('https://aplnk.to/launch', id: 'launch', isLaunch: true);
      final claim = Completer<void>();
      native.handlers[WarpLinkMethod.claimDelivery] = (args) async {
        await claim.future;
        return native.claimDeliveryNow(args);
      };
      final older = configure();
      await pump();
      final newer = <WarpLinkEvent>[];
      await WarpLink.configure(
        apiKey: validKey,
        automaticDeepLinks: false,
        onLink: newer.add,
      );
      claim.complete();
      await older;
      await pump();
      expect(events, isEmpty);
      expect(newer, isEmpty);
      expect((await WarpLink.getInitialDeepLink())!.linkId, 'launch');
      expect(await WarpLink.getInitialDeepLink(), isNull);
    });

    test('a configuration that replaces the claiming one and delivers '
        'automatically gets the answer', () async {
      native.arrive('https://aplnk.to/warm', id: 'warm');
      final claim = Completer<void>();
      native.handlers[WarpLinkMethod.claimDelivery] = (args) async {
        await claim.future;
        return native.claimDeliveryNow(args);
      };
      final older = configure();
      await pump();
      final newer = <WarpLinkEvent>[];
      await WarpLink.configure(apiKey: validKey, onLink: newer.add);
      claim.complete();
      await older;
      await pump();
      expect(events, isEmpty);
      expect(linkIds(newer), ['warm']);
    });

    test('WL-S22 a backward step of the arrival clock does not swallow a '
        'repeat', () async {
      await configure();
      native.arrive('https://aplnk.to/same', atMs: 50000);
      native.arrive('https://aplnk.to/same', atMs: 50800);
      await pump();
      expect(events, hasLength(1));
      native.arrive('https://aplnk.to/same', atMs: 100);
      await pump();
      expect(linkIds(events), ['same', 'same']);
    });

    test('a distinct arrival after the window delivers again', () async {
      await configure();
      native.arrive('https://aplnk.to/same');
      await pump();
      native.advanceClock(const Duration(milliseconds: 1499));
      native.arrive('https://aplnk.to/same');
      await pump();
      expect(events, hasLength(1));
      native.advanceClock(const Duration(seconds: 2));
      native.arrive('https://aplnk.to/same');
      await pump();
      expect(linkIds(events), ['same', 'same']);
      expect(native.resolveStarts, hasLength(2));
    });

    test('a subscriber still gets a repeat that onLink does not', () async {
      await configure();
      final streamed = <WarpLinkEvent>[];
      final sub = WarpLink.onDeepLink.listen(streamed.add);
      native.arrive('https://aplnk.to/same');
      await pump();
      native.arrive('https://aplnk.to/same');
      await pump();
      expect(linkIds(events), ['same']);
      expect(linkIds(streamed), ['same', 'same']);
      await sub.cancel();
    });

    test('a repeat standing in for an open tap delivers to onLink', () async {
      await configure();
      final streamed = <WarpLinkEvent>[];
      final sub = WarpLink.onDeepLink.listen(streamed.add);
      final gate = hold('https://aplnk.to/same');
      native.arrive('https://aplnk.to/same');
      native.arrive('https://aplnk.to/same');
      await pump();
      gate.complete();
      await pump();
      expect(linkIds(events), ['same']);
      expect(streamed, hasLength(2));
      await sub.cancel();
    });
  });
}
