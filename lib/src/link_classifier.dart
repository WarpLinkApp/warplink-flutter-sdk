import 'dart:async';

import 'package:warplink_flutter/src/channel_adapter.dart';
import 'package:warplink_flutter/src/errors.dart';

/// Longest a classification may take.
///
/// Classification is a read of a cached domain set, so a slow answer means a
/// stuck native module. Waiting longer would hold every later arrival.
const Duration classifyCeiling = Duration(seconds: 2);

/// Asks native whether a URL is a WarpLink link.
///
/// Only native knows: the link domain set is `aplnk.to`, the domains the host
/// declared, and the list the server returned. Dart must decide this before a
/// URL claims delivery, supersedes anything, or stamps the dedupe window.
final class LinkClassifier {
  /// Creates a classifier that asks through [adapter].
  const LinkClassifier(this._adapter);

  final ChannelAdapter _adapter;

  /// Whether [url] is a WarpLink link.
  ///
  /// Fails open: when native fails or does not answer within
  /// [classifyCeiling], the answer is `true`. Answering `false` would silence
  /// every link on a device whose classification is broken, and a foreign URL
  /// that gets through is refused by its own resolve with `invalidUrl`.
  Future<bool> isWarpLink(String url) async {
    try {
      return await _adapter
          .isWarpLinkUrl(url)
          .timeout(classifyCeiling, onTimeout: () => true);
    } on WarpLinkException {
      return true;
    }
  }
}
