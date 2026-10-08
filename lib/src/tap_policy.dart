/// Window inside which a second arrival of the same URL is a repeat.
///
/// Matches the longest native window. It never joins two feeds of one arrival:
/// that is done by the arrival id.
const Duration dedupeWindow = Duration(milliseconds: 1500);

/// One arrival that reached a native resolve, tracked until its answer.
final class Tap {
  Tap._({required this.isRepeat});

  /// Whether the arrival repeats a URL inside the dedupe window without
  /// standing in for the tap that owns the window. `onLink` never takes a
  /// repeat's answer; subscribers do.
  final bool isRepeat;

  /// Whether a newer link replaced this tap before its answer arrived.
  bool isSuperseded = false;

  /// Whether the answer arrived.
  bool isSettled = false;
}

/// Decides which arrivals resolve, which deliver, and which answers go stale.
///
/// Every decision uses only the order and timing of arrivals, never wall
/// clock. The caller passes the native monotonic time an arrival was recorded
/// at, so neither a slow classification nor a late replay can move an arrival
/// out of its window.
final class TapPolicy {
  String? _stampUrl;
  Duration? _stampAt;
  Tap? _owner;
  final List<Tap> _open = <Tap>[];

  /// Admits an arrival of the WarpLink link [url] recorded at [at].
  ///
  /// Returns `null` when the arrival must not resolve at all: a repeat inside
  /// the window with nobody asking for every event, or no consumer. Otherwise
  /// returns the claimed [Tap]. Claiming supersedes every older open tap,
  /// because the native resolve cancels the request still in flight.
  ///
  /// A repeat forced through for [hasSubscribers] is still a repeat for
  /// `onLink`, unless the tap that owns the dedupe stamp is open. That tap's
  /// answer is cancelled by this resolve, so the repeat stands in for it.
  Tap? admit(
    String url, {
    required Duration at,
    required bool autoEnabled,
    required bool hasSubscribers,
  }) {
    if (!autoEnabled) {
      return hasSubscribers ? _claim(isRepeat: false) : null;
    }
    if (!_isRepeat(url, at)) {
      final tap = _claim(isRepeat: false);
      _stampUrl = url;
      _stampAt = at;
      _owner = tap;
      return tap;
    }
    if (!hasSubscribers) {
      return null;
    }
    final owner = _owner;
    final takesOver = owner != null && !owner.isSettled;
    final tap = _claim(isRepeat: !takesOver);
    if (takesOver) {
      _owner = tap;
    }
    return tap;
  }

  /// Claims a tap for a manual resolve of a WarpLink link.
  ///
  /// The tap supersedes older open taps and never delivers to `onLink`. The
  /// manual call gets its own answer.
  Tap claimSilent() => _claim(isRepeat: false);

  /// Records that [tap] has its answer.
  ///
  /// A failed resolve of a real link releases the dedupe stamp it owns, so the
  /// user's own re-tap inside the window resolves again.
  void settle(Tap tap, {required bool failed}) {
    tap.isSettled = true;
    _open.remove(tap);
    if (failed && identical(_owner, tap)) {
      _clearStamp();
    }
  }

  /// Forgets the dedupe stamp, for a new configuration.
  void reset() => _clearStamp();

  bool _isRepeat(String url, Duration at) {
    final stampAt = _stampAt;
    if (url != _stampUrl || stampAt == null) {
      return false;
    }
    final elapsed = at - stampAt;
    return !elapsed.isNegative && elapsed < dedupeWindow;
  }

  Tap _claim({required bool isRepeat}) {
    for (final open in _open) {
      open.isSuperseded = true;
    }
    final tap = Tap._(isRepeat: isRepeat);
    _open.add(tap);
    return tap;
  }

  void _clearStamp() {
    _stampUrl = null;
    _stampAt = null;
    _owner = null;
  }
}
