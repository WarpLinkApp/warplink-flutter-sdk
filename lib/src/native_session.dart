import 'dart:async';
import 'dart:convert';

/// The native configuration this runtime asked for last, so a repeat of it is
/// a no-op.
///
/// Native Android and iOS ignore a configure with the same key and options and
/// keep the check that is running. Dart turns the native automatic check off
/// and runs the check itself, so it must not configure native or start a check
/// a second time for a session that already has them.
final class NativeSession {
  String? _signature;
  Future<void>? _live;

  /// Whether [arguments] are the live session's, so a configure is a repeat.
  bool isRepeat(Map<String, Object?> arguments) =>
      _live != null && _signature == jsonEncode(arguments);

  /// Runs [invoke] for [arguments] unless the live session already has them.
  ///
  /// A repeat that arrives while the first configure is still pending shares
  /// its result, failure included. A configure that fails builds no session,
  /// so the next call runs [invoke] again.
  Future<void> configure(
    Map<String, Object?> arguments,
    Future<void> Function() invoke,
  ) {
    final live = _live;
    if (live != null && isRepeat(arguments)) {
      return live;
    }
    final run = invoke();
    _signature = jsonEncode(arguments);
    _live = run;
    unawaited(
      run.then<void>(
        (_) {},
        onError: (Object _) {
          if (identical(_live, run)) {
            _live = null;
            _signature = null;
          }
        },
      ),
    );
    return run;
  }
}
