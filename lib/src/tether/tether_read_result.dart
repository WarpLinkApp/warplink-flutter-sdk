import 'package:flutter/foundation.dart';
import 'package:warplink_flutter/src/deep_link.dart';
import 'package:warplink_flutter/src/tether/tether_enums.dart';

/// What a Tether read ended on. A failure is a thrown `WarpLinkException`,
/// never one of these.
///
/// Use a `switch` to handle every case.
@immutable
sealed class TetherReadResult {
  const TetherReadResult();

  /// Decodes a platform channel map.
  ///
  /// A payload this version cannot read is [TetherUnusable], never an error,
  /// so a bridge mismatch cannot block onboarding. A reason this version does
  /// not know reads as `null`.
  factory TetherReadResult.fromMap(Object? raw) {
    if (raw is! Map<Object?, Object?>) {
      return const TetherUnusable();
    }
    return switch (raw['kind']) {
      'matched' when raw['link'] is Map<Object?, Object?> => TetherMatched(
        WarpLinkDeepLink.fromMap(raw['link']),
      ),
      'noCode' => TetherNoCode(TetherMissReason.fromWire(raw['reason'])),
      'test' => TetherTest(_receipt(raw['receipt'])),
      _ => const TetherUnusable(),
    };
  }

  static String? _receipt(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

/// The code led to [link]. It is also stored as the attribution result.
final class TetherMatched extends TetherReadResult {
  /// Creates a matched result.
  const TetherMatched(this.link);

  /// The link the code led to.
  final WarpLinkDeepLink link;

  @override
  bool operator ==(Object other) =>
      other is TetherMatched && other.link == link;

  @override
  int get hashCode => link.hashCode;

  @override
  String toString() => 'TetherMatched($link)';
}

/// No code was read and nothing was sent.
final class TetherNoCode extends TetherReadResult {
  /// Creates a no-code result.
  const TetherNoCode(this.reason);

  /// Why no code arrived. `null` on Android, which reads nothing, and for a
  /// reason this version does not know.
  final TetherMissReason? reason;

  @override
  bool operator ==(Object other) =>
      other is TetherNoCode && other.reason == reason;

  @override
  int get hashCode => Object.hash(TetherNoCode, reason);

  @override
  String toString() => 'TetherNoCode($reason)';
}

/// A code was sent and led nowhere. Let the person continue.
final class TetherUnusable extends TetherReadResult {
  /// Creates an unusable result.
  const TetherUnusable();

  @override
  bool operator ==(Object other) => other is TetherUnusable;

  @override
  int get hashCode => (TetherUnusable).hashCode;

  @override
  String toString() => 'TetherUnusable()';
}

/// A test code (`wl1t_`) reached the server and nothing was recorded.
final class TetherTest extends TetherReadResult {
  /// Creates a test result.
  const TetherTest(this.receipt);

  /// The receipt the server returned, or `null` when it sent none.
  final String? receipt;

  @override
  bool operator ==(Object other) =>
      other is TetherTest && other.receipt == receipt;

  @override
  int get hashCode => Object.hash(TetherTest, receipt);

  @override
  String toString() => 'TetherTest($receipt)';
}
