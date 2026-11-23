import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

Map<String, Object?> deferredLink([String id = 'deferred']) =>
    linkMap(linkId: id)..['isDeferred'] = true;

PlatformException offline() =>
    PlatformException(code: 'E_NETWORK_ERROR', message: 'offline');

/// A same-key repeat keeps the session, and still gives an unfinished check one
/// more chance. Native backoff and the age and give-up limits decide whether
/// the call sends a request, so a repeat never adds a rule of its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUpNative((value) => native = value);
  setUp(() {
    native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => false;
    native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) => null;
    native.handlers[WarpLinkMethod.getDeferredCheckStatus] = (_) =>
        <String, Object?>{'state': 'notChecked'};
  });

  int configures() => native.callsTo(WarpLinkMethod.configure).length;
  int checks() => native.callsTo(WarpLinkMethod.checkDeferredDeepLink).length;

  void statusIs(Map<String, Object?> status) =>
      native.handlers[WarpLinkMethod.getDeferredCheckStatus] = (_) => status;

  group('a same-key repeat after the first run finished', () {
    test('keeps the session and asks native for one more check', () async {
      await WarpLink.configure(apiKey: validKey, onLink: (_) {});
      await pump();
      await WarpLink.configure(apiKey: validKey, onLink: (_) {});
      await pump();

      expect(configures(), 1);
      expect(checks(), 2);
    });

    test('sends a match from the retry to the newer callback', () async {
      final first = <WarpLinkEvent>[];
      final second = <WarpLinkEvent>[];
      await WarpLink.configure(apiKey: validKey, onLink: first.add);
      await pump();
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          deferredLink();

      await WarpLink.configure(apiKey: validKey, onLink: second.add);
      await pump();

      expect(first, isEmpty);
      expect(linkIds(second), ['deferred']);
    });

    test('delivers a failed retry to the newer callback as an error', () async {
      await WarpLink.configure(apiKey: validKey, onLink: (_) {});
      await pump();
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          throw offline();
      final events = <WarpLinkEvent>[];

      await WarpLink.configure(apiKey: validKey, onLink: events.add);
      await pump();

      expect(events.single, isA<ErrorEvent>());
    });

    for (final state in ['matched', 'noMatch', 'checking']) {
      test('asks nothing when the status is $state', () async {
        await WarpLink.configure(apiKey: validKey, onLink: (_) {});
        await pump();
        statusIs(<String, Object?>{'state': state});

        await WarpLink.configure(apiKey: validKey, onLink: (_) {});
        await pump();

        expect(checks(), 1);
      });
    }

    for (final status in <Map<String, Object?>>[
      {'state': 'waiting', 'retryAt': 1800000000000},
      {'state': 'skippedOldInstall'},
      {'state': 'stopped'},
    ]) {
      test('still asks native when the status is $status', () async {
        await WarpLink.configure(apiKey: validKey, onLink: (_) {});
        await pump();
        statusIs(status);

        await WarpLink.configure(apiKey: validKey, onLink: (_) {});
        await pump();

        expect(checks(), 2);
      });
    }

    test('asks nothing when the deferred check is switched off', () async {
      for (var i = 0; i < 2; i++) {
        await WarpLink.configure(
          apiKey: validKey,
          automaticDeferredDeepLinks: false,
          onLink: (_) {},
        );
        await pump();
      }

      expect(native.callsTo(WarpLinkMethod.getDeferredCheckStatus), isEmpty);
      expect(checks(), 0);
    });

    test(
      'shares one retry between repeats that arrive while it runs',
      () async {
        await WarpLink.configure(apiKey: validKey, onLink: (_) {});
        await pump();
        final answer = Completer<Object?>();
        native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
            answer.future;
        final second = <WarpLinkEvent>[];

        await WarpLink.configure(apiKey: validKey, onLink: second.add);
        await pump();
        await WarpLink.configure(apiKey: validKey, onLink: (_) {});
        await pump();
        answer.complete(deferredLink());
        await pump();

        expect(checks(), 2);
        expect(second, isEmpty);
      },
    );
  });

  group('a same-key repeat while the first run is still going', () {
    test('adds no retry: the running check answers', () async {
      final answer = Completer<Object?>();
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          answer.future;

      await WarpLink.configure(apiKey: validKey, onLink: (_) {});
      await pump();
      await WarpLink.configure(apiKey: validKey, onLink: (_) {});
      await pump();
      answer.complete(null);
      await pump();

      expect(checks(), 1);
      expect(native.callsTo(WarpLinkMethod.getDeferredCheckStatus), isEmpty);
    });
  });
}
