import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUpNative((value) => native = value);

  /// Leaves one answer held: claimed while no recipient wanted it.
  Future<void> holdOneAnswer() async {
    final claim = Completer<void>();
    native.handlers[WarpLinkMethod.claimDelivery] = (args) async {
      await claim.future;
      return native.claimDeliveryNow(args);
    };
    native.arrive('https://aplnk.to/held');
    final older = WarpLink.configure(apiKey: validKey, onLink: (_) {});
    await pump();
    await WarpLink.configure(apiKey: validKey, automaticDeepLinks: false);
    claim.complete();
    await older;
    await pump();
  }

  group('a held answer reaches a new subscriber', () {
    test('after listen returned, even when the callback cancels', () async {
      await holdOneAnswer();
      final cancelsBefore = native.arrivalsCancels;
      final events = <WarpLinkEvent>[];
      StreamSubscription<WarpLinkEvent>? sub;
      var isListenReturned = false;
      var deliveredBeforeReturn = false;
      sub = WarpLink.onDeepLink.listen((event) {
        deliveredBeforeReturn = !isListenReturned;
        events.add(event);
        unawaited(sub?.cancel());
      });
      isListenReturned = true;
      await pump();
      expect(deliveredBeforeReturn, isFalse);
      expect(linkIds(events), ['held']);
      expect(native.arrivalsCancels, cancelsBefore + 1);
    });

    test('once, when the callback reconfigures', () async {
      await holdOneAnswer();
      final events = <WarpLinkEvent>[];
      final sub = WarpLink.onDeepLink.listen((event) {
        events.add(event);
        unawaited(
          WarpLink.configure(apiKey: validKey, automaticDeepLinks: false),
        );
      });
      await pump();
      expect(linkIds(events), ['held']);
      await sub.cancel();
    });
  });
}
