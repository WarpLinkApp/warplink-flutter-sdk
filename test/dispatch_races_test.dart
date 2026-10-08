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

  Future<void> configure({
    bool automaticDeepLinks = true,
    WarpLinkListener? onLink,
  }) => WarpLink.configure(
    apiKey: validKey,
    automaticDeepLinks: automaticDeepLinks,
    onLink: onLink ?? events.add,
  );

  Completer<void> holdClaim(String arrivalId) =>
      native.claimGates[arrivalId] = Completer<void>();

  Future<StreamSubscription<WarpLinkEvent>> subscribe(
    List<WarpLinkEvent> into,
  ) async {
    final sub = WarpLink.onDeepLink.listen(into.add);
    await pump();
    return sub;
  }

  group('a recipient that changes while a claim is pending', () {
    test('a repeat whose subscriber left before the claim is held for the '
        'next subscriber, and never reaches onLink', () async {
      await configure();
      final first = <WarpLinkEvent>[];
      final sub = await subscribe(first);
      native.arrive('https://aplnk.to/tap', id: 'tap');
      await pump();
      final gate = holdClaim('again');
      native.arrive('https://aplnk.to/tap', id: 'again', atMs: 100);
      await pump();
      await sub.cancel();
      await pump();
      gate.complete();
      await pump();
      expect(native.claimed, ['tap', 'again']);
      final second = <WarpLinkEvent>[];
      final next = await subscribe(second);
      expect(linkIds(second), ['tap']);
      expect(linkIds(events), ['tap']);
      await next.cancel();
    });

    test('a subscriber-only answer held after the subscriber left goes to a '
        'later automatic configuration once', () async {
      await configure(automaticDeepLinks: false);
      final sub = await subscribe(<WarpLinkEvent>[]);
      final gate = holdClaim('warm');
      native.arrive('https://aplnk.to/warm', id: 'warm');
      await pump();
      await sub.cancel();
      await pump();
      gate.complete();
      await pump();
      expect(events, isEmpty);
      await configure();
      await pump();
      expect(linkIds(events), ['warm']);
      await configure();
      await pump();
      expect(linkIds(events), ['warm']);
      expect(native.claimed, ['warm']);
    });

    test('a foreign URL whose claim was pending when a subscriber joined '
        'reaches that subscriber as an error', () async {
      await configure();
      final gate = holdClaim('foreign');
      native.arrive('https://example.com/x', id: 'foreign');
      await pump();
      final streamed = <WarpLinkEvent>[];
      final sub = await subscribe(streamed);
      gate.complete();
      await pump();
      expect(streamed, hasLength(1));
      expect(
        (streamed.single as ErrorEvent).error,
        isA<WarpLinkInvalidUrlException>(),
      );
      expect(events, isEmpty);
      expect(native.claimed, ['foreign']);
      await sub.cancel();
    });

    test('a repeat whose claim was pending when a subscriber joined reaches '
        'that subscriber and not onLink', () async {
      await configure();
      native.arrive('https://aplnk.to/tap', id: 'tap');
      await pump();
      final gate = holdClaim('again');
      native.arrive('https://aplnk.to/tap', id: 'again', atMs: 100);
      await pump();
      final streamed = <WarpLinkEvent>[];
      final sub = await subscribe(streamed);
      gate.complete();
      await pump();
      expect(linkIds(streamed), ['tap']);
      expect(linkIds(events), ['tap']);
      await sub.cancel();
    });

    test('a subscriber that cancels before the claim answers misses the '
        'answer, and the next one gets the held copy', () async {
      await configure(automaticDeepLinks: false);
      final gone = <WarpLinkEvent>[];
      final sub = await subscribe(gone);
      final gate = holdClaim('warm');
      native.arrive('https://aplnk.to/warm', id: 'warm');
      await pump();
      await sub.cancel();
      gate.complete();
      await pump();
      expect(gone, isEmpty);
      final next = <WarpLinkEvent>[];
      final again = await subscribe(next);
      expect(linkIds(next), ['warm']);
      await again.cancel();
    });
  });

  group('a host callback that configures during a flush', () {
    Future<void> holdThree() async {
      final gates = [for (var i = 0; i < 3; i++) holdClaim('a$i')];
      final older = configure();
      await pump();
      for (var i = 0; i < 3; i++) {
        native.arrive('https://aplnk.to/l$i', atMs: i * 2000);
      }
      await pump();
      await configure(automaticDeepLinks: false);
      for (final gate in gates) {
        gate.complete();
      }
      await older;
      await pump();
    }

    test('the rest of the held answers go to the newer onLink', () async {
      await holdThree();
      final newer = <WarpLinkEvent>[];
      var configured = false;
      await configure(
        onLink: (event) {
          events.add(event);
          if (!configured) {
            configured = true;
            unawaited(configure(onLink: newer.add));
          }
        },
      );
      await pump();
      expect(linkIds(events), ['l0']);
      expect(linkIds(newer), ['l1', 'l2']);
    });

    test('turning the automatic path off keeps the rest held for a '
        'subscriber', () async {
      await holdThree();
      await configure(
        onLink: (event) {
          events.add(event);
          unawaited(configure(automaticDeepLinks: false));
        },
      );
      await pump();
      expect(linkIds(events), ['l0']);
      final streamed = <WarpLinkEvent>[];
      final sub = await subscribe(streamed);
      expect(linkIds(streamed), ['l1', 'l2']);
      await sub.cancel();
    });
  });
}
