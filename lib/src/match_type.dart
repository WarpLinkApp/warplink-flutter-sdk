/// How an install or link click was matched to a link.
enum MatchType {
  /// Matched by a stable identifier (install referrer or vendor id).
  ///
  /// Confidence is always 1.0 and the match is guaranteed.
  deterministic('deterministic'),

  /// Matched by a device fingerprint. This is a best guess and can be wrong.
  probabilistic('probabilistic');

  const MatchType(this.wireValue);

  /// The lowercase value used on the platform channel.
  final String wireValue;

  /// Parses a channel value. Returns `null` for anything unrecognized.
  static MatchType? fromWire(Object? value) {
    for (final type in values) {
      if (type.wireValue == value) {
        return type;
      }
    }
    return null;
  }
}
