import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

void main() {
  group('WarpLinkDeepLink.fromMap', () {
    test('decodes every field', () {
      final link = WarpLinkDeepLink.fromMap(linkMap());
      expect(link.linkId, 'link-1');
      expect(link.destination, 'https://example.com/a');
      expect(link.deepLinkUrl, 'myapp://a');
      expect(link.isDeferred, isFalse);
      expect(link.matchType, MatchType.deterministic);
      expect(link.matchConfidence, 1.0);
      expect(link.matchGuaranteed, isTrue);
    });

    test('reads an absent matchGuaranteed as false', () {
      final map = linkMap(matchGuaranteed: null)
        ..['matchType'] = 'probabilistic';
      final link = WarpLinkDeepLink.fromMap(map);
      expect(link.matchGuaranteed, isFalse);
      expect(link.matchType, MatchType.probabilistic);
    });

    test('only a true matchGuaranteed counts', () {
      expect(
        WarpLinkDeepLink.fromMap(
          linkMap(matchGuaranteed: 'true'),
        ).matchGuaranteed,
        isFalse,
      );
    });

    test('keeps nested JSON in customParams as plain collections', () {
      final params = WarpLinkDeepLink.fromMap(linkMap()).customParams;
      expect(params['plan'], 'pro');
      final nested = params['nested']! as Map<String, Object?>;
      expect(nested['tags'], <Object?>['a', 1, 2.5, null, true]);
    });

    test('customParams is read-only', () {
      final params = WarpLinkDeepLink.fromMap(linkMap()).customParams;
      expect(() => params['x'] = 1, throwsUnsupportedError);
    });

    test('tolerates absent optional fields', () {
      final link = WarpLinkDeepLink.fromMap(<Object?, Object?>{
        'linkId': 'a',
        'destination': 'b',
      });
      expect(link.deepLinkUrl, isNull);
      expect(link.customParams, isEmpty);
      expect(link.matchType, isNull);
      expect(link.matchConfidence, isNull);
      expect(link.isDeferred, isFalse);
    });

    test('maps an unknown matchType to null', () {
      final map = linkMap()..['matchType'] = 'fuzzy';
      expect(WarpLinkDeepLink.fromMap(map).matchType, isNull);
    });

    test('rejects a payload that is not a map', () {
      expect(
        () => WarpLinkDeepLink.fromMap('nope'),
        throwsA(isA<WarpLinkDecodingException>()),
      );
    });

    test('compares by value including nested params', () {
      final a = WarpLinkDeepLink.fromMap(linkMap());
      final b = WarpLinkDeepLink.fromMap(linkMap());
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(WarpLinkDeepLink.fromMap(linkMap(linkId: 'other'))));
      expect(a.toString(), contains('link-1'));
    });
  });

  group('AttributionResult.fromMap', () {
    Map<String, Object?> map() => <String, Object?>{
      'linkId': 'l',
      'matchType': 'probabilistic',
      'matchConfidence': 0.8,
      'matchGuaranteed': false,
      'isDeferred': true,
    };

    test('decodes every field', () {
      final result = AttributionResult.fromMap(map());
      expect(result.linkId, 'l');
      expect(result.matchType, MatchType.probabilistic);
      expect(result.matchConfidence, 0.8);
      expect(result.matchGuaranteed, isFalse);
      expect(result.isDeferred, isTrue);
      expect(result, AttributionResult.fromMap(map()));
      expect(result.hashCode, AttributionResult.fromMap(map()).hashCode);
    });

    test('accepts an integer confidence', () {
      final result = AttributionResult.fromMap(map()..['matchConfidence'] = 1);
      expect(result.matchConfidence, 1.0);
    });

    test('reads an absent matchGuaranteed as false', () {
      final result = AttributionResult.fromMap(
        map()..remove('matchGuaranteed'),
      );
      expect(result.matchGuaranteed, isFalse);
    });

    test('missing matchType is a decoding error', () {
      expect(
        () => AttributionResult.fromMap(map()..remove('matchType')),
        throwsA(isA<WarpLinkDecodingException>()),
      );
    });

    test('missing or non-numeric matchConfidence is a decoding error', () {
      expect(
        () => AttributionResult.fromMap(map()..remove('matchConfidence')),
        throwsA(isA<WarpLinkDecodingException>()),
      );
      expect(
        () => AttributionResult.fromMap(map()..['matchConfidence'] = '1'),
        throwsA(isA<WarpLinkDecodingException>()),
      );
    });

    test('a payload that is not a map is a decoding error', () {
      expect(
        () => AttributionResult.fromMap(3),
        throwsA(isA<WarpLinkDecodingException>()),
      );
    });
  });

  group('MatchType', () {
    test('round-trips the wire value', () {
      for (final type in MatchType.values) {
        expect(MatchType.fromWire(type.wireValue), type);
      }
      expect(MatchType.fromWire(null), isNull);
    });
  });

  group('WarpLinkEvent.fromMap', () {
    test('decodes a link event', () {
      final event = WarpLinkEvent.fromMap(<String, Object?>{
        'type': 'link',
        'link': linkMap(),
      });
      expect(event, isA<LinkEvent>());
      expect((event as LinkEvent).deepLink.linkId, 'link-1');
    });

    test('decodes an error event with a status code', () {
      final event = WarpLinkEvent.fromMap(<String, Object?>{
        'type': 'error',
        'code': 'E_SERVER_ERROR',
        'message': 'boom',
        'statusCode': 502,
      });
      final error = (event as ErrorEvent).error as WarpLinkServerException;
      expect(error.statusCode, 502);
      expect(error.message, 'boom');
    });

    test('a malformed payload becomes a decoding error event', () {
      for (final raw in <Object?>[
        null,
        'x',
        <String, Object?>{'type': 'what'},
        <String, Object?>{'type': 'link', 'link': 3},
      ]) {
        final event = WarpLinkEvent.fromMap(raw);
        expect((event as ErrorEvent).error, isA<WarpLinkDecodingException>());
      }
    });
  });
}
