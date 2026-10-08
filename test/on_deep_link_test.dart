import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;
  late List<WarpLinkEvent> events;

  setUpNative((value) => native = value);
  setUp(() async {
    events = <WarpLinkEvent>[];
    await WarpLink.configure(apiKey: validKey);
  });

  group('onDeepLink', () {
    test('emits a link event per arrival', () async {
      final sub = WarpLink.onDeepLink.listen(events.add);
      await pump();
      native.arrive('https://aplnk.to/one');
      native.arrive('https://aplnk.to/two');
      await pump();
      expect(linkIds(events), ['one', 'two']);
      await sub.cancel();
    });

    test('is not deduplicated', () async {
      final sub = WarpLink.onDeepLink.listen(events.add);
      await pump();
      native.arrive('https://aplnk.to/same');
      native.arrive('https://aplnk.to/same');
      await pump();
      expect(linkIds(events), ['same', 'same']);
      await sub.cancel();
    });

    test('resolves once for several listeners', () async {
      final other = <WarpLinkEvent>[];
      final subA = WarpLink.onDeepLink.listen(events.add);
      final subB = WarpLink.onDeepLink.listen(other.add);
      await pump();
      native.arrive('https://aplnk.to/one');
      await pump();
      expect(events, hasLength(1));
      expect(other, hasLength(1));
      expect(native.resolveStarts, hasLength(1));
      expect(native.arrivalsListens, 1);
      await subA.cancel();
      await subB.cancel();
    });

    test(
      'a url received before the first listener is delivered then',
      () async {
        native.arrive('https://aplnk.to/early');
        await pump();
        expect(native.resolveStarts, isEmpty);
        final sub = WarpLink.onDeepLink.listen(events.add);
        await pump();
        expect(linkIds(events), ['early']);
        await sub.cancel();
      },
    );

    test('the launch arrival is not part of the stream', () async {
      native.arrive('https://aplnk.to/launch', isLaunch: true);
      final sub = WarpLink.onDeepLink.listen(events.add);
      await pump();
      expect(events, isEmpty);
      expect(native.ledger, hasLength(1));
      await sub.cancel();
    });

    test('cancel stops delivery and releases the native stream', () async {
      final sub = WarpLink.onDeepLink.listen(events.add);
      await pump();
      await sub.cancel();
      await pump();
      expect(native.arrivalsCancels, 1);
      expect(native.arrivalsSink, isNull);
    });

    test('a listener added after cancel reconnects', () async {
      var sub = WarpLink.onDeepLink.listen((_) {});
      await pump();
      await sub.cancel();
      await pump();
      sub = WarpLink.onDeepLink.listen(events.add);
      await pump();
      native.arrive('https://aplnk.to/again');
      await pump();
      expect(events, hasLength(1));
      expect(native.arrivalsListens, 2);
      await sub.cancel();
    });

    test('skips a url that resolves to nothing', () async {
      native.resolver = (_) async => null;
      final sub = WarpLink.onDeepLink.listen(events.add);
      await pump();
      native.arrive('https://aplnk.to/one');
      await pump();
      expect(events, isEmpty);
      expect(native.claimed, hasLength(1));
      await sub.cancel();
    });

    test('waits for configure before it resolves anything', () async {
      await WarpLink.resetForTesting();
      native.calls.clear();
      final sub = WarpLink.onDeepLink.listen(events.add);
      native.arrive('https://aplnk.to/one');
      await pump();
      expect(native.resolveStarts, isEmpty);
      await WarpLink.configure(apiKey: validKey);
      await pump();
      expect(linkIds(events), ['one']);
      expect(native.callsTo(WarpLinkMethod.configure), hasLength(1));
      await sub.cancel();
    });
  });
}
