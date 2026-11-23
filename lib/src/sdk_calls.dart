import 'package:warplink_flutter/src/attribution_result.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/src/deep_link.dart';
import 'package:warplink_flutter/src/deferred_check_status.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/platform_support.dart';
import 'package:warplink_flutter/src/referral/referral_claim_result.dart';
import 'package:warplink_flutter/src/tether/tether_read_result.dart';
import 'package:warplink_flutter/src/tether/tether_route.dart';

/// The channel calls behind the `WarpLink` methods that carry no dispatch.
///
/// Every call checks the platform first, then decodes the raw reply.
final class SdkCalls {
  /// Binds the calls to [channel].
  const SdkCalls(this.channel);

  /// The channel the calls go through.
  final WarpLinkChannel channel;

  /// Calls [method] and returns the raw reply.
  Future<Object?> call(String method, [Map<String, Object?>? arguments]) async {
    requireSupportedPlatform();
    return channel.invoke(method, arguments);
  }

  /// Calls [method] and decodes a deep link, or `null`.
  Future<WarpLinkDeepLink?> link(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final raw = await call(method, arguments);
    return raw == null ? null : WarpLinkDeepLink.fromMap(raw);
  }

  /// Calls [method] and reads a boolean reply.
  Future<bool> flag(String method) async => await call(method) == true;

  /// Reads the stored attribution result.
  Future<AttributionResult?> attributionResult() async {
    final raw = await call(WarpLinkMethod.getAttributionResult);
    return raw == null ? null : AttributionResult.fromMap(raw);
  }

  /// Reads where the deferred check stands. Sends no request.
  Future<DeferredCheckStatus> deferredCheckStatus() async =>
      DeferredCheckStatus.fromMap(
        await call(WarpLinkMethod.getDeferredCheckStatus),
      );

  /// Claims the referral behind this install for [installerId].
  Future<ReferralClaimResult> claimReferral(String installerId) async {
    final raw = await call(WarpLinkMethod.claimReferral, {
      'installerId': installerId,
    });
    return ReferralClaimResult.fromMap(raw);
  }

  /// Reads the clipboard once and sends a Tether code, if one is there. A
  /// match that replaces a link `onLink` already received goes to `onLink`.
  Future<TetherReadResult> readTether() async {
    final result = TetherReadResult.fromMap(
      await call(WarpLinkMethod.readTether),
    );
    routeTetherResult(result);
    return result;
  }

  /// Reads the receipt of the last test Tether read, or `null`.
  Future<String?> lastTetherTestReceipt() async {
    final raw = await call(WarpLinkMethod.getTetherTestReceipt);
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  /// Reads the version the native SDK sends on the wire.
  Future<String> sdkVersion() async {
    final raw = await call(WarpLinkMethod.getSdkVersion);
    if (raw is String) {
      return raw;
    }
    throw const WarpLinkDecodingException('Native SDK version is not a string');
  }

  /// Whether [url] belongs to a known WarpLink domain. An unparsable string
  /// reads `false`.
  Future<bool> isWarpLinkUrl(String url) async {
    try {
      return await call(WarpLinkMethod.isWarpLinkUrl, {'url': url}) == true;
    } on WarpLinkException {
      return false;
    }
  }
}
