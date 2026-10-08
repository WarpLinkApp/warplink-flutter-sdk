import 'dart:async';

/// Fans one platform event stream out to many Dart listeners.
///
/// Each call to `EventChannel.receiveBroadcastStream` replaces the native
/// handler of the previous one. This wrapper opens the platform stream once,
/// while at least one Dart listener exists, and shares it.
final class SharedStream {
  /// Creates a shared view over [open], which must return a fresh platform
  /// stream on each call.
  SharedStream(Stream<Object?> Function() open) : _open = open {
    _controller = StreamController<Object?>.broadcast(
      onListen: _connect,
      onCancel: _disconnect,
    );
  }

  final Stream<Object?> Function() _open;
  late final StreamController<Object?> _controller;
  StreamSubscription<Object?>? _platform;

  /// The shared broadcast stream.
  Stream<Object?> get stream => _controller.stream;

  void _connect() {
    _platform = _open().listen(_controller.add, onError: _controller.addError);
  }

  Future<void> _disconnect() async {
    final platform = _platform;
    _platform = null;
    await platform?.cancel();
  }
}
