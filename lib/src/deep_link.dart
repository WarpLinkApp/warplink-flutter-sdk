import 'package:flutter/foundation.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/json_values.dart';
import 'package:warplink_flutter/src/match_type.dart';
import 'package:warplink_flutter/src/referral/attribution_evidence.dart';

/// A resolved WarpLink link.
@immutable
final class WarpLinkDeepLink extends AttributionEvidence {
  /// Creates a deep link value.
  const WarpLinkDeepLink({
    required this.linkId,
    required this.destination,
    required this.customParams,
    this.deepLinkUrl,
    this.isDeferred = false,
    this.matchType,
    this.matchConfidence,
    this.matchGuaranteed = false,
    super.attributionId,
    super.matchMethod,
    super.evidenceClass,
    super.replayState,
    super.capturedParams,
    super.tappedAt,
  });

  /// Decodes a platform channel map.
  ///
  /// An absent `matchGuaranteed` reads as `false`, so a native SDK that omits
  /// it can never make a probabilistic match look guaranteed. The evidence
  /// fields read as `null` (an empty map for `capturedParams`) when they are
  /// absent or unknown. Throws [WarpLinkDecodingException] when [raw] is not a
  /// map.
  factory WarpLinkDeepLink.fromMap(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      throw const WarpLinkDecodingException(
        'Native deep link payload is not a map',
      );
    }
    final custom = normalizeJson(raw['customParams']);
    final confidence = raw['matchConfidence'];
    final deepLinkUrl = raw['deepLinkUrl'];
    final evidence = AttributionEvidence.fromMap(raw);
    return WarpLinkDeepLink(
      linkId: raw['linkId']?.toString() ?? '',
      destination: raw['destination']?.toString() ?? '',
      deepLinkUrl: deepLinkUrl?.toString(),
      customParams: Map<String, Object?>.unmodifiable(
        custom is Map<String, Object?> ? custom : const <String, Object?>{},
      ),
      isDeferred: raw['isDeferred'] == true,
      matchType: MatchType.fromWire(raw['matchType']),
      matchConfidence: confidence is num ? confidence.toDouble() : null,
      matchGuaranteed: raw['matchGuaranteed'] == true,
      attributionId: evidence.attributionId,
      matchMethod: evidence.matchMethod,
      evidenceClass: evidence.evidenceClass,
      replayState: evidence.replayState,
      capturedParams: evidence.capturedParams,
      tappedAt: evidence.tappedAt,
    );
  }

  /// Identifier of the link in the dashboard.
  final String linkId;

  /// The web destination URL.
  final String destination;

  /// The in-app URL for this platform, or `null` when the link has none.
  final String? deepLinkUrl;

  /// Custom key and value pairs set on the link. Values are JSON values.
  final Map<String, Object?> customParams;

  /// `true` when the link came from the install attribution check rather than
  /// from a tap on a link in the running app.
  final bool isDeferred;

  /// How the link was matched, or `null` when it was not matched at all.
  final MatchType? matchType;

  /// Confidence of the match from 0 to 1, or `null` when not matched.
  final double? matchConfidence;

  /// `true` only when the match was deterministic.
  ///
  /// Use it, like [matchConfidence], to pick the destination to route to, not
  /// as a credential. A probabilistic match is an estimate from device signals,
  /// namely the IP address and language, with time zone when available.
  /// Use it to route the user, not to identify them. Authenticate the user and
  /// check authorization separately before showing private data or doing
  /// anything sensitive, guaranteed match or not.
  final bool matchGuaranteed;

  @override
  bool operator ==(Object other) =>
      other is WarpLinkDeepLink &&
      other.linkId == linkId &&
      other.destination == destination &&
      other.deepLinkUrl == deepLinkUrl &&
      jsonEquals(other.customParams, customParams) &&
      other.isDeferred == isDeferred &&
      other.matchType == matchType &&
      other.matchConfidence == matchConfidence &&
      other.matchGuaranteed == matchGuaranteed &&
      evidenceEquals(other);

  @override
  int get hashCode => Object.hash(
    linkId,
    destination,
    deepLinkUrl,
    jsonHash(customParams),
    isDeferred,
    matchType,
    matchConfidence,
    matchGuaranteed,
    evidenceHash,
  );

  @override
  String toString() =>
      'WarpLinkDeepLink(linkId: $linkId, destination: $destination, '
      'deepLinkUrl: $deepLinkUrl, customParams: $customParams, '
      'isDeferred: $isDeferred, matchType: $matchType, '
      'matchConfidence: $matchConfidence, '
      'matchGuaranteed: $matchGuaranteed, $evidenceText)';
}
