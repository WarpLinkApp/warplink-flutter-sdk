import 'package:flutter/foundation.dart';
import 'package:warplink_flutter/src/deep_link.dart';
import 'package:warplink_flutter/src/errors.dart';

/// A callback that receives link events.
typedef WarpLinkListener = void Function(WarpLinkEvent event);

/// One delivery to an `onLink` callback or the `onDeepLink` stream.
///
/// Either a [LinkEvent] or an [ErrorEvent]. Use a `switch` to handle both.
@immutable
sealed class WarpLinkEvent {
  const WarpLinkEvent();

  /// Decodes an event channel payload.
  ///
  /// A malformed payload becomes an [ErrorEvent] with a
  /// [WarpLinkDecodingException], so a bad native message never throws inside
  /// a stream.
  factory WarpLinkEvent.fromMap(Object? raw) {
    try {
      if (raw is Map<Object?, Object?>) {
        if (raw['type'] == 'link') {
          return LinkEvent(WarpLinkDeepLink.fromMap(raw['link']));
        }
        if (raw['type'] == 'error') {
          final status = raw['statusCode'];
          return ErrorEvent(
            WarpLinkException.fromWire(
              raw['code']?.toString(),
              raw['message']?.toString(),
              statusCode: status is int ? status : null,
            ),
          );
        }
      }
      throw const WarpLinkDecodingException('Unknown native event payload');
    } on WarpLinkException catch (error) {
      return ErrorEvent(error);
    }
  }
}

/// A link was resolved.
final class LinkEvent extends WarpLinkEvent {
  /// Creates a link event.
  const LinkEvent(this.deepLink);

  /// The resolved link.
  final WarpLinkDeepLink deepLink;

  @override
  bool operator ==(Object other) =>
      other is LinkEvent && other.deepLink == deepLink;

  @override
  int get hashCode => deepLink.hashCode;

  @override
  String toString() => 'LinkEvent($deepLink)';
}

/// Resolving or configuring failed.
final class ErrorEvent extends WarpLinkEvent {
  /// Creates an error event.
  const ErrorEvent(this.error);

  /// The failure.
  final WarpLinkException error;

  @override
  String toString() => 'ErrorEvent($error)';
}
