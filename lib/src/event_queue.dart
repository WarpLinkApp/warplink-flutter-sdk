import 'dart:async';
import 'dart:collection';

/// Work a handler leaves for after it committed its state: user callbacks and
/// follow-up events.
final class Outbox {
  final List<void Function()> _effects = <void Function()>[];

  /// Runs [effect] once the handler returned, in the order added.
  void add(void Function() effect) => _effects.add(effect);
}

/// One input to the dispatcher. It reads and writes state synchronously and
/// never waits: a native call it starts comes back as a new event.
typedef Handler = void Function(Outbox outbox);

/// Runs handlers strictly one at a time, in the order they were posted.
///
/// A handler posted while another runs, for example by a host callback that
/// calls `configure`, waits for the running one, so no handler is ever
/// re-entered and every decision sees committed state.
final class EventQueue {
  final Queue<Handler> _pending = Queue<Handler>();
  bool _isDraining = false;
  bool _isClosed = false;

  /// Runs [handler] now, or after the running handler and everything queued
  /// before it. Does nothing once the queue is [close]d.
  void post(Handler handler) {
    if (_isClosed) {
      return;
    }
    _pending.add(handler);
    if (!_isDraining) {
      _drain();
    }
  }

  /// Queues [handler] like [post], but never runs it before the caller
  /// returns: an idle queue drains in a later microtask.
  ///
  /// For callers that must not deliver to a host callback from inside a
  /// framework call, such as a stream's `onListen`.
  void postDeferred(Handler handler) {
    if (_isClosed) {
      return;
    }
    _pending.add(handler);
    if (!_isDraining) {
      scheduleMicrotask(_drainIfIdle);
    }
  }

  /// Runs [read] as a handler and completes with its result.
  Future<T> ask<T>(T Function(Outbox outbox) read) {
    final answer = Completer<T>();
    post((outbox) => answer.complete(read(outbox)));
    return answer.future;
  }

  /// Drops what is queued and everything posted from now on.
  void close() {
    _isClosed = true;
    _pending.clear();
  }

  void _drainIfIdle() {
    if (!_isDraining) {
      _drain();
    }
  }

  void _drain() {
    _isDraining = true;
    try {
      while (_pending.isNotEmpty) {
        _run(_pending.removeFirst());
      }
    } finally {
      _isDraining = false;
    }
  }

  void _run(Handler handler) {
    final outbox = Outbox();
    _guard(() => handler(outbox));
    outbox._effects.forEach(_guard);
  }

  /// A failure in one handler or host callback must not stop the queue.
  void _guard(void Function() step) {
    try {
      step();
    } on Object catch (error, stack) {
      Zone.current.handleUncaughtError(error, stack);
    }
  }
}
