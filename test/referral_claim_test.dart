import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';
import 'support/referral_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUpNative((value) => native = value);

  void answer(Object? value) =>
      native.handlers[WarpLinkMethod.claimReferral] = (_) => value;

  group('claimReferral', () {
    test('WL-S45 sends the installer id to native as written', () async {
      answer(claimMap());

      await WarpLink.claimReferral(' user-42 ');

      expect(
        native.argumentsOf(WarpLinkMethod.claimReferral),
        <String, Object?>{'installerId': ' user-42 '},
      );
    });

    test('WL-S45 a claimed answer keeps every field', () async {
      answer(claimMap());

      final claim = await WarpLink.claimReferral('user-42');

      expect(claim.status, ReferralClaimStatus.claimed);
      expect(claim.referralId, 'ref-1');
      expect(claim.linkUrl, 'https://acme.aplnk.to/invite');
      expect(claim.matchMethod, MatchMethod.installToken);
      expect(claim.isExact, isTrue);
      expect(claim.matchConfidence, 1.0);
      expect(claim.replayState, ReplayState.original);
    });

    test('WL-S45 a repeat claim returns the same answer', () async {
      answer(claimMap(overrides: {'replayState': 'replayed'}));

      final first = await WarpLink.claimReferral('user-42');
      final second = await WarpLink.claimReferral('user-42');

      expect(second, first);
      expect(second.hashCode, first.hashCode);
      expect(second.replayState, ReplayState.replayed);
    });

    test('WL-S45 status none is an answer, not an error', () async {
      answer(<String, Object?>{'status': 'none'});

      final claim = await WarpLink.claimReferral('user-42');

      expect(claim.status, ReferralClaimStatus.none);
      expect(claim.referralId, isNull);
      expect(claim.flags, isEmpty);
    });

    for (final raw in <Object?>[
      null,
      'claimed',
      <String, Object?>{},
      <String, Object?>{'status': 'credited'},
    ]) {
      test('WL-S45 an unreadable answer ($raw) reads as none', () async {
        answer(raw);

        final claim = await WarpLink.claimReferral('user-42');

        expect(claim.status, ReferralClaimStatus.none);
      });
    }

    test('WL-S45 a flagged claim keeps its flags', () async {
      answer(
        claimMap(
          overrides: {
            'status': 'flagged',
            'flags': <Object?>['outside_window', 7, 'self_referral'],
          },
        ),
      );

      final flagged = await WarpLink.claimReferral('user-42');

      expect(flagged.status, ReferralClaimStatus.flagged);
      expect(flagged.flags, <String>['outside_window', 'self_referral']);
      expect(() => flagged.flags.add('x'), throwsUnsupportedError);
    });

    test('WL-S45 an ignored claim names the referral that holds it', () async {
      answer(
        claimMap(overrides: {'status': 'ignored', 'duplicateOf': 'ref-0'}),
      );

      final ignored = await WarpLink.claimReferral('user-42');

      expect(ignored.status, ReferralClaimStatus.ignored);
      expect(ignored.duplicateOf, 'ref-0');
    });

    for (final code in <String>[
      'E_NETWORK_ERROR',
      'E_INVALID_API_KEY',
      'E_SERVER_ERROR',
    ]) {
      test('WL-S45 a $code failure is an error', () async {
        native.handlers[WarpLinkMethod.claimReferral] = (_) =>
            throw PlatformException(code: code, message: 'nope');

        await expectLater(
          WarpLink.claimReferral('user-42'),
          throwsA(
            isA<WarpLinkException>().having((e) => e.wireCode, 'code', code),
          ),
        );
      });
    }
  });
}
