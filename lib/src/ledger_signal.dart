import 'package:warplink_flutter/src/arrival.dart';
import 'package:warplink_flutter/src/errors.dart';

/// One event on the arrivals channel.
sealed class LedgerSignal {
  const LedgerSignal();

  /// Decodes an arrivals channel payload.
  ///
  /// A map of `type` `ready` is the handshake. Any other map is an arrival.
  /// Throws [WarpLinkDecodingException] for a malformed arrival.
  factory LedgerSignal.fromMap(Object? raw) {
    if (raw is Map<Object?, Object?> && raw['type'] == 'ready') {
      return const ListenerReady();
    }
    return ArrivalAnnounced(Arrival.fromMap(raw));
  }
}

/// Native finished opening its listener. It is the first event of a listen.
final class ListenerReady extends LedgerSignal {
  /// Creates the signal.
  const ListenerReady();
}

/// Native recorded [arrival] while Dart listens.
final class ArrivalAnnounced extends LedgerSignal {
  /// Creates the signal.
  const ArrivalAnnounced(this.arrival);

  /// The recorded arrival.
  final Arrival arrival;
}
