import 'dart:async';

import 'package:flutter/services.dart';
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
    List<String> linkDomains = const <String>[],
  }) => WarpLink.configure(
    apiKey: validKey,
    automaticDeepLinks: automaticDeepLinks,
    linkDomains: linkDomains,
    onLink: events.add,
  );

  Completer<void> hold(String url) => native.gates[url] = Completer<void>();

  group('supersede', () {
    test('a newer link drops the stale answer of an older one', () async {
      await configure();
      final gate = hold('https://aplnk.to/old');
      native.arrive('https://aplnk.to/old', id: 'old');
      native.arrive('https://aplnk.to/new', id: 'new');
      await pump();
      expect(linkIds(events), ['new']);
      gate.complete();
      await pump();
      expect(linkIds(events), ['new']);
      expect(native.claimed, containsAll(<String>['old', 'new']));
    });

    test(
      'a manual resolve of a link supersedes an open automatic tap',
      () async {
        await configure();
        final gate = hold('https://aplnk.to/auto');
        native.arrive('https://aplnk.to/auto');
        await pump();
        final manual = await WarpLink.handleDeepLink('https://aplnk.to/manual');
        expect(manual!.linkId, 'manual');
        gate.complete();
        await pump();
        expect(events, isEmpty);
      },
    );

    test('WL-S09 a foreign URL supersedes nothing', () async {
      await configure();
      final gate = hold('https://aplnk.to/real');
      native.arrive('https://aplnk.to/real');
      native.arrive('myapp://oauth/callback');
      await pump();
      gate.complete();
      await pump();
      expect(linkIds(events), ['real']);
    });

    test('WL-S09 a foreign URL does not stamp the dedupe window', () async {
      await configure();
      native.arrive('https://aplnk.to/one');
      native.arrive('myapp://oauth/callback');
      native.arrive('https://aplnk.to/one');
      await pump();
      expect(linkIds(events), ['one']);
    });
  });

  Completer<void> holdClaim(String arrivalId) =>
      native.claimGates[arrivalId] = Completer<void>();

  /// Makes the resolve of [url] fail the way a cancelled request does.
  void failWhenReleased(String url) {
    final defaultResolver = native.resolver;
    native.resolver = (requested) async {
      if (requested != url) {
        return defaultResolver(requested);
      }
      await native.gates[url]?.future;
      throw PlatformException(code: 'E_NETWORK_ERROR', message: 'cancelled');
    };
  }

  Future<StreamSubscription<WarpLinkEvent>> subscribe(
    List<WarpLinkEvent> into,
  ) async {
    final sub = WarpLink.onDeepLink.listen(into.add);
    await pump();
    return sub;
  }

  group('a superseded answer for subscribers', () {
    test('an error is delivered to nobody and is claimed', () async {
      await configure();
      final streamed = <WarpLinkEvent>[];
      final sub = await subscribe(streamed);
      final gate = hold('https://aplnk.to/old');
      failWhenReleased('https://aplnk.to/old');
      native.arrive('https://aplnk.to/old', id: 'old');
      native.arrive('https://aplnk.to/new', id: 'new');
      await pump();
      gate.complete();
      await pump();
      expect(linkIds(streamed), ['new']);
      expect(linkIds(events), ['new']);
      expect(native.claimed, containsAll(<String>['old', 'new']));
      await sub.cancel();
    });

    test('a link is delivered to the subscriber and not to onLink', () async {
      await configure();
      final streamed = <WarpLinkEvent>[];
      final sub = await subscribe(streamed);
      final gate = hold('https://aplnk.to/old');
      native.arrive('https://aplnk.to/old', id: 'old');
      native.arrive('https://aplnk.to/new', id: 'new');
      await pump();
      gate.complete();
      await pump();
      expect(linkIds(streamed), ['new', 'old']);
      expect(linkIds(events), ['new']);
      await sub.cancel();
    });

    test('a held error is dropped when a subscriber joins later', () async {
      await configure(automaticDeepLinks: false);
      final first = <WarpLinkEvent>[];
      final sub = await subscribe(first);
      final gate = hold('https://aplnk.to/old');
      failWhenReleased('https://aplnk.to/old');
      native.arrive('https://aplnk.to/old', id: 'old');
      native.arrive('https://aplnk.to/new', id: 'new');
      await pump();
      final claim = holdClaim('old');
      gate.complete();
      await pump();
      await sub.cancel();
      await pump();
      claim.complete();
      await pump();
      final later = <WarpLinkEvent>[];
      final next = await subscribe(later);
      expect(later, isEmpty);
      expect(native.claimed, containsAll(<String>['old', 'new']));
      await next.cancel();
    });

    test('an error resolved after the last subscriber left is claimed, '
        'not replayed', () async {
      await configure(automaticDeepLinks: false);
      final first = <WarpLinkEvent>[];
      final sub = await subscribe(first);
      final gate = hold('https://aplnk.to/old');
      failWhenReleased('https://aplnk.to/old');
      native.arrive('https://aplnk.to/old', id: 'old');
      native.arrive('https://aplnk.to/new', id: 'new');
      await pump();
      await sub.cancel();
      await pump();
      gate.complete();
      await pump();
      expect(native.claimed, contains('old'));
      final later = <WarpLinkEvent>[];
      final next = await subscribe(later);
      expect(later.whereType<ErrorEvent>(), isEmpty);
      await next.cancel();
    });

    test('a held link reaches a subscriber that joins later', () async {
      await configure(automaticDeepLinks: false);
      final first = <WarpLinkEvent>[];
      final sub = await subscribe(first);
      final gate = hold('https://aplnk.to/old');
      native.arrive('https://aplnk.to/old', id: 'old');
      native.arrive('https://aplnk.to/new', id: 'new');
      await pump();
      final claim = holdClaim('old');
      gate.complete();
      await pump();
      await sub.cancel();
      await pump();
      claim.complete();
      await pump();
      final later = <WarpLinkEvent>[];
      final next = await subscribe(later);
      expect(linkIds(later), ['old']);
      await next.cancel();
    });
  });

  group('foreign URLs', () {
    test('WL-S09 a foreign URL reaches onLink neither as a link nor an '
        'error', () async {
      await configure();
      native.arrive('https://example.com/x');
      await pump();
      expect(events, isEmpty);
      expect(native.resolveStarts, isEmpty);
      expect(native.claimed, hasLength(1));
    });

    test('a foreign URL reaches explicit subscribers as invalidUrl', () async {
      await configure();
      final streamed = <WarpLinkEvent>[];
      final sub = WarpLink.onDeepLink.listen(streamed.add);
      native.arrive('https://example.com/x');
      await pump();
      expect(events, isEmpty);
      expect(
        (streamed.single as ErrorEvent).error,
        isA<WarpLinkInvalidUrlException>(),
      );
      await sub.cancel();
    });

    test('a classification that never answers fails open', () async {
      native.handlers['isWarpLinkUrl'] = (_) => Completer<Object?>().future;
      await configure();
      native.arrive('https://aplnk.to/slow');
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(linkIds(events), ['slow']);
    });
  });
}
