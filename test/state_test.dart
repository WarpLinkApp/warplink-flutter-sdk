import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

import 'support/fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;

  setUpNative((value) => native = value);

  group('state queries', () {
    test('sdkVersion returns the native version', () async {
      native.handlers[WarpLinkMethod.getSdkVersion] = (_) => '1.1.0';
      expect(await WarpLink.sdkVersion(), '1.1.0');
      expect(warplinkFlutterVersion, '1.1.0');
    });

    test('sdkVersion rejects a non-string', () async {
      native.handlers[WarpLinkMethod.getSdkVersion] = (_) => null;
      await expectLater(
        WarpLink.sdkVersion(),
        throwsA(isA<WarpLinkDecodingException>()),
      );
    });

    test('isConfigured and isAttributionComplete', () async {
      native.handlers[WarpLinkMethod.isConfigured] = (_) => true;
      native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => false;
      expect(await WarpLink.isConfigured(), isTrue);
      expect(await WarpLink.isAttributionComplete(), isFalse);
    });

    test('a null answer reads as false', () async {
      native.handlers[WarpLinkMethod.isConfigured] = (_) => null;
      native.handlers[WarpLinkMethod.isAttributionComplete] = (_) => null;
      expect(await WarpLink.isConfigured(), isFalse);
      expect(await WarpLink.isAttributionComplete(), isFalse);
    });

    test('isWarpLinkUrl sends the url and returns the answer', () async {
      native.handlers[WarpLinkMethod.isWarpLinkUrl] = (args) =>
          args['url'] == 'https://aplnk.to/abc';
      expect(await WarpLink.isWarpLinkUrl('https://aplnk.to/abc'), isTrue);
      expect(await WarpLink.isWarpLinkUrl('https://example.com/x'), isFalse);
    });

    test('isWarpLinkUrl never rejects', () async {
      native.handlers[WarpLinkMethod.isWarpLinkUrl] = (_) =>
          throw PlatformException(code: 'E_INVALID_URL', message: 'm');
      expect(await WarpLink.isWarpLinkUrl('::::'), isFalse);
    });
  });

  group('getInitialDeepLink', () {
    test('takes the launch arrival once and resolves it', () async {
      native.arrive('https://aplnk.to/launch', id: 'launch', isLaunch: true);
      native.arrive('https://aplnk.to/warm');
      final first = await WarpLink.getInitialDeepLink();
      final second = await WarpLink.getInitialDeepLink();
      expect(first!.linkId, 'launch');
      expect(second, isNull);
      expect(native.resolveStarts, ['https://aplnk.to/launch']);
      expect(native.claimed, ['launch']);
      expect(native.callsTo(WarpLinkMethod.handleDeepLink), isEmpty);
    });

    test('two concurrent calls resolve the launch once', () async {
      native.arrive('https://aplnk.to/launch', isLaunch: true);
      final results = await Future.wait([
        WarpLink.getInitialDeepLink(),
        WarpLink.getInitialDeepLink(),
      ]);
      expect(results.whereType<WarpLinkDeepLink>(), hasLength(1));
      expect(native.resolveStarts, hasLength(1));
    });

    test('is null without a launch arrival', () async {
      native.arrive('https://aplnk.to/warm');
      expect(await WarpLink.getInitialDeepLink(), isNull);
    });

    test('is null while the automatic path owns the launch link', () async {
      native.arrive('https://aplnk.to/launch', isLaunch: true);
      final events = <WarpLinkEvent>[];
      await WarpLink.configure(apiKey: validKey, onLink: events.add);
      expect(await WarpLink.getInitialDeepLink(), isNull);
      await pump();
      expect(linkIds(events), ['launch']);
      expect(native.resolveStarts, hasLength(1));
    });

    test('propagates a resolve failure', () async {
      native.arrive('https://x.test/a', isLaunch: true);
      await expectLater(
        WarpLink.getInitialDeepLink(),
        throwsA(isA<WarpLinkInvalidUrlException>()),
      );
    });
  });

  group('platform support', () {
    test('web and desktop platforms throw UnsupportedError', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await expectLater(
        WarpLink.configure(apiKey: validKey),
        throwsUnsupportedError,
      );
      await expectLater(WarpLink.isConfigured(), throwsUnsupportedError);
      await expectLater(WarpLink.isWarpLinkUrl('x'), throwsUnsupportedError);
      expect(native.calls, isEmpty);
    });

    test('iOS is supported', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      native.handlers[WarpLinkMethod.isConfigured] = (_) => true;
      expect(await WarpLink.isConfigured(), isTrue);
    });
  });
}
