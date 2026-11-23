import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

const int retryAtMs = 1800000000000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUpNative((value) => native = value);

  Future<DeferredCheckStatus> read(Object? reply) {
    native.handlers[WarpLinkMethod.getDeferredCheckStatus] = (_) => reply;
    return WarpLink.getDeferredCheckStatus();
  }

  group('WarpLink.getDeferredCheckStatus', () {
    // conformance: WL-S74
    for (final (wire, state) in <(String, DeferredCheckState)>[
      ('notChecked', DeferredCheckState.notChecked),
      ('checking', DeferredCheckState.checking),
      ('matched', DeferredCheckState.matched),
      ('noMatch', DeferredCheckState.noMatch),
      ('skippedOldInstall', DeferredCheckState.skippedOldInstall),
      ('stopped', DeferredCheckState.stopped),
    ]) {
      test('reads $wire with no retry time', () async {
        final status = await read(<String, Object?>{'state': wire});

        expect(status.state, state);
        expect(status.retryAt, isNull);
      });
    }

    // conformance: WL-S74
    test('reads waiting with the time the next check is allowed', () async {
      final status = await read(<String, Object?>{
        'state': 'waiting',
        'retryAt': retryAtMs,
      });

      expect(status.state, DeferredCheckState.waiting);
      expect(
        status.retryAt,
        DateTime.fromMillisecondsSinceEpoch(retryAtMs, isUtc: true),
      );
    });

    // conformance: WL-S74
    test('drops a retry time from a state that does not wait', () async {
      final status = await read(<String, Object?>{
        'state': 'matched',
        'retryAt': retryAtMs,
      });

      expect(status.retryAt, isNull);
    });

    for (final (name, reply) in <(String, Object?)>[
      ('an unknown state', <String, Object?>{'state': 'paused'}),
      ('a missing state', <String, Object?>{}),
      ('a waiting state with no retry time', {'state': 'waiting'}),
      (
        'a retry time that is not a number',
        {'state': 'waiting', 'retryAt': 'soon'},
      ),
      ('no payload', null),
    ]) {
      test('rejects $name as a decoding error', () async {
        await expectLater(
          read(reply),
          throwsA(isA<WarpLinkDecodingException>()),
        );
      });
    }

    test('passes a native failure on as a WarpLinkException', () async {
      native.handlers[WarpLinkMethod.getDeferredCheckStatus] = (_) =>
          throw PlatformException(code: 'E_SERVER_ERROR', message: 'no');

      await expectLater(
        WarpLink.getDeferredCheckStatus(),
        throwsA(isA<WarpLinkException>()),
      );
    });

    test('statuses with the same state and time are equal', () {
      expect(
        DeferredCheckStatus(state: DeferredCheckState.noMatch),
        DeferredCheckStatus(state: DeferredCheckState.noMatch),
      );
    });
  });
}
