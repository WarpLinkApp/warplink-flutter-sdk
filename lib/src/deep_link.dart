import 'package:flutter/foundation.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/json_values.dart';
import 'package:warplink_flutter/src/match_type.dart';

/// A resolved WarpLink link.
@immutable
final class WarpLinkDeepLink {
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
  });

  /// Decodes a platform channel map.
  ///
  /// An absent `matchGuaranteed` reads as `false`, so a native SDK that omits
  /// it can never make a probabilistic match look guaranteed. Throws
  /// [WarpLinkDecodingException] when [raw] is not a map.
  factory WarpLinkDeepLink.fromMap(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      throw const WarpLinkDecodingException(
        'Native deep link payload is not a map',
      );
    }
    final custom = normalizeJson(raw['customParams']);
    final confidence = raw['matchConfidence'];
    final deepLinkUrl = raw['deepLinkUrl'];
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
  /// as a credential. A probabilistic match is a best guess from a
  /// network-shaped fingerprint and can name the wrong user. Authenticate the
  /// user and check authorization separately before showing private data or
  /// doing anything sensitive, guaranteed match or not.
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
      other.matchGuaranteed == matchGuaranteed;

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
  );

  @override
  String toString() =>
      'WarpLinkDeepLink(linkId: $linkId, destination: $destination, '
      'deepLinkUrl: $deepLinkUrl, customParams: $customParams, '
      'isDeferred: $isDeferred, matchType: $matchType, '
      'matchConfidence: $matchConfidence, '
      'matchGuaranteed: $matchGuaranteed)';
}
