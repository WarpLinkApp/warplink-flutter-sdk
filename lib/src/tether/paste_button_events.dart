import 'package:warplink_flutter/src/errors.dart';
import 'package:warplink_flutter/src/tether/tether_read_result.dart';

/// What one tap on the native paste control ended on.
///
/// Native sends `{result}` or `{error: {code, message}}`. A body this version
/// cannot read is [TetherUnusable], never a throw.
({TetherReadResult? result, WarpLinkException? error}) decodePasteEvent(
  Object? body,
) {
  if (body is! Map<Object?, Object?>) {
    return (result: const TetherUnusable(), error: null);
  }
  final error = body['error'];
  if (error is Map<Object?, Object?>) {
    final code = error['code'];
    final message = error['message'];
    return (
      result: null,
      error: WarpLinkException.fromWire(
        code is String ? code : null,
        message is String ? message : null,
      ),
    );
  }
  return (result: TetherReadResult.fromMap(body['result']), error: null);
}
