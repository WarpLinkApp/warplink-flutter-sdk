import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/src/held_answers.dart';
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
    WarpLinkListener? onLink,
  }) => WarpLink.configure(
    apiKey: validKey,
    automaticDeepLinks: automaticDeepLinks,
    onLink: onLink ?? events.add,
  );

  Completer<void> blockClaims() {
    final claim = Completer<void>();
    native.handlers[WarpLinkMethod.claimDelivery] = (args) async {
      await claim.future;
      return native.claimDeliveryNow(args);
    };
    return claim;
  }

  group('recipients are chosen from the current state', () {
    test('an automatic run that the newest configuration replaced with no '
        'consumer leaves the arrival unclaimed, and a subscriber gets it '
        'once', () async {
      final gate = native.gates['https://aplnk.to/warm'] = Completer<void>();
      await configure();
      native.arrive('https://aplnk.to/warm');
      await pump();
      await configure(automaticDeepLinks: false);
      gate.complete();
      await pump();
      expect(native.claimed, isEmpty);
      expect(events, isEmpty);
      final streamed = <WarpLinkEvent>[];
      final sub = WarpLink.onDeepLink.listen(streamed.add);
      await pump();
      expect(linkIds(streamed), ['warm']);
      expect(native.claimed, ['a0']);
      expect(native.resolveStarts, hasLength(1));
      await sub.cancel();
    });

    test('a subscriber run that a newer automatic configuration replaced '
        'delivers to the new onLink once', () async {
      await configure(automaticDeepLinks: false);
      final streamed = <WarpLinkEvent>[];
      final sub = WarpLink.onDeepLink.listen(streamed.add);
      await pump();
      final gate = native.gates['https://aplnk.to/warm'] = Completer<void>();
      native.arrive('https://aplnk.to/warm');
      await pump();
      final newer = <WarpLinkEvent>[];
      await configure(onLink: newer.add);
      gate.complete();
      await pump();
      expect(linkIds(newer), ['warm']);
      expect(linkIds(streamed), ['warm']);
      expect(events, isEmpty);
      expect(native.claimed, ['a0']);
      await sub.cancel();
    });

    test('an answer claimed while the configuration changed to no consumer '
        'is held and a later subscriber gets it once', () async {
      final claim = blockClaims();
      native.arrive('https://aplnk.to/warm');
      final older = configure();
      await pump();
      await configure(automaticDeepLinks: false);
      claim.complete();
      await older;
      await pump();
      expect(events, isEmpty);
      final first = <WarpLinkEvent>[];
      final subA = WarpLink.onDeepLink.listen(first.add);
      await pump();
      expect(linkIds(first), ['warm']);
      await subA.cancel();
      final second = <WarpLinkEvent>[];
      final subB = WarpLink.onDeepLink.listen(second.add);
      await pump();
      expect(second, isEmpty);
      await subB.cancel();
    });

    test(
      'a held answer goes to the next automatic configuration once',
      () async {
        final claim = blockClaims();
        native.arrive('https://aplnk.to/warm');
        final older = configure();
        await pump();
        await configure(automaticDeepLinks: false);
        claim.complete();
        await older;
        await pump();
        final newer = <WarpLinkEvent>[];
        await configure(onLink: newer.add);
        await pump();
        expect(linkIds(newer), ['warm']);
        final latest = <WarpLinkEvent>[];
        await configure(onLink: latest.add);
        await pump();
        expect(latest, isEmpty);
      },
    );

    test('a held launch answer is not offered to subscribers', () async {
      final claim = blockClaims();
      native.arrive('https://aplnk.to/launch', id: 'launch', isLaunch: true);
      final older = configure();
      await pump();
      await configure(automaticDeepLinks: false);
      claim.complete();
      await older;
      await pump();
      final streamed = <WarpLinkEvent>[];
      final sub = WarpLink.onDeepLink.listen(streamed.add);
      await pump();
      expect(streamed, isEmpty);
      expect((await WarpLink.getInitialDeepLink())!.linkId, 'launch');
      await sub.cancel();
    });

    test('the held queue drops the oldest answer past its cap', () async {
      final claim = blockClaims();
      final older = configure();
      await pump();
      for (var i = 0; i <= heldAnswerCap; i++) {
        native.arrive('https://aplnk.to/l$i', atMs: i * 2000);
      }
      await pump();
      await configure(automaticDeepLinks: false);
      claim.complete();
      await older;
      await pump();
      final streamed = <WarpLinkEvent>[];
      final sub = WarpLink.onDeepLink.listen(streamed.add);
      await pump();
      expect(streamed, hasLength(heldAnswerCap));
      expect(linkIds(streamed).first, 'l1');
      expect(linkIds(streamed).last, 'l$heldAnswerCap');
      await sub.cancel();
    });

    test('a subscriber that reconfigures during a flush redirects the '
        'remaining held answers', () async {
      final claim = blockClaims();
      final older = configure();
      await pump();
      for (var i = 0; i < 3; i++) {
        native.arrive('https://aplnk.to/w$i', atMs: i * 2000);
      }
      await pump();
      await configure(automaticDeepLinks: false);
      claim.complete();
      await older;
      await pump();

      final streamed = <WarpLinkEvent>[];
      final newer = <WarpLinkEvent>[];
      StreamSubscription<WarpLinkEvent>? sub;
      await configure(
        onLink: (event) {
          events.add(event);
          sub ??= WarpLink.onDeepLink.listen((streamedEvent) {
            streamed.add(streamedEvent);
            unawaited(sub!.cancel());
            unawaited(configure(onLink: newer.add));
          });
        },
      );
      await pump();
      expect(linkIds(events), ['w0', 'w1']);
      expect(linkIds(streamed), ['w1']);
      expect(linkIds(newer), ['w2']);
    });
  });
}
