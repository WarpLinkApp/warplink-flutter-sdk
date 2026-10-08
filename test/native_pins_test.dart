import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warplink_flutter/warplink_flutter.dart';

/// Every place that carries the release version must agree, so a package can
/// never ship pinned to native SDKs that report a different version.
void main() {
  String read(String path) => File(path).readAsStringSync();
  String capture(String path, RegExp pattern) {
    final match = pattern.firstMatch(read(path));
    expect(match, isNotNull, reason: '$path has no match for $pattern');
    return match!.group(1)!;
  }

  test('pubspec, constant, and CHANGELOG agree', () {
    final pubspec = capture(
      'pubspec.yaml',
      RegExp(r'^version: (\S+)', multiLine: true),
    );
    expect(warplinkFlutterVersion, pubspec);
    final changelog = capture(
      'CHANGELOG.md',
      RegExp(r'^## \[(\S+)\]', multiLine: true),
    );
    expect(changelog, pubspec);
  });

  test('the Android pin is the same version', () {
    final pin = capture(
      'android/build.gradle.kts',
      RegExp(r'implementation\("app\.warplink:sdk:([^"]+)"\)'),
    );
    expect(pin, warplinkFlutterVersion);
  });

  test('the iOS floor is the same version', () {
    final pin = capture(
      'ios/warplink_flutter/Package.swift',
      RegExp(r'warplink-ios-sdk\.git", from: "([^"]+)"'),
    );
    expect(pin, warplinkFlutterVersion);
  });

  test('the Android namespace and plugin class match the pubspec', () {
    final pubspec = read('pubspec.yaml');
    expect(pubspec, contains('package: app.warplink.flutter'));
    expect(pubspec, contains('pluginClass: WarpLinkFlutterPlugin'));
    expect(
      capture('android/build.gradle.kts', RegExp(r'namespace = "([^"]+)"')),
      'app.warplink.flutter',
    );
  });
}
