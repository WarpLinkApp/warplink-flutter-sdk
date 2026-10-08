import 'package:flutter/foundation.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/match_type.dart';

/// The stored result of the install attribution check.
@immutable
final class AttributionResult {
  /// Creates an attribution result.
  const AttributionResult({
    required this.linkId,
    required this.matchType,
    required this.matchConfidence,
    required this.matchGuaranteed,
    required this.isDeferred,
  });

  /// Decodes a platform channel map.
  ///
  /// Throws [WarpLinkDecodingException] when [raw] is not a map, or when
  /// `matchType` or `matchConfidence` is missing or invalid.
  factory AttributionResult.fromMap(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      throw const WarpLinkDecodingException(
        'Native attribution payload is not a map',
      );
    }
    final matchType = MatchType.fromWire(raw['matchType']);
    final confidence = raw['matchConfidence'];
    if (matchType == null || confidence is! num) {
      throw const WarpLinkDecodingException(
        'Native attribution payload is missing matchType or matchConfidence',
      );
    }
    return AttributionResult(
      linkId: raw['linkId']?.toString() ?? '',
      matchType: matchType,
      matchConfidence: confidence.toDouble(),
      matchGuaranteed: raw['matchGuaranteed'] == true,
      isDeferred: raw['isDeferred'] == true,
    );
  }

  /// Identifier of the link that attributed the install.
  final String linkId;

  /// How the install was matched.
  final MatchType matchType;

  /// Confidence of the match from 0 to 1.
  final double matchConfidence;

  /// `true` only when the match was deterministic.
  ///
  /// Use it, like [matchConfidence], to pick the destination to route to, not
  /// as a credential. A probabilistic match is a best guess from a
  /// network-shaped fingerprint and can name the wrong user. Authenticate the
  /// user and check authorization separately before showing private data or
  /// doing anything sensitive, guaranteed match or not.
  final bool matchGuaranteed;

  /// `true` when the install was attributed by the deferred check.
  final bool isDeferred;

  @override
  bool operator ==(Object other) =>
      other is AttributionResult &&
      other.linkId == linkId &&
      other.matchType == matchType &&
      other.matchConfidence == matchConfidence &&
      other.matchGuaranteed == matchGuaranteed &&
      other.isDeferred == isDeferred;

  @override
  int get hashCode => Object.hash(
    linkId,
    matchType,
    matchConfidence,
    matchGuaranteed,
    isDeferred,
  );

  @override
  String toString() =>
      'AttributionResult(linkId: $linkId, matchType: $matchType, '
      'matchConfidence: $matchConfidence, '
      'matchGuaranteed: $matchGuaranteed, isDeferred: $isDeferred)';
}
