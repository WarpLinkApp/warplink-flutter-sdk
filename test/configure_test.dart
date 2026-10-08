import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUpNative((value) => native = value);

  group('configure', () {
    test('sends the configuration with defaults', () async {
      await WarpLink.configure(apiKey: validKey);
      expect(native.argumentsOf(WarpLinkMethod.configure), <String, Object?>{
        'apiKey': validKey,
        'apiEndpoint': 'https://api.warplink.app/v1',
        'debugLogging': false,
        'linkDomains': <String>[],
        'automaticDeepLinks': false,
        'automaticDeferredDeepLinks': false,
      });
    });

    test('forwards every option', () async {
      await WarpLink.configure(
        apiKey: validKey,
        apiEndpoint: 'https://example.test/v1',
        debugLogging: true,
        linkDomains: const ['links.example.com', ' Other.com '],
        onLink: (_) {},
      );
      final args = native.argumentsOf(WarpLinkMethod.configure);
      expect(args['apiEndpoint'], 'https://example.test/v1');
      expect(args['debugLogging'], true);
      expect(args['linkDomains'], ['links.example.com', ' Other.com ']);
    });

    test(
      'WL-S14 native automatic handling stays off whatever the host asks',
      () async {
        await WarpLink.configure(
          apiKey: validKey,
          automaticDeepLinks: true,
          automaticDeferredDeepLinks: true,
          onLink: (_) {},
        );
        final args = native.argumentsOf(WarpLinkMethod.configure);
        expect(args['automaticDeepLinks'], false);
        expect(args['automaticDeferredDeepLinks'], false);
      },
    );

    test('accepts a test key', () async {
      const testKey = 'wl_test_abcdefghijklmnopqrstuvwxyz012345';
      await WarpLink.configure(apiKey: testKey);
      expect(native.argumentsOf(WarpLinkMethod.configure)['apiKey'], testKey);
    });

    for (final key in <String>[
      '',
      'wl_live_short',
      'wl_prod_abcdefghijklmnopqrstuvwxyz012345',
      'wl_live_abcdefghijklmnopqrstuvwxyz0123456',
      'wl_live_abcdefghijklmnopqrstuvwxyz01234!',
      ' wl_live_abcdefghijklmnopqrstuvwxyz012345',
    ]) {
      test('WL-S11 malformed key "$key" is reported, not thrown, and never '
          'reaches native', () async {
        final events = <WarpLinkEvent>[];
        final printed = <String>[];
        await runZoned(
          () => WarpLink.configure(apiKey: key, onLink: events.add),
          zoneSpecification: ZoneSpecification(
            print: (_, _, _, line) => printed.add(line),
          ),
        );
        expect(native.calls, isEmpty);
        expect(events, hasLength(1));
        expect(
          (events.single as ErrorEvent).error,
          isA<WarpLinkInvalidApiKeyFormatException>(),
        );
        expect(printed.single, startsWith('[WarpLink] Invalid API key format'));
        expect(printed.single, isNot(contains(key.isEmpty ? '\u0000' : key)));
      });
    }

    test('malformed key without onLink only logs', () async {
      await expectLater(WarpLink.configure(apiKey: 'nope'), completes);
      expect(native.calls, isEmpty);
    });

    test('a native failure goes to onLink and the future completes', () async {
      native.handlers[WarpLinkMethod.configure] = (_) =>
          throw PlatformException(code: 'E_NETWORK_ERROR', message: 'offline');
      final events = <WarpLinkEvent>[];
      await WarpLink.configure(apiKey: validKey, onLink: events.add);
      final error = (events.single as ErrorEvent).error;
      expect(error, isA<WarpLinkNetworkException>());
      expect(error.message, 'offline');
    });

    test('a native failure without onLink rejects the future', () async {
      native.handlers[WarpLinkMethod.configure] = (_) =>
          throw PlatformException(
            code: 'E_INVALID_API_KEY',
            message: 'rejected',
          );
      await expectLater(
        WarpLink.configure(apiKey: validKey),
        throwsA(isA<WarpLinkInvalidApiKeyException>()),
      );
    });

    test('a failed native configure resolves no arrival', () async {
      native.handlers[WarpLinkMethod.configure] = (_) =>
          throw PlatformException(code: 'E_NETWORK_ERROR', message: 'offline');
      native.arrive('https://aplnk.to/one');
      final events = <WarpLinkEvent>[];
      await WarpLink.configure(apiKey: validKey, onLink: events.add);
      await pump();
      expect(native.resolveStarts, isEmpty);
      expect(events, hasLength(1));
      expect(native.ledger, hasLength(1));
    });

    test('listens for arrivals before the native configure call', () async {
      var listenedAtConfigure = false;
      native.handlers[WarpLinkMethod.configure] = (_) {
        listenedAtConfigure = native.arrivalsListens == 1;
        return null;
      };
      await WarpLink.configure(apiKey: validKey, onLink: (_) {});
      expect(listenedAtConfigure, isTrue);
    });

    test('reconfigure replaces the callback and keeps one listener', () async {
      final first = <WarpLinkEvent>[];
      final second = <WarpLinkEvent>[];
      await WarpLink.configure(apiKey: validKey, onLink: first.add);
      await WarpLink.configure(apiKey: validKey, onLink: second.add);
      native.arrive('https://aplnk.to/one');
      await pump();
      expect(first, isEmpty);
      expect(linkIds(second), ['one']);
      expect(native.arrivalsListens, 1);
    });

    test('reconfigure without onLink drops the old callback', () async {
      final first = <WarpLinkEvent>[];
      await WarpLink.configure(apiKey: validKey, onLink: first.add);
      await WarpLink.configure(apiKey: validKey);
      native.arrive('https://aplnk.to/one');
      await pump();
      expect(first, isEmpty);
      expect(native.resolveStarts, isEmpty);
    });

    test('a malformed key keeps the earlier configuration', () async {
      final events = <WarpLinkEvent>[];
      await WarpLink.configure(apiKey: validKey, onLink: events.add);
      await runZoned(
        () => WarpLink.configure(apiKey: 'bad'),
        zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}),
      );
      native.arrive('https://aplnk.to/one');
      await pump();
      expect(linkIds(events), ['one']);
    });

    test('the future does not wait for the launch link', () async {
      native.arrive('https://aplnk.to/launch', isLaunch: true);
      native.gates['https://aplnk.to/launch'] = Completer<void>();
      final events = <WarpLinkEvent>[];
      await WarpLink.configure(apiKey: validKey, onLink: events.add);
      expect(events, isEmpty);
      native.gates['https://aplnk.to/launch']!.complete();
      await pump();
      expect(linkIds(events), ['launch']);
    });
  });
}
