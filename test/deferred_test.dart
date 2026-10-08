import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

Map<String, Object?> deferredLink([String id = 'deferred']) =>
    linkMap(linkId: id)..['isDeferred'] = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;
  late List<WarpLinkEvent> events;

  setUpNative((value) => native = value);
  setUp(() {
    events = <WarpLinkEvent>[];
    native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => false;
  });

  Future<void> configure({
    bool automaticDeferredDeepLinks = true,
    List<WarpLinkEvent>? into,
    bool withOnLink = true,
  }) => WarpLink.configure(
    apiKey: validKey,
    automaticDeferredDeepLinks: automaticDeferredDeepLinks,
    onLink: withOnLink ? (into ?? events).add : null,
  );

  int checks() => native.callsTo(WarpLinkMethod.checkDeferredDeepLink).length;

  group('deferred check', () {
    test('runs after the cold start link, never before', () async {
      final gate = native.gates['https://aplnk.to/launch'] = Completer<void>();
      native.arrive('https://aplnk.to/launch', isLaunch: true);
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          deferredLink();
      await configure();
      await pump();
      expect(checks(), 0);
      gate.complete();
      await pump();
      expect(linkIds(events), ['launch', 'deferred']);
      expect(checks(), 1);
    });

    test('WL-S05 a no-match delivers nothing', () async {
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) => null;
      await configure();
      await pump();
      expect(checks(), 1);
      expect(events, isEmpty);
    });

    test(
      'WL-S14 the automatic check defaults to on and can be turned off',
      () async {
        native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
            deferredLink();
        await configure(automaticDeferredDeepLinks: false);
        await pump();
        expect(checks(), 0);
        await configure();
        await pump();
        expect(linkIds(events), ['deferred']);
      },
    );

    test('WL-S04 is skipped once attribution completed', () async {
      native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => true;
      await configure();
      await pump();
      expect(checks(), 0);
      expect(events, isEmpty);
    });

    test(
      'runs without onLink because the request attributes the install',
      () async {
        native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
            deferredLink();
        await configure(withOnLink: false);
        await pump();
        expect(checks(), 1);
        expect(events, isEmpty);
      },
    );

    test('a failure reaches onLink and the next launch retries', () async {
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          throw PlatformException(code: 'E_NETWORK_ERROR', message: 'offline');
      await configure();
      await pump();
      expect(
        (events.single as ErrorEvent).error,
        isA<WarpLinkNetworkException>(),
      );
      await WarpLink.resetForTesting();
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          deferredLink();
      await configure();
      await pump();
      expect(linkIds(events.skip(1).toList()), ['deferred']);
      expect(checks(), 2);
    });

    test('a new process asks again while attribution is open', () async {
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          deferredLink();
      await configure();
      await pump();
      await WarpLink.resetForTesting();
      await configure();
      await pump();
      expect(linkIds(events), ['deferred', 'deferred']);
    });

    test('a cold start link that throws does not skip the check', () async {
      native.arrive('https://aplnk.to/launch', isLaunch: true);
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          deferredLink();
      final reached = <String>[];
      await runZonedGuarded(() async {
        await WarpLink.configure(
          apiKey: validKey,
          onLink: (event) {
            reached.add((event as LinkEvent).deepLink.linkId);
            if (reached.length == 1) throw StateError('host bug');
          },
        );
        await pump();
      }, (error, stack) {});
      expect(reached, ['launch', 'deferred']);
    });
  });

  group('one request per install', () {
    test('WL-S04 reconfigure and restart while a request is in flight make '
        'one request', () async {
      final answer = Completer<Object?>();
      var attributed = false;
      native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => attributed;
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          answer.future.whenComplete(() => attributed = true);
      await configure();
      await pump();
      await configure();
      await configure();
      await pump();
      expect(checks(), 1);
      answer.complete(deferredLink());
      await pump();
      expect(linkIds(events), ['deferred']);
      await WarpLink.resetForTesting();
      final restarted = <WarpLinkEvent>[];
      await configure(into: restarted);
      await pump();
      expect(checks(), 1);
      expect(restarted, isEmpty);
    });

    test('WL-S04 a restart while the request is in flight sends one native '
        'request', () async {
      final answer = Completer<Object?>();
      var requests = 0;
      Future<Object?>? inFlight;
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          inFlight ??= () {
            requests++;
            return answer.future;
          }();
      await configure();
      await pump();
      await WarpLink.resetForTesting();
      final restarted = <WarpLinkEvent>[];
      await configure(into: restarted);
      await pump();
      expect(requests, 1);
      answer.complete(deferredLink());
      await pump();
      expect(requests, 1);
      expect(linkIds(restarted), ['deferred']);
    });
  });

  group('reconfigure while the check is in flight', () {
    late Completer<Object?> answer;

    setUp(() {
      answer = Completer<Object?>();
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          answer.future;
    });

    test('WL-S07 one check, delivered once to the newer callback', () async {
      final older = <WarpLinkEvent>[];
      final newer = <WarpLinkEvent>[];
      await configure(into: older);
      await pump();
      await configure(into: newer);
      await pump();
      answer.complete(deferredLink());
      await pump();
      expect(older, isEmpty);
      expect(linkIds(newer), ['deferred']);
      expect(checks(), 1);
    });

    test('WL-S07 an answer that lands before the newer configure finishes '
        'is held for it', () async {
      final older = <WarpLinkEvent>[];
      final newer = <WarpLinkEvent>[];
      await configure(into: older);
      await pump();
      final secondConfigure = Completer<Object?>();
      native.handlers[WarpLinkMethod.configure] = (_) => secondConfigure.future;
      final done = configure(into: newer);
      await pump();
      answer.complete(deferredLink());
      await pump();
      expect(older, isEmpty);
      secondConfigure.complete(null);
      await done;
      await pump();
      expect(older, isEmpty);
      expect(linkIds(newer), ['deferred']);
    });
  });
}
