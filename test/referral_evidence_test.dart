import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';
import 'support/referral_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUpNative((value) => native = value);

  group('evidence fields', () {
    test('WL-S43 a match carries the six evidence fields', () async {
      native.handlers[WarpLinkMethod.handleDeepLink] = (_) => matchMap();

      final link = await WarpLink.handleDeepLink('https://acme.aplnk.to/i');

      expect(link?.attributionId, 'attr-1');
      expect(link?.matchMethod, MatchMethod.installToken);
      expect(link?.evidenceClass, EvidenceClass.exact);
      expect(link?.replayState, ReplayState.original);
      expect(link?.capturedParams, <String, Object?>{'utm_source': 'friend'});
      expect(link?.tappedAt, '2026-10-20T10:00:00Z');
    });

    test('WL-S43 the attribution result carries the same fields', () async {
      native.handlers[WarpLinkMethod.getAttributionResult] = (_) => matchMap();

      final result = await WarpLink.getAttributionResult();

      expect(result?.attributionId, 'attr-1');
      expect(result?.evidenceClass, EvidenceClass.exact);
      expect(result?.matchMethod, MatchMethod.installToken);
    });

    test('WL-S43 a payload from an older SDK decodes to safe defaults', () {
      final link = WarpLinkDeepLink.fromMap(linkMap());

      expect(link.attributionId, isNull);
      expect(link.matchMethod, isNull);
      expect(link.evidenceClass, isNull);
      expect(link.replayState, isNull);
      expect(link.capturedParams, isEmpty);
      expect(link.tappedAt, isNull);
    });

    test('WL-S43 a value this SDK does not know never drops the match', () {
      final link = WarpLinkDeepLink.fromMap(
        matchMap(
          overrides: {
            'matchMethod': 'telepathy',
            'evidenceClass': 'certain',
            'replayState': 'twice',
            'capturedParams': 'oops',
            'tappedAt': 5,
          },
        ),
      );

      expect(link.linkId, 'link-1');
      expect(link.matchMethod, isNull);
      expect(link.evidenceClass, isNull);
      expect(link.replayState, isNull);
      expect(link.capturedParams, isEmpty);
      expect(link.tappedAt, isNull);
    });

    test('WL-S43 equality and text include the evidence', () {
      final a = WarpLinkDeepLink.fromMap(matchMap());
      final b = WarpLinkDeepLink.fromMap(matchMap());
      final c = WarpLinkDeepLink.fromMap(
        matchMap(overrides: {'attributionId': 'attr-2'}),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a.toString(), contains('attr-1'));
      expect(() => a.capturedParams['x'] = 1, throwsUnsupportedError);
    });

    test('WL-S46 a link-id match stays legacy_link with link_open', () {
      final link = WarpLinkDeepLink.fromMap(
        matchMap(
          overrides: {
            'evidenceClass': 'legacy_link',
            'matchMethod': 'link_open',
          },
        ),
      );

      expect(link.evidenceClass, EvidenceClass.legacyLink);
      expect(link.matchMethod, MatchMethod.linkOpen);
      expect(link.evidenceClass, isNot(EvidenceClass.exact));
    });

    for (final (method, cls) in <(String, String)>[
      ('android_referrer', 'exact'),
      ('device_id', 'exact'),
      ('probabilistic', 'estimated'),
    ]) {
      test('WL-S46 a $method match keeps its own class $cls', () {
        final link = WarpLinkDeepLink.fromMap(
          matchMap(overrides: {'matchMethod': method, 'evidenceClass': cls}),
        );

        expect(link.matchMethod?.wireValue, method);
        expect(link.evidenceClass?.wireValue, cls);
      });
    }

    test('WL-S46 a missing class is never upgraded to exact', () {
      final link = WarpLinkDeepLink.fromMap(
        matchMap(overrides: {'evidenceClass': null}),
      );

      expect(link.evidenceClass, isNull);
    });
  });
}
