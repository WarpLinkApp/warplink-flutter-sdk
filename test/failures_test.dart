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

  group('failures', () {
    test('WL-S21 a failure reaches onLink as a WarpLink error', () async {
      native.resolver = (_) async =>
          throw PlatformException(code: 'E_NETWORK_ERROR', message: 'offline');
      await configure();
      native.arrive('https://aplnk.to/one');
      await pump();
      expect(
        (events.single as ErrorEvent).error,
        isA<WarpLinkNetworkException>(),
      );
    });

    test('WL-S27 a failed tap resolves once and is not redispatched', () async {
      native.resolver = (_) async =>
          throw PlatformException(code: 'E_SERVER_ERROR', message: 'boom');
      await configure();
      native.arrive('https://aplnk.to/one');
      await pump();
      await pump();
      expect(events, hasLength(1));
      expect(native.resolveStarts, hasLength(1));
      expect(native.claimed, hasLength(1));
    });

    test('a failed resolve releases the dedupe so a re-tap resolves', () async {
      var attempts = 0;
      native.resolver = (url) async {
        if (attempts++ == 0) {
          throw PlatformException(code: 'E_NETWORK_ERROR', message: 'offline');
        }
        return linkMap(linkId: 'retry');
      };
      await configure();
      native.arrive('https://aplnk.to/one');
      await pump();
      native.arrive('https://aplnk.to/one');
      await pump();
      expect(events, hasLength(2));
      expect(events[0], isA<ErrorEvent>());
      expect(linkIds([events[1]]), ['retry']);
    });

    test('WL-S26 a password protected link is an error without a '
        'destination', () async {
      native.resolver = (_) async => throw PlatformException(
        code: 'E_PASSWORD_REQUIRED',
        message: 'locked',
      );
      await configure();
      native.arrive('https://aplnk.to/locked');
      await pump();
      expect(
        (events.single as ErrorEvent).error,
        isA<WarpLinkPasswordRequiredException>(),
      );
    });

    test(
      'an exception thrown by onLink does not stop later arrivals',
      () async {
        var calls = 0;
        await runZonedGuarded(() async {
          await WarpLink.configure(
            apiKey: validKey,
            onLink: (event) {
              calls++;
              throw StateError('host bug');
            },
          );
          native.arrive('https://aplnk.to/one');
          await pump();
          native.arrive('https://aplnk.to/two');
          await pump();
        }, (error, stack) {});
        expect(calls, 2);
        expect(native.claimed, hasLength(2));
      },
    );
  });
}
