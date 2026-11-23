import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source guards for the Tether handoff: what each platform may and may not
/// contain. The clipboard itself is only ever read by the native iOS SDK.
const _extensions = <String>{'.dart', '.kt', '.swift', '.java'};
const _swiftDir = 'ios/warplink_flutter/Sources';

List<File> _sources(String dir) => Directory(dir).existsSync()
    ? Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => _extensions.any(file.path.endsWith))
          .toList()
    : <File>[];

List<String> _containing(List<File> files, RegExp pattern) => files
    .where((file) => file.readAsStringSync().contains(pattern))
    .map((file) => file.path)
    .toList();

void main() {
  clipboardWriteTests();
  androidClipboardTests();
  installationIdTests();
  sdkPlatformTests();
  pasteControlTests();
}

void sdkPlatformTests() {
  test(
    'WL-S62 Dart and the bridges leave a pending code to the native SDK',
    () {
      final sources = [..._sources('lib'), ..._sources(_swiftDir)];
      final pending = RegExp(
        'retry_after|retryAfter|tether.*pending',
        caseSensitive: false,
      );

      expect(_containing(sources, pending), isEmpty);
    },
  );

  test(
    'WL-S58 the iOS plugin declares flutter before it configures the native SDK',
    () {
      final live = File('$_swiftDir/warplink_flutter/LiveWarpLinkNative.swift');
      final source = live.readAsStringSync();

      expect(source, contains('WarpLink.declareHostWrapper("flutter")'));
      expect(
        source.indexOf('declareHostWrapper'),
        lessThan(source.indexOf('WarpLink.configure(')),
      );
    },
  );
}

void clipboardWriteTests() {
  test('WL-S55 no SDK source writes to the clipboard', () {
    final all = [
      ..._sources('lib'),
      ..._sources('android/src/main'),
      ..._sources(_swiftDir),
    ];
    expect(all.length, greaterThan(10));

    final writes = RegExp(
      r'Clipboard\.setData|setPrimaryClip|\.string\s*=|\.strings\s*=|'
      r'UIPasteboard',
    );

    expect(_containing(all, writes), isEmpty);
  });
}

void androidClipboardTests() {
  test('WL-S56 the Android main source holds no clipboard type', () {
    final android = _sources('android/src/main');
    expect(android, isNotEmpty);

    final clipboard = RegExp('ClipboardManager|ClipData|CLIPBOARD_SERVICE');

    expect(_containing(android, clipboard), isEmpty);
  });
}

void installationIdTests() {
  final id = RegExp('installation_id|installationId', caseSensitive: false);

  test('WL-S58 no Dart source handles an installation id', () {
    final dart = _sources('lib');
    expect(dart, isNotEmpty);

    expect(_containing(dart, id), isEmpty);
  });

  test('WL-S58 no native bridge source builds an installation id', () {
    final native = [..._sources('android/src/main'), ..._sources(_swiftDir)];

    expect(_containing(native, id), isEmpty);
  });
}

void pasteControlTests() {
  test('WL-S57 the native paste control is a system control only', () {
    final swift = _sources(
      _swiftDir,
    ).where((file) => file.path.contains('PasteButton')).toList();
    expect(swift, isNotEmpty);

    expect(_containing(swift, RegExp('UIPasteControl')), isNotEmpty);
    final lookalike = RegExp(r'UIButton\(|UITapGestureRecognizer');

    expect(_containing(swift, lookalike), isEmpty);
  });

  test('WL-S57 every file that uses the control is gated by availability', () {
    final users = _sources(
      _swiftDir,
    ).where((file) => file.readAsStringSync().contains('UIPasteControl'));

    for (final file in users) {
      expect(
        file.readAsStringSync(),
        contains('@available(iOS 16'),
        reason: '${file.path} uses UIPasteControl without an iOS 16 gate',
      );
    }
  });
}
