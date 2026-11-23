import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

late FakeNative _native;
final _created = <Map<Object?, Object?>>[];

Map<String, Object?> _estimate() =>
    linkMap(linkId: 'estimate', matchGuaranteed: false)
      ..['isDeferred'] = true
      ..['matchType'] = 'probabilistic'
      ..['matchConfidence'] = 0.77;

Map<String, Object?> _exact() =>
    linkMap(linkId: 'exact')..['isDeferred'] = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<WarpLinkEvent> events;

  setUpNative((value) => _native = value);
  setUp(() {
    events = <WarpLinkEvent>[];
    _native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => false;
    _native.handlers[WarpLinkMethod.readTether] = (_) => {
      'kind': 'matched',
      'link': _exact(),
    };
  });

  Future<void> configureWith(Map<String, Object?>? deferred) async {
    _native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) => deferred;
    await WarpLink.configure(apiKey: validKey, onLink: events.add);
    await pump();
  }

  test(
    'readTether fires onLink again with the exact link after the estimate',
    () async {
      await configureWith(_estimate());
      expect(linkIds(events), ['estimate']);

      final result = await WarpLink.readTether();

      expect(result, isA<TetherMatched>());
      expect(linkIds(events), ['estimate', 'exact']);
      final exact = (events.last as LinkEvent).deepLink;
      expect(exact.matchType, MatchType.deterministic);
      expect(exact.matchGuaranteed, isTrue);
    },
  );

  test('does not deliver the same exact link twice', () async {
    await configureWith(_estimate());

    await WarpLink.readTether();
    await WarpLink.readTether();

    expect(linkIds(events), ['estimate', 'exact']);
  });

  test(
    'does not fire again for the same link id with different evidence',
    () async {
      await configureWith(_estimate()..['linkId'] = 'exact');

      await WarpLink.readTether();

      expect(linkIds(events), ['exact']);
    },
  );

  test('stays silent when onLink was given no earlier link', () async {
    await configureWith(null);

    await WarpLink.readTether();

    expect(events, isEmpty);
  });

  test('stays silent for a read that matched nothing', () async {
    await configureWith(_estimate());
    _native.handlers[WarpLinkMethod.readTether] = (_) => {'kind': 'unusable'};

    await WarpLink.readTether();

    expect(linkIds(events), ['estimate']);
  });

  test('keeps the read result when the host onLink throws', () async {
    final reported = <Object>[];
    var calls = 0;
    _native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) => _estimate();
    await WarpLink.configure(
      apiKey: validKey,
      onLink: (_) {
        calls++;
        if (calls > 1) {
          throw StateError('host bug');
        }
      },
    );
    await pump();

    await runZonedGuarded(
      () async => expect(await WarpLink.readTether(), isA<TetherMatched>()),
      (error, _) => reported.add(error),
    );

    expect(reported, hasLength(1));
  });

  group('paste button', () {
    setUp(() {
      _created.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, (
            call,
          ) async {
            if (call.method == 'create') {
              _created.add(call.arguments as Map<Object?, Object?>);
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform_views, null);
    });

    testWidgets('a tap that matches fires onLink again with the exact link', (
      tester,
    ) async {
      // `pump()` waits on real timers, so configure runs outside fake time.
      await tester.runAsync(() => configureWith(_estimate()));
      _native.handlers[WarpLinkMethod.isPasteButtonSupported] = (_) => true;
      final results = <TetherReadResult>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: WarpLinkPasteButton(onResult: results.add)),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'app.warplink/flutter/paste_button/${_created.last['id']}',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('onTether', {
                'result': {'kind': 'matched', 'link': _exact()},
              }),
            ),
            (_) {},
          );

      expect(results, hasLength(1));
      expect(linkIds(events), ['estimate', 'exact']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}
