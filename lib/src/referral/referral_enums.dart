/// The closed sets of words the referral handoff uses on the channel.
///
/// Each parser returns `null` for a value this version does not know. An
/// unknown value is never read as a known one, so a newer native SDK cannot
/// make an estimate look exact.
library;

/// How an attribution was made.
enum MatchMethod {
  /// The install carried a token from the link tap.
  installToken('install_token'),

  /// The Play Install Referrer carried the link.
  androidReferrer('android_referrer'),

  /// The vendor id of the device matched an earlier install.
  deviceId('device_id'),

  /// The person opened a link inside the installed app.
  linkOpen('link_open'),

  /// Matched on an estimate from device signals: the IP address and language.
  probabilistic('probabilistic');

  const MatchMethod(this.wireValue);

  /// The value used on the platform channel.
  final String wireValue;

  /// Parses a channel value. Returns `null` for anything unrecognized.
  ///
  /// The server names the install referrer match `referrer`, and rows from
  /// before that name carry `android_referrer`. Both read as
  /// [androidReferrer].
  static MatchMethod? fromWire(Object? value) {
    if (value == _serverReferrer) {
      return androidReferrer;
    }
    for (final method in values) {
      if (method.wireValue == value) {
        return method;
      }
    }
    return null;
  }

  static const String _serverReferrer = 'referrer';
}

/// How strong the evidence behind an attribution is.
enum EvidenceClass {
  /// The evidence names the install exactly.
  exact('exact'),

  /// The evidence is an estimate.
  estimated('estimated'),

  /// The match came from a link id alone, as in SDKs before 1.2.0. Never read
  /// it as exact.
  legacyLink('legacy_link');

  const EvidenceClass(this.wireValue);

  /// The value used on the platform channel.
  final String wireValue;

  /// Parses a channel value. Returns `null` for anything unrecognized.
  static EvidenceClass? fromWire(Object? value) {
    for (final evidence in values) {
      if (evidence.wireValue == value) {
        return evidence;
      }
    }
    return null;
  }
}

/// Whether an answer is the first for its match or a repeat of it.
enum ReplayState {
  /// The first answer for the match.
  original('original'),

  /// A repeat of an earlier answer.
  replayed('replayed');

  const ReplayState(this.wireValue);

  /// The value used on the platform channel.
  final String wireValue;

  /// Parses a channel value. Returns `null` for anything unrecognized.
  static ReplayState? fromWire(Object? value) {
    for (final state in values) {
      if (state.wireValue == value) {
        return state;
      }
    }
    return null;
  }
}

/// The outcome of a referral claim.
enum ReferralClaimStatus {
  /// The referral was credited.
  claimed('claimed'),

  /// The referral was recorded and flagged for review.
  flagged('flagged'),

  /// Another referral already holds the credit.
  ignored('ignored'),

  /// There was no referral to credit. An ordinary answer, not an error.
  none('none');

  const ReferralClaimStatus(this.wireValue);

  /// The value used on the platform channel.
  final String wireValue;

  /// Parses a channel value. Returns `null` for anything unrecognized.
  static ReferralClaimStatus? fromWire(Object? value) {
    for (final status in values) {
      if (status.wireValue == value) {
        return status;
      }
    }
    return null;
  }
}
