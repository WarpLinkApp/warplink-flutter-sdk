import 'dart:async';

import 'package:warplink_flutter/src/events.dart';

/// The broadcast stream behind `WarpLink.onDeepLink`.
///
/// Tells its owner when the first listener attaches and when the last one
/// leaves, so the native listener lives exactly as long as someone wants it.
///
/// Delivery is synchronous: a listener runs inside [emit], in the dispatcher's
/// post-commit phase. A listener that reconfigures or cancels therefore posts
/// its event before the next held answer is dispatched. A synchronous
/// controller must not deliver from `onListen`, so [onFirstListen] must only
/// queue work and never deliver before it returns.
final class SubscriberFeed {
  /// Creates a feed. [onFirstListen] and [onLastCancel] fire as listeners come
  /// and go.
  SubscriberFeed({
    required void Function() onFirstListen,
    required void Function() onLastCancel,
  }) {
    _controller = StreamController<WarpLinkEvent>.broadcast(
      sync: true,
      onListen: () {
        hasListeners = true;
        onFirstListen();
      },
      onCancel: () {
        hasListeners = false;
        onLastCancel();
      },
    );
  }

  late final StreamController<WarpLinkEvent> _controller;

  /// Whether at least one listener is attached.
  bool hasListeners = false;

  /// The events.
  Stream<WarpLinkEvent> get stream => _controller.stream;

  /// Pushes [event] to every listener. Does nothing after [close].
  void emit(WarpLinkEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// Ends the stream for every listener.
  Future<void> close() => _controller.close();
}
