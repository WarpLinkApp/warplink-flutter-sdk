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

  group('out-of-order configure completion', () {
    late Completer<Object?> firstReply;

    setUp(() {
      firstReply = Completer<Object?>();
      var calls = 0;
      native.handlers[WarpLinkMethod.configure] = (_) =>
          calls++ == 0 ? firstReply.future : null;
    });

    test('an older native failure never reaches any callback', () async {
      final first = <WarpLinkEvent>[];
      final second = <WarpLinkEvent>[];
      final firstDone = WarpLink.configure(apiKey: validKey, onLink: first.add);
      await pump();
      await WarpLink.configure(apiKey: validKey, onLink: second.add);
      firstReply.completeError(
        PlatformException(code: 'E_NETWORK_ERROR', message: 'offline'),
      );
      await firstDone;
      await pump();
      expect(first, isEmpty);
      expect(second, isEmpty);
    });

    test('a newer native failure still reaches the newer callback', () async {
      final first = <WarpLinkEvent>[];
      final second = <WarpLinkEvent>[];
      final firstDone = WarpLink.configure(apiKey: validKey, onLink: first.add);
      await pump();
      native.handlers[WarpLinkMethod.configure] = (_) =>
          throw PlatformException(code: 'E_NETWORK_ERROR', message: 'offline');
      await WarpLink.configure(apiKey: validKey, onLink: second.add);
      firstReply.complete(null);
      await firstDone;
      expect(first, isEmpty);
      expect(
        (second.single as ErrorEvent).error,
        isA<WarpLinkNetworkException>(),
      );
    });

    test(
      'an older failure without onLink still rejects its own future',
      () async {
        final firstDone = WarpLink.configure(apiKey: validKey);
        await pump();
        await WarpLink.configure(apiKey: validKey, onLink: (_) {});
        firstReply.completeError(
          PlatformException(code: 'E_INVALID_API_KEY', message: 'rejected'),
        );
        await expectLater(
          firstDone,
          throwsA(isA<WarpLinkInvalidApiKeyException>()),
        );
      },
    );

    test('an arrival waits for the newest native configure', () async {
      final events = <WarpLinkEvent>[];
      final done = WarpLink.configure(apiKey: validKey, onLink: events.add);
      await pump();
      native.arrive('https://aplnk.to/one');
      await pump();
      expect(native.resolveStarts, isEmpty);
      firstReply.complete(null);
      await done;
      await pump();
      expect(linkIds(events), ['one']);
    });
  });
}
