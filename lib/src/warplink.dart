import 'package:flutter/foundation.dart';
import 'package:warplink_flutter/src/attribution_reset.dart';
import 'package:warplink_flutter/src/attribution_result.dart';
import 'package:warplink_flutter/src/channel.dart';
import 'package:warplink_flutter/src/configure_flow.dart';
import 'package:warplink_flutter/src/deep_link.dart';
import 'package:warplink_flutter/src/deferred_check_status.dart';
import 'package:warplink_flutter/src/events.dart';
import 'package:warplink_flutter/src/link_runtime.dart';
import 'package:warplink_flutter/src/platform_support.dart';
import 'package:warplink_flutter/src/referral/referral_claim_result.dart';
import 'package:warplink_flutter/src/sdk_calls.dart';
import 'package:warplink_flutter/src/tether/tether_enums.dart';
import 'package:warplink_flutter/src/tether/tether_read_result.dart';

/// Default endpoint of the WarpLink API.
const String defaultApiEndpoint = 'https://api.warplink.app/v1';

/// Deep linking, install attribution, and link analytics.
///
/// Call [configure] once at startup. With an `onLink` callback, all deep links
/// arrive through that one callback. Methods run in the root isolate on iOS and
/// Android only; other platforms throw [UnsupportedError].
abstract final class WarpLink {
  static LinkRuntime _runtime = LinkRuntime(WarpLinkChannel());
  static SdkCalls _calls = SdkCalls(_runtime.channel);

  /// Initializes the SDK.
  ///
  /// [apiKey] is an SDK key (`wl_live_` or `wl_test_` plus 32 characters)
  /// created under Keys > SDK keys in the dashboard. A malformed key never
  /// throws: the SDK logs a warning, delivers an [ErrorEvent] to [onLink], and
  /// stays unconfigured.
  ///
  /// [onLink] is the single sink for cold-start, warm-start, and deferred
  /// links. A native configuration failure reaches it as an [ErrorEvent].
  /// Without [onLink] the future completes with a [WarpLinkException].
  ///
  /// [automaticDeepLinks] only takes effect when [onLink] is set; set it to
  /// `false` to wire links yourself with [onDeepLink] and
  /// [getInitialDeepLink]. [automaticDeferredDeepLinks] runs the install
  /// attribution check after the launch link. [linkDomains] lists extra hosts
  /// that serve your links, on top of `aplnk.to`. [tetherReadMode] says how
  /// the SDK gets a Tether code from the clipboard; the default never reads it
  /// by itself. See [readTether].
  ///
  /// The future completes when native configuration does, without waiting for
  /// the launch link or the deferred check. Calling `configure` again with
  /// other options replaces the earlier configuration and callback. With the
  /// same key and options it keeps the session, replaces only the callback,
  /// and gives an unfinished check one more chance, at most once a minute. The
  /// native SDK decides whether that sends a request.
  static Future<void> configure({
    required String apiKey,
    String apiEndpoint = defaultApiEndpoint,
    bool debugLogging = false,
    List<String> linkDomains = const <String>[],
    bool automaticDeepLinks = true,
    bool automaticDeferredDeepLinks = true,
    TetherReadMode tetherReadMode = TetherReadMode.pasteButton,
    WarpLinkListener? onLink,
  }) async {
    requireSupportedPlatform();
    return configureSdk(
      _runtime,
      apiKey: apiKey,
      apiEndpoint: apiEndpoint,
      debugLogging: debugLogging,
      linkDomains: linkDomains,
      automaticDeepLinks: automaticDeepLinks,
      automaticDeferredDeepLinks: automaticDeferredDeepLinks,
      tetherReadMode: tetherReadMode,
      onLink: onLink,
    );
  }

  /// Resolves [url], a WarpLink link, to its destination.
  ///
  /// Throws [WarpLinkInvalidUrlException] for a URL that is not a WarpLink
  /// link. Never superseded by automatic deliveries.
  static Future<WarpLinkDeepLink?> handleDeepLink(String url) async {
    requireSupportedPlatform();
    return _runtime.manual.handleDeepLink(url);
  }

  /// Runs the deferred deep link check. Returns the stored result once
  /// attribution completed, and `null` for a confirmed no-match.
  static Future<WarpLinkDeepLink?> checkDeferredDeepLink() =>
      _calls.link(WarpLinkMethod.checkDeferredDeepLink);

  /// Reads the stored install attribution result, or `null` for no match.
  /// Throws [WarpLinkNotConfiguredException] before [configure].
  static Future<AttributionResult?> getAttributionResult() =>
      _calls.attributionResult();

  /// Redeems the invitation in [text], which the person pasted.
  ///
  /// Pass the text as the person pasted it; the SDK never reads the
  /// clipboard. Returns the matched link, or `null` when the text is not an
  /// invitation or matched nothing, so do not tell the person a referral was
  /// applied. A refused invitation throws a [WarpLinkServerException] whose
  /// message says how to open the link again. After a
  /// [WarpLinkNetworkException] the native SDK keeps the invitation and tries
  /// again on a later launch, a bounded number of times.
  static Future<WarpLinkDeepLink?> redeemInvitation(String text) =>
      _calls.link(WarpLinkMethod.redeemInvitation, {'text': text});

  /// Claims the referral behind this install for the new signup.
  ///
  /// [installerId] is your own stable id for that person, 1 to 128
  /// characters. Calling again with the same id returns the same claim.
  /// [ReferralClaimStatus.none] is an answer, not an error. The call throws
  /// when it cannot reach the server, the key is refused, or [installerId] is
  /// empty or too long.
  static Future<ReferralClaimResult> claimReferral(String installerId) =>
      _calls.claimReferral(installerId);

  /// Reads the clipboard once and sends a Tether code, if one is there.
  ///
  /// Use it with `TetherReadMode.onCall`. On iOS the system may show its paste
  /// alert. Android reads nothing and returns [TetherNoCode] with a `null`
  /// reason. A match is also stored as the attribution result, and goes to
  /// `onLink` when it replaces a link `onLink` already received, such as the
  /// first-launch estimate. A failure throws a [WarpLinkException], a
  /// [WarpLinkNotConfiguredException] before [configure].
  static Future<TetherReadResult> readTether() => _calls.readTether();

  /// The receipt of the last test code (`wl1t_`) the server accepted, or
  /// `null`. It holds a value only with a `wl_test_` key.
  static Future<String?> lastTetherTestReceipt() =>
      _calls.lastTetherTestReceipt();

  /// The version the native SDK sends on the wire, for example `1.4.1`.
  static Future<String> sdkVersion() => _calls.sdkVersion();

  /// Whether install attribution has completed for this install.
  static Future<bool> isAttributionComplete() =>
      _calls.flag(WarpLinkMethod.isAttributionComplete);

  /// Where the first-launch link check stands, so a skipped check reads
  /// differently from one that found no match. Sends no request and survives a
  /// relaunch. [DeferredCheckState.waiting] carries `retryAt`. A `wl_test_`
  /// key never reports `waiting`, `skippedOldInstall` or `stopped`.
  static Future<DeferredCheckStatus> getDeferredCheckStatus() =>
      _calls.deferredCheckStatus();

  /// Forgets this install's attribution so the next first launch can be tested
  /// again: the cached match, the completed and attempted gates, and any held
  /// referral invitation. Server records are not deleted.
  ///
  /// Test only. With a `wl_live_` key this does nothing and completes. With a
  /// `wl_test_` key and `automaticDeferredDeepLinks` on, a check in flight is
  /// discarded and a fresh check starts; its match reaches `onLink`.
  ///
  /// Throws [WarpLinkNotConfiguredException] before [configure], and
  /// [WarpLinkDecodingException], with the message "Could not clear stored
  /// attribution data.", when a stored item could not be deleted. Calling
  /// again is safe.
  static Future<void> clearAttribution() async {
    requireSupportedPlatform();
    return clearAttributionOf(_runtime);
  }

  /// Whether [configure] succeeded. `false` after a rejected key format.
  static Future<bool> isConfigured() =>
      _calls.flag(WarpLinkMethod.isConfigured);

  /// Whether [url] belongs to a known WarpLink domain.
  ///
  /// An unparsable string returns `false`.
  static Future<bool> isWarpLinkUrl(String url) => _calls.isWarpLinkUrl(url);

  /// Every URL the host app receives while it runs, resolved, for manual
  /// wiring.
  ///
  /// Emits a [LinkEvent] for a WarpLink link and an [ErrorEvent] for a failure.
  /// Events are not deduplicated and are independent of `onLink`. The launch
  /// URL is not part of this stream: read it with [getInitialDeepLink].
  static Stream<WarpLinkEvent> get onDeepLink => _runtime.arrivals.subscribers;

  /// Takes the URL that launched the app, once, and resolves it.
  ///
  /// The second call returns `null`. With `automaticDeepLinks` and an `onLink`
  /// callback the launch link goes to `onLink` and this returns `null`.
  static Future<WarpLinkDeepLink?> getInitialDeepLink() async {
    requireSupportedPlatform();
    return _runtime.takeInitialLink();
  }

  /// Replaces the channel and clears state. For tests only.
  @visibleForTesting
  static Future<void> resetForTesting([
    WarpLinkChannel? channel,
    DateTime Function() now = DateTime.now,
  ]) async {
    await _runtime.arrivals.dispose();
    _runtime = LinkRuntime(channel ?? WarpLinkChannel(), now: now);
    _calls = SdkCalls(_runtime.channel);
  }
}
