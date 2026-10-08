import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

void main() {
  const expected = <String, Type>{
    'E_NOT_CONFIGURED': WarpLinkNotConfiguredException,
    'E_INVALID_API_KEY_FORMAT': WarpLinkInvalidApiKeyFormatException,
    'E_INVALID_API_KEY': WarpLinkInvalidApiKeyException,
    'E_NETWORK_ERROR': WarpLinkNetworkException,
    'E_SERVER_ERROR': WarpLinkServerException,
    'E_INVALID_URL': WarpLinkInvalidUrlException,
    'E_LINK_NOT_FOUND': WarpLinkLinkNotFoundException,
    'E_PASSWORD_REQUIRED': WarpLinkPasswordRequiredException,
    'E_DECODING_ERROR': WarpLinkDecodingException,
  };

  test('there are nine error codes', () {
    expect(WarpLinkErrorCode.values, hasLength(9));
    expect(
      WarpLinkErrorCode.values.map((code) => code.wireCode),
      unorderedEquals(expected.keys),
    );
  });

  group('PlatformException mapping', () {
    for (final entry in expected.entries) {
      test('${entry.key} maps to ${entry.value}', () {
        final error = mapPlatformException(
          PlatformException(code: entry.key, message: 'native text'),
        );
        expect(error.runtimeType, entry.value);
        expect(error.wireCode, entry.key);
        expect(error.code, WarpLinkErrorCode.fromWire(entry.key));
        expect(error.message, 'native text');
        expect(error.toString(), contains(entry.key));
      });
    }

    test('an unknown code becomes a server error', () {
      final error = mapPlatformException(
        PlatformException(code: 'E_WHAT', message: 'odd'),
      );
      expect(error, isA<WarpLinkServerException>());
      expect(error.message, 'odd');
    });

    test('a plain native error code becomes a server error', () {
      final error = mapPlatformException(PlatformException(code: 'error'));
      expect(error, isA<WarpLinkServerException>());
      expect(error.message, isNotEmpty);
    });

    test('a server error carries the status code from details', () {
      final error = mapPlatformException(
        PlatformException(
          code: 'E_SERVER_ERROR',
          message: 'bad gateway',
          details: <String, Object?>{'statusCode': 502},
        ),
      );
      expect((error as WarpLinkServerException).statusCode, 502);
    });

    test('details without a status code leave it null', () {
      for (final details in <Object?>[null, 'x', <String, Object?>{}]) {
        final error = mapPlatformException(
          PlatformException(code: 'E_SERVER_ERROR', details: details),
        );
        expect((error as WarpLinkServerException).statusCode, isNull);
      }
    });

    test('a missing message falls back to the code name', () {
      final error = mapPlatformException(
        PlatformException(code: 'E_NOT_CONFIGURED'),
      );
      expect(error.message, 'notConfigured');
    });
  });

  test('exceptions are exhaustive in a switch', () {
    const WarpLinkException error = WarpLinkNetworkException('x');
    final label = switch (error) {
      WarpLinkNotConfiguredException() => 'a',
      WarpLinkInvalidApiKeyFormatException() => 'b',
      WarpLinkInvalidApiKeyException() => 'c',
      WarpLinkNetworkException() => 'd',
      WarpLinkServerException() => 'e',
      WarpLinkInvalidUrlException() => 'f',
      WarpLinkLinkNotFoundException() => 'g',
      WarpLinkPasswordRequiredException() => 'h',
      WarpLinkDecodingException() => 'i',
    };
    expect(label, 'd');
  });
}
