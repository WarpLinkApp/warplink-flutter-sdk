import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';
import 'support/referral_fixtures.dart';

late FakeNative _native;

Future<Map<String, Object?>> _configured([TetherReadMode? mode]) async {
  if (mode == null) {
    await WarpLink.configure(apiKey: validKey);
  } else {
    await WarpLink.configure(apiKey: validKey, tetherReadMode: mode);
  }
  return _native.argumentsOf(WarpLinkMethod.configure);
}

/// Makes native answer `readTether` with [answer].
void _answers(Object? answer) {
  _native.handlers[WarpLinkMethod.readTether] = (_) => answer;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpNative((value) => _native = value);

  readModeTests();
  readTetherTests();
  unusableAnswerTests();
}

void readModeTests() {
  group('read modes', () {
    test('WL-S53 the default mode is the paste button', () async {
      expect((await _configured())['tetherReadMode'], 'paste_button');
    });

    for (final (mode, wire) in <(TetherReadMode, String)>[
      (TetherReadMode.pasteButton, 'paste_button'),
      (TetherReadMode.automatic, 'automatic'),
      (TetherReadMode.onCall, 'on_call'),
    ]) {
      test('WL-S53 the $wire mode reaches native as $wire', () async {
        expect((await _configured(mode))['tetherReadMode'], wire);
      });
    }

    test('WL-S53 configure alone never asks native for a read', () async {
      await _configured(TetherReadMode.onCall);

      expect(_native.callsTo(WarpLinkMethod.readTether), isEmpty);
    });

    test('WL-S53 a mode never turns an automatic link path back on', () async {
      final args = await _configured(TetherReadMode.automatic);

      expect(args['automaticDeepLinks'], false);
      expect(args['automaticDeferredDeepLinks'], false);
    });
  });
}

void readTetherTests() {
  group('readTether', () {
    test('WL-S54 sends no arguments, so no clipboard text crosses', () async {
      _answers({'kind': 'noCode', 'reason': 'clipboard_empty'});

      await WarpLink.readTether();

      final calls = _native.callsTo(WarpLinkMethod.readTether);
      expect(calls, hasLength(1));
      expect(calls.single.arguments, isNull);
    });

    test('WL-S53 a matched read returns the link', () async {
      _answers({'kind': 'matched', 'link': matchMap()});

      final matched = await WarpLink.readTether() as TetherMatched;

      expect(matched.link.linkId, 'link-1');
      expect(matched.link.matchMethod, MatchMethod.installToken);
    });

    for (final reason in TetherMissReason.values) {
      test('WL-S59 a miss reports ${reason.wireValue}', () async {
        _answers({'kind': 'noCode', 'reason': reason.wireValue});

        expect(await WarpLink.readTether(), TetherNoCode(reason));
      });
    }

    test('WL-S59 a reason this version does not know reads as null', () async {
      _answers({'kind': 'noCode', 'reason': 'a_future_reason'});

      expect(await WarpLink.readTether(), const TetherNoCode(null));
    });

    test('WL-S56 an Android read has no reason and no link', () async {
      _answers({'kind': 'noCode', 'reason': null});

      expect(await WarpLink.readTether(), const TetherNoCode(null));
    });
  });
}

void unusableAnswerTests() {
  group('answers Dart cannot use', () {
    final unreadable = <String, Object?>{
      'a non-map answer': 'matched',
      'an unknown kind': <String, Object?>{'kind': 'brand_new'},
      'a matched answer without a link': <String, Object?>{'kind': 'matched'},
      'a matched answer with a link that is not a map': <String, Object?>{
        'kind': 'matched',
        'link': 'x',
      },
      'a null answer': null,
    };

    unreadable.forEach((name, answer) {
      test('WL-S60 $name is unusable, never an error', () async {
        _answers(answer);

        expect(await WarpLink.readTether(), const TetherUnusable());
      });
    });

    test('WL-S60 a code that led nowhere is unusable', () async {
      _answers({'kind': 'unusable'});

      expect(await WarpLink.readTether(), const TetherUnusable());
    });

    test('WL-S60 a native failure throws its mapped error', () async {
      _native.handlers[WarpLinkMethod.readTether] = (_) =>
          throw PlatformException(
            code: 'E_NOT_CONFIGURED',
            message: 'not configured',
          );

      await expectLater(
        WarpLink.readTether(),
        throwsA(isA<WarpLinkNotConfiguredException>()),
      );
    });

    test('WL-S60 a failed read leaves the next method running', () async {
      _native.handlers[WarpLinkMethod.readTether] = (_) =>
          throw PlatformException(code: 'E_NETWORK_ERROR', message: 'offline');
      _native.handlers[WarpLinkMethod.checkDeferredDeepLink] = (_) => linkMap();
      await _configured(TetherReadMode.onCall);

      await expectLater(
        WarpLink.readTether(),
        throwsA(isA<WarpLinkNetworkException>()),
      );
      final link = await WarpLink.checkDeferredDeepLink();

      expect(link?.linkId, 'link-1');
    });
  });
}
