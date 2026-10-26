import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _clipboard = RegExp(
  'UIPasteboard|ClipboardManager|ClipData|Clipboard\\.getData|'
  'Clipboard\\.hasStrings',
);

const List<String> _sourceDirs = <String>[
  'lib',
  'android/src/main',
  'ios/warplink_flutter/Sources',
];

const Set<String> _extensions = <String>{'.dart', '.kt', '.swift', '.java'};

void main() {
  test('WL-S47 no SDK source reads the system clipboard', () {
    final files = _sourceDirs
        .map(Directory.new)
        .where((dir) => dir.existsSync())
        .expand((dir) => dir.listSync(recursive: true))
        .whereType<File>()
        .where((file) => _extensions.any(file.path.endsWith))
        .toList();
    expect(files.length, greaterThan(10));

    final offenders = files
        .where((file) => file.readAsStringSync().contains(_clipboard))
        .map((file) => file.path)
        .toList();

    expect(offenders, isEmpty);
  });
}
