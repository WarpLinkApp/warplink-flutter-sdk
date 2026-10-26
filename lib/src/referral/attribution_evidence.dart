import 'package:flutter/foundation.dart';
import 'package:warplink_flutter/src/json_values.dart';
import 'package:warplink_flutter/src/referral/referral_enums.dart';

/// The evidence behind a match, shared by [WarpLinkDeepLink] and
/// [AttributionResult].
///
/// Every field has a safe reading when the native SDK omits it or sends a value
/// this version does not know: `null`, or an empty map. A missing
/// [evidenceClass] is never read as exact.
@immutable
base class AttributionEvidence {
  /// Creates the evidence of a match.
  const AttributionEvidence({
    this.attributionId,
    this.matchMethod,
    this.evidenceClass,
    this.replayState,
    this.capturedParams = const <String, Object?>{},
    this.tappedAt,
  });

  /// Decodes the evidence fields of a platform channel map.
  factory AttributionEvidence.fromMap(Map<Object?, Object?> raw) {
    final captured = normalizeJson(raw['capturedParams']);
    final attributionId = raw['attributionId'];
    final tappedAt = raw['tappedAt'];
    return AttributionEvidence(
      attributionId: attributionId is String ? attributionId : null,
      matchMethod: MatchMethod.fromWire(raw['matchMethod']),
      evidenceClass: EvidenceClass.fromWire(raw['evidenceClass']),
      replayState: ReplayState.fromWire(raw['replayState']),
      capturedParams: Map<String, Object?>.unmodifiable(
        captured is Map<String, Object?> ? captured : const <String, Object?>{},
      ),
      tappedAt: tappedAt is String ? tappedAt : null,
    );
  }

  /// The stable id of the attribution. The same on every replay of the match.
  /// `null` when the link did not come from an attribution.
  final String? attributionId;

  /// How the match was made, or `null` when the source is not known.
  final MatchMethod? matchMethod;

  /// How strong the evidence is, or `null` when the source is not known.
  final EvidenceClass? evidenceClass;

  /// Whether this is the first answer for the match or a repeat of it.
  final ReplayState? replayState;

  /// The link parameters the server captured at the tap. Empty when none.
  final Map<String, Object?> capturedParams;

  /// When the link was tapped, as the ISO 8601 text the server sent, or
  /// `null` when the server did not record a tap.
  final String? tappedAt;

  /// Whether [other] carries the same evidence.
  @protected
  bool evidenceEquals(AttributionEvidence other) =>
      other.attributionId == attributionId &&
      other.matchMethod == matchMethod &&
      other.evidenceClass == evidenceClass &&
      other.replayState == replayState &&
      jsonEquals(other.capturedParams, capturedParams) &&
      other.tappedAt == tappedAt;

  /// A hash code that agrees with [evidenceEquals].
  @protected
  int get evidenceHash => Object.hash(
    attributionId,
    matchMethod,
    evidenceClass,
    replayState,
    jsonHash(capturedParams),
    tappedAt,
  );

  /// The evidence as text, for `toString`.
  @protected
  String get evidenceText =>
      'attributionId: $attributionId, matchMethod: $matchMethod, '
      'evidenceClass: $evidenceClass, replayState: $replayState, '
      'capturedParams: $capturedParams, tappedAt: $tappedAt';
}
