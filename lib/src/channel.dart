import 'package:flutter/services.dart';
import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/shared_stream.dart';

/// Name of the method channel.
const String methodChannelName = 'app.warplink/flutter';

/// Name of the event channel that announces arrivals.
const String arrivalsChannelName = 'app.warplink/flutter/arrivals';

/// Method names on the method channel.
abstract final class WarpLinkMethod {
  /// Configures the native SDK.
  static const String configure = 'configure';

  /// Resolves a URL.
  static const String handleDeepLink = 'handleDeepLink';

  /// Tests whether a URL belongs to a known WarpLink domain.
  static const String isWarpLinkUrl = 'isWarpLinkUrl';

  /// Runs the deferred deep link check.
  static const String checkDeferredDeepLink = 'checkDeferredDeepLink';

  /// Reads the stored attribution result.
  static const String getAttributionResult = 'getAttributionResult';

  /// Reads whether the SDK is configured.
  static const String isConfigured = 'isConfigured';

  /// Reads whether install attribution has completed.
  static const String isAttributionComplete = 'isAttributionComplete';

  /// Lists the arrivals the native ledger still holds.
  static const String getPendingArrivals = 'getPendingArrivals';

  /// Claims an arrival and resolves it, joining an earlier claim.
  static const String resolveArrival = 'resolveArrival';

  /// Claims the one delivery of an arrival.
  static const String claimDelivery = 'claimDelivery';

  /// Reads the version the native SDK reports.
  static const String getSdkVersion = 'getSdkVersion';
}

/// Typed access to the plugin's platform channels.
///
/// Every platform failure leaves this class as a [WarpLinkException].
final class WarpLinkChannel {
  /// Creates the channel set.
  WarpLinkChannel()
    : _method = const MethodChannel(methodChannelName),
      _arrivals = SharedStream(
        () => const EventChannel(arrivalsChannelName).receiveBroadcastStream(),
      );

  final MethodChannel _method;
  final SharedStream _arrivals;

  /// Arrival announcements as raw channel payloads.
  Stream<Object?> get arrivals => _arrivals.stream;

  /// Calls [method] and returns the raw result.
  ///
  /// A [PlatformException] becomes a [WarpLinkException]. An unknown error
  /// code becomes a [WarpLinkServerException].
  Future<Object?> invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _method.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      throw mapPlatformException(error);
    }
  }
}

/// Converts a platform failure into the matching [WarpLinkException].
///
/// `details` may be a map holding an integer `statusCode`.
WarpLinkException mapPlatformException(PlatformException error) {
  final details = error.details;
  final status = details is Map<Object?, Object?>
      ? details['statusCode']
      : null;
  return WarpLinkException.fromWire(
    error.code,
    error.message,
    statusCode: status is int ? status : null,
  );
}
