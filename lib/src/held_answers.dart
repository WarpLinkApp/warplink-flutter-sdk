import 'package:flutter/foundation.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/events.dart';
import 'package:warplink_flutter/src/tap_policy.dart';

/// How many answers are held before the oldest is dropped.
///
/// Matches the bound of the native ledger.
const int heldAnswerCap = 32;

/// One resolved answer and the rules for who may take it.
///
/// The rules do not name a recipient. Whoever exists when the answer is
/// delivered, or when it leaves the held queue, is checked against them then.
@immutable
final class Answer {
  /// Creates an answer for an arrival resolved under [tap], if it has one.
  const Answer(this.event, {required this.isLaunch, required this.tap});

  /// The resolved link or error.
  final WarpLinkEvent event;

  /// Whether the arrival launched the app. Subscribers never get a launch
  /// answer; `getInitialDeepLink` does.
  final bool isLaunch;

  /// The tap the arrival resolved under. Arrivals that were not planned as a
  /// resolve have none.
  final Tap? tap;

  /// Whether `onLink` may take the answer: it is not a repeat, not stale, and
  /// not the refusal of a foreign URL.
  bool get mayReachOnLink {
    final tap = this.tap;
    final failure = event;
    return tap != null &&
        !tap.isRepeat &&
        !tap.isSuperseded &&
        !(failure is ErrorEvent &&
            failure.error is WarpLinkInvalidUrlException);
  }

  /// Whether `onDeepLink` subscribers may take the answer: it is not a launch
  /// answer, and not an error that only a newer tap caused by cancelling the
  /// request. A superseded link still reaches them.
  bool get mayReachSubscribers => !isLaunch && !isSupersededError;

  /// Whether the answer is an error that only a newer tap caused by cancelling
  /// the request. No recipient ever takes it.
  bool get isSupersededError =>
      (tap?.isSuperseded ?? false) && event is ErrorEvent;

  /// Whether any recipient could ever take the answer.
  bool get isDeliverable => mayReachOnLink || mayReachSubscribers;
}

/// Answers whose delivery native granted while nobody could take them.
///
/// One bounded queue serves every kind of recipient: an automatic
/// configuration, a new `onDeepLink` subscriber, or `getInitialDeepLink` for a
/// launch answer. The oldest answer is dropped first when the queue is full.
final class HeldAnswers {
  final Map<String, Answer> _entries = <String, Answer>{};

  /// Holds [answer] for [arrivalId], unless no recipient could ever take it.
  void add(String arrivalId, Answer answer) {
    if (!answer.isDeliverable) {
      debugPrint('[WarpLink] dropped an undeliverable answer, $arrivalId');
      return;
    }
    _entries[arrivalId] = answer;
    if (_entries.length > heldAnswerCap) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest);
      debugPrint('[WarpLink] dropped the oldest held answer, arrival $oldest');
    }
  }

  /// Removes and returns the oldest answer [accepts], after dropping the ones
  /// that went stale while held.
  Answer? takeFirst(bool Function(Answer answer) accepts) {
    _entries.removeWhere((id, answer) {
      final isStale = !answer.isDeliverable;
      if (isStale) debugPrint('[WarpLink] dropped a stale held answer, $id');
      return isStale;
    });
    final id = _entries.entries
        .where((entry) => accepts(entry.value))
        .firstOrNull
        ?.key;
    return id == null ? null : _entries.remove(id);
  }
}
