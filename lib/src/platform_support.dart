import 'package:flutter/foundation.dart';

/// Throws [UnsupportedError] unless the app runs on iOS or Android.
void requireSupportedPlatform() {
  final supported =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  if (!supported) {
    throw UnsupportedError('WarpLink supports iOS and Android only');
  }
}
