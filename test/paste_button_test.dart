import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

late FakeNative _native;
final _created = <Map<Object?, Object?>>[];
final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);

Widget _button({
  ValueChanged<TetherReadResult>? onResult,
  ValueChanged<WarpLinkException>? onError,
  PasteButtonCornerStyle corner = PasteButtonCornerStyle.system,
}) => MaterialApp(
  home: Center(
    child: WarpLinkPasteButton(
      onResult: onResult ?? (_) {},
      onError: onError,
      cornerStyle: corner,
    ),
  ),
);

/// Delivers [body] the way the native control reports a tap.
Future<void> _sendFromNative(Object? body) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'app.warplink/flutter/paste_button/${_created.last['id']}',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onTether', body),
        ),
        (_) {},
      );
}

/// Shows [widget] on a device whose native side supports the paste control.
Future<void> _pumpSupported(WidgetTester tester, Widget widget) async {
  _native.handlers[WarpLinkMethod.isPasteButtonSupported] = (_) => true;
  await tester.pumpWidget(widget);
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void _mockPlatformViews() {
  setUp(() {
    _created.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpNative((value) => _native = value);
  _mockPlatformViews();

  unsupportedTests();
  tapResultTests();
  recreationTests();
}

void unsupportedTests() {
  testWidgets('WL-S57 takes no space on Android and asks nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_button());

    expect(tester.getSize(find.byType(WarpLinkPasteButton)), Size.zero);
    expect(_native.callsTo(WarpLinkMethod.isPasteButtonSupported), isEmpty);
  });

  testWidgets('WL-S57 takes no space on iOS when native says unsupported', (
    tester,
  ) async {
    _native.handlers[WarpLinkMethod.isPasteButtonSupported] = (_) => false;

    await tester.pumpWidget(_button());
    await tester.pump();

    expect(tester.getSize(find.byType(WarpLinkPasteButton)), Size.zero);
    expect(_created, isEmpty);
  }, variant: _ios);

  testWidgets('WL-S57 a failed support check takes no space', (tester) async {
    _native.handlers[WarpLinkMethod.isPasteButtonSupported] = (_) =>
        throw PlatformException(code: 'E_NOT_CONFIGURED');

    await tester.pumpWidget(_button());
    await tester.pump();

    expect(tester.getSize(find.byType(WarpLinkPasteButton)), Size.zero);
  }, variant: _ios);
}

void tapResultTests() {
  group('on iOS 16 and later', () {
    testWidgets('WL-S53 a tap result reaches onResult', (tester) async {
      final results = <TetherReadResult>[];
      await _pumpSupported(tester, _button(onResult: results.add));

      await _sendFromNative(<String, Object?>{
        'result': <String, Object?>{'kind': 'noCode', 'reason': 'expired'},
      });

      expect(results, [const TetherNoCode(TetherMissReason.expired)]);
      expect(_created.single['viewType'], 'app.warplink/flutter/paste_button');
    }, variant: _ios);

    testWidgets('WL-S60 a tap failure reaches onError, not onResult', (
      tester,
    ) async {
      final results = <TetherReadResult>[];
      final errors = <WarpLinkException>[];
      await _pumpSupported(
        tester,
        _button(onResult: results.add, onError: errors.add),
      );

      await _sendFromNative(<String, Object?>{
        'error': <String, Object?>{
          'code': 'E_NETWORK_ERROR',
          'message': 'offline',
        },
      });

      expect(results, isEmpty);
      expect(errors.single, isA<WarpLinkNetworkException>());
    }, variant: _ios);

    testWidgets('WL-S60 an unreadable body is unusable, not a crash', (
      tester,
    ) async {
      final results = <TetherReadResult>[];
      await _pumpSupported(tester, _button(onResult: results.add));

      await _sendFromNative('nonsense');

      expect(results, [const TetherUnusable()]);
    }, variant: _ios);
  });
}

void recreationTests() {
  testWidgets('a new corner style recreates the native control', (
    tester,
  ) async {
    await _pumpSupported(tester, _button());
    await tester.pumpWidget(_button(corner: PasteButtonCornerStyle.capsule));
    await tester.pump();

    expect(_created, hasLength(2));
  }, variant: _ios);
}
