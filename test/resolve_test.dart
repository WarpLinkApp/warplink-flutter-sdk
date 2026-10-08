import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUpNative((value) => native = value);

  group('handleDeepLink', () {
    test('sends the url and decodes the link', () async {
      native.handlers[WarpLinkMethod.handleDeepLink] = (_) => linkMap();
      final link = await WarpLink.handleDeepLink('https://aplnk.to/abc');
      expect(native.argumentsOf(WarpLinkMethod.handleDeepLink), {
        'url': 'https://aplnk.to/abc',
      });
      expect(link!.linkId, 'link-1');
      expect(link.customParams['plan'], 'pro');
    });

    test('returns null when native resolves nothing', () async {
      native.handlers[WarpLinkMethod.handleDeepLink] = (_) => null;
      expect(await WarpLink.handleDeepLink('https://aplnk.to/abc'), isNull);
    });

    test('maps a native failure', () async {
      native.handlers[WarpLinkMethod.handleDeepLink] = (_) =>
          throw PlatformException(code: 'E_INVALID_URL', message: 'not ours');
      await expectLater(
        WarpLink.handleDeepLink('https://example.com/x'),
        throwsA(isA<WarpLinkInvalidUrlException>()),
      );
    });

    test('maps a password protected link', () async {
      native.handlers[WarpLinkMethod.handleDeepLink] = (_) =>
          throw PlatformException(
            code: 'E_PASSWORD_REQUIRED',
            message: 'locked',
          );
      await expectLater(
        WarpLink.handleDeepLink('https://aplnk.to/abc'),
        throwsA(isA<WarpLinkPasswordRequiredException>()),
      );
    });

    test('a non-WarpLink platform error becomes a server error', () async {
      native.handlers[WarpLinkMethod.handleDeepLink] = (_) =>
          throw PlatformException(code: 'weird', message: 'odd');
      await expectLater(
        WarpLink.handleDeepLink('https://aplnk.to/abc'),
        throwsA(isA<WarpLinkServerException>()),
      );
    });

    test('a malformed payload is a decoding error', () async {
      native.handlers[WarpLinkMethod.handleDeepLink] = (_) => 'nope';
      await expectLater(
        WarpLink.handleDeepLink('https://aplnk.to/abc'),
        throwsA(isA<WarpLinkDecodingException>()),
      );
    });
  });

  group('checkDeferredDeepLink', () {
    test('returns the link', () async {
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
          linkMap()..['isDeferred'] = true;
      final link = await WarpLink.checkDeferredDeepLink();
      expect(link!.isDeferred, isTrue);
    });

    test('returns null for a confirmed no-match', () async {
      native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) => null;
      expect(await WarpLink.checkDeferredDeepLink(), isNull);
    });

    for (final code in [
      'E_NOT_CONFIGURED',
      'E_NETWORK_ERROR',
      'E_SERVER_ERROR',
      'E_DECODING_ERROR',
    ]) {
      test('maps $code', () async {
        native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) =>
            throw PlatformException(code: code, message: 'm');
        await expectLater(
          WarpLink.checkDeferredDeepLink(),
          throwsA(
            isA<WarpLinkException>().having((e) => e.wireCode, 'code', code),
          ),
        );
      });
    }
  });

  group('getAttributionResult', () {
    test('decodes the result', () async {
      native.handlers[WarpLinkMethod.getAttributionResult] = (_) => {
        'linkId': 'l',
        'matchType': 'deterministic',
        'matchConfidence': 1.0,
        'matchGuaranteed': true,
        'isDeferred': true,
      };
      final result = await WarpLink.getAttributionResult();
      expect(result!.matchType, MatchType.deterministic);
      expect(result.matchGuaranteed, isTrue);
    });

    test('returns null when there is no match', () async {
      native.handlers[WarpLinkMethod.getAttributionResult] = (_) => null;
      expect(await WarpLink.getAttributionResult(), isNull);
    });

    test('a payload without matchType is a decoding error', () async {
      native.handlers[WarpLinkMethod.getAttributionResult] = (_) => {
        'linkId': 'l',
        'matchConfidence': 1.0,
      };
      await expectLater(
        WarpLink.getAttributionResult(),
        throwsA(isA<WarpLinkDecodingException>()),
      );
    });

    test('not configured rejects', () async {
      native.handlers[WarpLinkMethod.getAttributionResult] = (_) =>
          throw PlatformException(code: 'E_NOT_CONFIGURED', message: 'm');
      await expectLater(
        WarpLink.getAttributionResult(),
        throwsA(isA<WarpLinkNotConfiguredException>()),
      );
    });
  });
}
