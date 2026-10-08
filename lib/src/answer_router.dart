import 'package:warplink_flutter/src/dispatch_state.dart';
import 'package:warplink_flutter/src/event_queue.dart';
import 'package:warplink_flutter/src/events.dart';
import 'package:warplink_flutter/src/held_answers.dart';

/// Gives each answer to the recipients that exist when it is routed.
///
/// An answer goes to `onLink` and to every `onDeepLink` subscriber that the
/// current state names and the answer's rules allow. With none, it is held for
/// the first recipient that appears. The router reads the state at the moment
/// of each call and never keeps a callback.
final class AnswerRouter {
  /// Creates a router. Subscribers receive answers through [emit].
  AnswerRouter(this._emit);

  final void Function(WarpLinkEvent event) _emit;
  final HeldAnswers _held = HeldAnswers();

  /// Whether [answer] has a recipient in [state] now.
  bool hasRecipient(Answer answer, DispatchState state) =>
      (state.automaticSink != null && answer.mayReachOnLink) ||
      (state.hasSubscribers && answer.mayReachSubscribers);

  /// Delivers [answer] to the recipients in [state], or holds it.
  void route(
    String arrivalId,
    Answer answer,
    DispatchState state,
    Outbox outbox,
  ) {
    if (hasRecipient(answer, state)) {
      _deliver(answer, state, outbox);
    } else {
      _held.add(arrivalId, answer);
    }
  }

  /// Delivers the oldest held answer that has a recipient in [state].
  ///
  /// Returns whether it found one. One answer per call, so a host callback
  /// that changes the state gets its event handled before the next answer.
  bool flushOne(DispatchState state, Outbox outbox) {
    final answer = _held.takeFirst((held) => hasRecipient(held, state));
    if (answer == null) {
      return false;
    }
    _deliver(answer, state, outbox);
    return true;
  }

  /// Removes and returns the oldest held launch answer `onLink` could take,
  /// for `getInitialDeepLink`.
  WarpLinkEvent? takeLaunch() =>
      _held.takeFirst((a) => a.isLaunch && a.mayReachOnLink)?.event;

  void _deliver(Answer answer, DispatchState state, Outbox outbox) {
    final onLink = state.automaticSink;
    if (state.hasSubscribers && answer.mayReachSubscribers) {
      outbox.add(() => _emit(answer.event));
    }
    if (onLink != null && answer.mayReachOnLink) {
      outbox.add(() => onLink(answer.event));
    }
  }
}
