import 'package:flutter/foundation.dart';

/// Reports a failure of the arrival ledger that no caller can act on.
///
/// A malformed announcement or a failed delivery claim leaves the entry in
/// the native ledger, where the next replay offers it again. The report goes
/// through [FlutterError.reportError], so the host sees it in its error hook.
void reportLedgerError(Object error) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      library: 'warplink_flutter',
      context: ErrorDescription('while reading the arrival ledger'),
    ),
  );
}
