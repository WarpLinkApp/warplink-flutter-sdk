import 'package:flutter/foundation.dart';
import 'package:warplink_flutter/src/referral/referral_enums.dart';

/// The answer to `WarpLink.claimReferral`.
///
/// A status of [ReferralClaimStatus.none] is an ordinary answer, not an error:
/// there was no referral to credit.
@immutable
final class ReferralClaimResult {
  /// Creates a claim result.
  const ReferralClaimResult({
    required this.status,
    this.referralId,
    this.linkId,
    this.linkUrl,
    this.matchMethod,
    this.isExact = false,
    this.matchConfidence,
    this.flags = const <String>[],
    this.duplicateOf,
    this.updated = false,
    this.replayState,
  });

  /// Decodes a platform channel map.
  ///
  /// An answer this version cannot read, such as a missing map or an unknown
  /// status, reads as [ReferralClaimStatus.none]. A claim that cannot be read
  /// never reads as credited.
  factory ReferralClaimResult.fromMap(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      return const ReferralClaimResult(status: ReferralClaimStatus.none);
    }
    final status = ReferralClaimStatus.fromWire(raw['status']);
    if (status == null || status == ReferralClaimStatus.none) {
      return const ReferralClaimResult(status: ReferralClaimStatus.none);
    }
    final confidence = raw['matchConfidence'];
    final flags = raw['flags'];
    return ReferralClaimResult(
      status: status,
      referralId: _text(raw['referralId']),
      linkId: _text(raw['linkId']),
      linkUrl: _text(raw['linkUrl']),
      matchMethod: MatchMethod.fromWire(raw['matchMethod']),
      isExact: raw['isExact'] == true,
      matchConfidence: confidence is num ? confidence.toDouble() : null,
      flags: List<String>.unmodifiable(
        flags is List<Object?> ? flags.whereType<String>() : const <String>[],
      ),
      duplicateOf: _text(raw['duplicateOf']),
      updated: raw['updated'] == true,
      replayState: ReplayState.fromWire(raw['replayState']),
    );
  }

  static String? _text(Object? value) => value is String ? value : null;

  /// The outcome of the claim.
  final ReferralClaimStatus status;

  /// The id of the referral, or `null` when [status] is none.
  final String? referralId;

  /// The link the referral came from, or `null` when [status] is none.
  final String? linkId;

  /// The short URL of that link, or `null` when [status] is none.
  final String? linkUrl;

  /// How the referral was matched, or `null` when [status] is none.
  final MatchMethod? matchMethod;

  /// `true` when the match rests on exact evidence rather than an estimate.
  final bool isExact;

  /// The confidence of an estimated match, or `null` when there is none.
  final double? matchConfidence;

  /// Reasons the referral was flagged, for example `outside_window`.
  final List<String> flags;

  /// For [ReferralClaimStatus.ignored], the referral that already holds the
  /// credit.
  final String? duplicateOf;

  /// `true` when this call replaced an earlier estimate with an exact match.
  final bool updated;

  /// Whether this is the first answer for the claim or a repeat of it.
  final ReplayState? replayState;

  @override
  bool operator ==(Object other) =>
      other is ReferralClaimResult &&
      other.status == status &&
      other.referralId == referralId &&
      other.linkId == linkId &&
      other.linkUrl == linkUrl &&
      other.matchMethod == matchMethod &&
      other.isExact == isExact &&
      other.matchConfidence == matchConfidence &&
      listEquals(other.flags, flags) &&
      other.duplicateOf == duplicateOf &&
      other.updated == updated &&
      other.replayState == replayState;

  @override
  int get hashCode => Object.hash(
    status,
    referralId,
    linkId,
    linkUrl,
    matchMethod,
    isExact,
    matchConfidence,
    Object.hashAll(flags),
    duplicateOf,
    updated,
    replayState,
  );

  @override
  String toString() =>
      'ReferralClaimResult(status: $status, referralId: $referralId, '
      'linkId: $linkId, matchMethod: $matchMethod, isExact: $isExact, '
      'flags: $flags, duplicateOf: $duplicateOf, updated: $updated, '
      'replayState: $replayState)';
}
