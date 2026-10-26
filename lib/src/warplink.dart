import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:warplink_flutter/src/api_key.dart';
import 'package:warplink_flutter/src/attribution_result.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/src/deep_link.dart';
import 'package:warplink_flutter/src/dispatch_config.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/events.dart';
import 'package:warplink_flutter/src/link_runtime.dart';
import 'package:warplink_flutter/src/platform_support.dart';
import 'package:warplink_flutter/src/referral/referral_claim_result.dart';

/// Default endpoint of the WarpLink API.
const String defaultApiEndpoint = 'https://api.warplink.app/v1';

/// Deep linking, install attribution, and link analytics.
///
/// Call [configure] once at startup. With an `onLink` callback, cold-start,
/// warm-start, and deferred deep links all arrive through that one callback.
///
/// Every method runs in the root isolate and works on iOS and Android only.
/// Other platforms throw [UnsupportedError].
abstract final class WarpLink {
  static LinkRuntime _runtime = LinkRuntime(WarpLinkChannel());

  /// Initializes the SDK.
  ///
  /// [apiKey] is an SDK key (`wl_live_` or `wl_test_` plus 32 characters)
  /// created under Keys > SDK keys in the dashboard. A malformed key never
  /// throws: the SDK logs a warning, delivers an [ErrorEvent] to [onLink], and
  /// stays unconfigured.
  ///
  /// [onLink] is the single sink for cold-start, warm-start, and deferred
  /// links. A native configuration failure reaches it as an [ErrorEvent]
  /// instead of failing the returned future. Without [onLink] the failure
  /// completes the future with a [WarpLinkException].
  ///
  /// [automaticDeepLinks] only takes effect when [onLink] is set. Set it to
  /// `false` to wire links yourself with [onDeepLink] and
  /// [getInitialDeepLink]. [automaticDeferredDeepLinks] runs the install
  /// attribution check after the launch link, with or without [onLink].
  ///
  /// [linkDomains] lists extra hosts that serve your links, on top of
  /// `aplnk.to`. Values are normalized natively.
  ///
  /// The returned future completes when native configuration does. It does not
  /// wait for the launch link or the deferred check. Calling `configure` again
  /// replaces the earlier configuration and callback.
  static Future<void> configure({
    required String apiKey,
    String apiEndpoint = defaultApiEndpoint,
    bool debugLogging = false,
    List<String> linkDomains = const <String>[],
    bool automaticDeepLinks = true,
    bool automaticDeferredDeepLinks = true,
    WarpLinkListener? onLink,
  }) async {
    requireSupportedPlatform();
    if (!isValidApiKey(apiKey)) {
      reportInvalidApiKey(onLink);
      return;
    }
    final runtime = _runtime;
    final config = DispatchConfig(
      onLink: onLink,
      automaticDeepLinks: automaticDeepLinks,
      automaticDeferredDeepLinks: automaticDeferredDeepLinks,
    );
    runtime.arrivals.begin(config);
    try {
      await runtime.channel.invoke(WarpLinkMethod.configure, <String, Object?>{
        'apiKey': apiKey,
        'apiEndpoint': apiEndpoint,
        'debugLogging': debugLogging,
        'linkDomains': List<String>.of(linkDomains),
        'automaticDeepLinks': false,
        'automaticDeferredDeepLinks': false,
      });
    } on WarpLinkException catch (error) {
      runtime.arrivals.markConfigured(config, ok: false);
      if (onLink == null) rethrow;
      if (runtime.arrivals.isCurrent(config)) onLink(ErrorEvent(error));
      return;
    }
    runtime.arrivals.markConfigured(config, ok: true);
    unawaited(runtime.dispatchAutomatic(config));
  }

  /// Resolves [url], a WarpLink link, to its destination.
  ///
  /// Throws a [WarpLinkException], for example [WarpLinkInvalidUrlException]
  /// for a URL that is not a WarpLink link. Never superseded by automatic
  /// deliveries.
  static Future<WarpLinkDeepLink?> handleDeepLink(String url) async {
    requireSupportedPlatform();
    return _runtime.manual.handleDeepLink(url);
  }

  /// Runs the deferred deep link check.
  ///
  /// Returns the stored result on every call once attribution completed, and
  /// `null` for a confirmed no-match.
  static Future<WarpLinkDeepLink?> checkDeferredDeepLink() async {
    final raw = await _call(WarpLinkMethod.checkDeferredDeepLink);
    return raw == null ? null : WarpLinkDeepLink.fromMap(raw);
  }

  /// Reads the stored install attribution result.
  ///
  /// Returns `null` when the install had no match. Throws
  /// [WarpLinkNotConfiguredException] before [configure].
  static Future<AttributionResult?> getAttributionResult() async {
    final raw = await _call(WarpLinkMethod.getAttributionResult);
    return raw == null ? null : AttributionResult.fromMap(raw);
  }

  /// Redeems the invitation in [text], which the person pasted.
  ///
  /// Pass the text as the person pasted it. The native SDK decides whether it
  /// is an invitation and whether it has expired. The SDK never reads the
  /// clipboard.
  ///
  /// Returns the matched link, or `null` when the text is not an invitation or
  /// matched nothing. Nothing is confirmed then, so do not tell the person a
  /// referral was applied. A refused invitation throws a
  /// [WarpLinkServerException] whose message says how to open the link again.
  /// After a [WarpLinkNetworkException] the native SDK keeps the invitation and
  /// tries again on a later launch, a bounded number of times.
  static Future<WarpLinkDeepLink?> redeemInvitation(String text) async {
    final raw = await _call(WarpLinkMethod.redeemInvitation, {'text': text});
    return raw == null ? null : WarpLinkDeepLink.fromMap(raw);
  }

  /// Claims the referral behind this install for the person who just signed
  /// up.
  ///
  /// [installerId] is your own stable id for that person, 1 to 128
  /// characters. Calling again with the same id returns the same claim. A
  /// status of [ReferralClaimStatus.none] is an answer, not an error. The call
  /// throws only when it cannot reach the server, the key is refused, or
  /// [installerId] is empty or too long.
  static Future<ReferralClaimResult> claimReferral(String installerId) async {
    final raw = await _call(WarpLinkMethod.claimReferral, {
      'installerId': installerId,
    });
    return ReferralClaimResult.fromMap(raw);
  }

  /// The version the native SDK reports, for example `1.2.0`.
  ///
  /// This is the version sent on the wire, not the package version.
  static Future<String> sdkVersion() async {
    final raw = await _call(WarpLinkMethod.getSdkVersion);
    if (raw is String) {
      return raw;
    }
    throw const WarpLinkDecodingException('Native SDK version is not a string');
  }

  /// Whether install attribution has completed for this install.
  static Future<bool> isAttributionComplete() async {
    final raw = await _call(WarpLinkMethod.isAttributionComplete);
    return raw == true;
  }

  /// Whether [configure] succeeded.
  ///
  /// `false` after a rejected key format.
  static Future<bool> isConfigured() async {
    final raw = await _call(WarpLinkMethod.isConfigured);
    return raw == true;
  }

  /// Whether [url] belongs to a known WarpLink domain.
  ///
  /// Never throws for a bad URL: an unparsable string returns `false`.
  static Future<bool> isWarpLinkUrl(String url) async {
    try {
      return await _call(WarpLinkMethod.isWarpLinkUrl, {'url': url}) == true;
    } on WarpLinkException {
      return false;
    }
  }

  /// Every URL the host app receives while it runs, resolved, for manual
  /// wiring.
  ///
  /// Emits a [LinkEvent] for a WarpLink link and an [ErrorEvent] for a failure,
  /// including [WarpLinkInvalidUrlException] for a foreign URL. Events are not
  /// deduplicated and are independent of `onLink`. The launch URL is not part
  /// of this stream: read it with [getInitialDeepLink]. A URL received before
  /// the first listener attaches is delivered when it does. Cancel the
  /// subscription to stop listening.
  static Stream<WarpLinkEvent> get onDeepLink => _runtime.arrivals.subscribers;

  /// Takes the URL that launched the app, once, and resolves it.
  ///
  /// The second call returns `null`. With `automaticDeepLinks` and an `onLink`
  /// callback the launch link goes to `onLink` and this returns `null`.
  static Future<WarpLinkDeepLink?> getInitialDeepLink() async {
    requireSupportedPlatform();
    return switch (await _runtime.arrivals.takeInitial()) {
      LinkEvent(:final deepLink) => deepLink,
      ErrorEvent(:final error) => throw error,
      null => null,
    };
  }

  /// Replaces the channel and clears state. For tests only.
  @visibleForTesting
  static Future<void> resetForTesting([WarpLinkChannel? channel]) async {
    await _runtime.arrivals.dispose();
    _runtime = LinkRuntime(channel ?? WarpLinkChannel());
  }

  static Future<Object?> _call(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    requireSupportedPlatform();
    return _runtime.channel.invoke(method, arguments);
  }
}
