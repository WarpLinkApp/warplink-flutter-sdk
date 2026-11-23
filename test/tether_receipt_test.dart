import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

late FakeNative _native;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpNative((value) => _native = value);

  testCodeReadTests();
  lastReceiptTests();
}

void testCodeReadTests() {
  group('test code reads', () {
    test('WL-S61 a test code returns its receipt and no link', () async {
      _native.handlers[WarpLinkMethod.readTether] = (_) => <String, Object?>{
        'kind': 'test',
        'receipt': 'rcpt-1',
      };

      expect(await WarpLink.readTether(), const TetherTest('rcpt-1'));
    });

    for (final receipt in <Object?>[null, '', 7]) {
      test('WL-S61 a receipt of $receipt reads as null', () async {
        _native.handlers[WarpLinkMethod.readTether] = (_) => <String, Object?>{
          'kind': 'test',
          'receipt': receipt,
        };

        expect(await WarpLink.readTether(), const TetherTest(null));
      });
    }
  });
}

void lastReceiptTests() {
  group('the last receipt', () {
    test('WL-S61 the last receipt comes from native', () async {
      _native.handlers[WarpLinkMethod.getTetherTestReceipt] = (_) => 'rcpt-2';

      expect(await WarpLink.lastTetherTestReceipt(), 'rcpt-2');
    });

    test('WL-S61 no receipt, or an empty one, reads as null', () async {
      _native.handlers[WarpLinkMethod.getTetherTestReceipt] = (_) => null;
      expect(await WarpLink.lastTetherTestReceipt(), isNull);

      _native.handlers[WarpLinkMethod.getTetherTestReceipt] = (_) => '';
      expect(await WarpLink.lastTetherTestReceipt(), isNull);
    });

    test('WL-S61 a failure reading the receipt throws', () async {
      _native.handlers[WarpLinkMethod.getTetherTestReceipt] = (_) =>
          throw PlatformException(code: 'E_NOT_CONFIGURED', message: 'no');

      await expectLater(
        WarpLink.lastTetherTestReceipt(),
        throwsA(isA<WarpLinkException>()),
      );
    });
  });
}
