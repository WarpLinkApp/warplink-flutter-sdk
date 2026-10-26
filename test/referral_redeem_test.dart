import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';
import 'support/referral_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;
  final token = 'A' * 50;

  setUpNative((value) => native = value);

  PlatformException refusal(String code, String message) =>
      PlatformException(code: code, message: message);

  group('redeemInvitation', () {
    test('WL-S40 hands the pasted text to native untouched', () async {
      native.handlers[WarpLinkMethod.redeemInvitation] = (_) => matchMap();
      final paste = '  Join me: https://acme.aplnk.to/invite?t=$token \n';

      final link = await WarpLink.redeemInvitation(paste);

      expect(
        native.argumentsOf(WarpLinkMethod.redeemInvitation),
        <String, Object?>{'text': paste},
      );
      expect(link?.linkId, 'link-1');
      expect(link?.evidenceClass, EvidenceClass.exact);
    });

    test('WL-S40 leaves the shape and expiry decision to native', () async {
      native.handlers[WarpLinkMethod.redeemInvitation] = (_) => null;

      await WarpLink.redeemInvitation('not an invitation');
      await WarpLink.redeemInvitation('');

      expect(native.callsTo(WarpLinkMethod.redeemInvitation), hasLength(2));
    });

    test('WL-S41 text that is not an invitation resolves null', () async {
      native.handlers[WarpLinkMethod.redeemInvitation] = (_) => null;

      expect(await WarpLink.redeemInvitation('hello'), isNull);
    });

    test('WL-S42 a refusal keeps the reopen message, no retry', () async {
      native.handlers[WarpLinkMethod.redeemInvitation] = (_) =>
          throw refusal('E_SERVER_ERROR', reopenMessage);

      await expectLater(
        WarpLink.redeemInvitation(token),
        throwsA(
          isA<WarpLinkServerException>().having(
            (e) => e.message,
            'message',
            reopenMessage,
          ),
        ),
      );
      expect(native.callsTo(WarpLinkMethod.redeemInvitation), hasLength(1));
      expect(reopenMessage, isNot(contains('expired')));
    });

    test('WL-S42 a pending answer asks to try again in a minute', () async {
      native.handlers[WarpLinkMethod.redeemInvitation] = (_) =>
          throw refusal('E_SERVER_ERROR', pendingMessage);

      await expectLater(
        WarpLink.redeemInvitation(token),
        throwsA(
          isA<WarpLinkServerException>().having(
            (e) => e.message,
            'message',
            pendingMessage,
          ),
        ),
      );
      expect(native.callsTo(WarpLinkMethod.redeemInvitation), hasLength(1));
    });

    test('WL-S42 an unconfigured SDK reports not configured', () async {
      native.handlers[WarpLinkMethod.redeemInvitation] = (_) =>
          throw refusal('E_NOT_CONFIGURED', 'SDK not configured');

      await expectLater(
        WarpLink.redeemInvitation(token),
        throwsA(isA<WarpLinkNotConfiguredException>()),
      );
    });

    test(
      'WL-S44 a network failure surfaces once, Dart never retries',
      () async {
        native.handlers[WarpLinkMethod.redeemInvitation] = (_) =>
            throw refusal('E_NETWORK_ERROR', 'offline');

        await expectLater(
          WarpLink.redeemInvitation(token),
          throwsA(isA<WarpLinkNetworkException>()),
        );
        await pump();
        expect(native.callsTo(WarpLinkMethod.redeemInvitation), hasLength(1));
      },
    );

    test('WL-S44 one paste is one delivery to native', () async {
      native.handlers[WarpLinkMethod.redeemInvitation] = (_) => matchMap();

      await WarpLink.redeemInvitation(token);
      await pump();

      expect(native.callsTo(WarpLinkMethod.redeemInvitation), hasLength(1));
      expect(native.callsTo(WarpLinkMethod.handleDeepLink), isEmpty);
    });
  });
}
