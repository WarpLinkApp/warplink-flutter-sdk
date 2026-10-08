/// Machine-readable identifier for each WarpLink failure.
enum WarpLinkErrorCode {
  /// An SDK call was made before a successful `configure`.
  notConfigured('E_NOT_CONFIGURED'),

  /// The API key does not match `wl_live_` or `wl_test_` plus 32 characters.
  invalidApiKeyFormat('E_INVALID_API_KEY_FORMAT'),

  /// The server rejected the key as invalid or revoked.
  invalidApiKey('E_INVALID_API_KEY'),

  /// The request did not reach the server.
  networkError('E_NETWORK_ERROR'),

  /// The server answered with an unexpected status, or the failure is unknown.
  serverError('E_SERVER_ERROR'),

  /// The URL is not a WarpLink link.
  invalidUrl('E_INVALID_URL'),

  /// No link exists for the URL.
  linkNotFound('E_LINK_NOT_FOUND'),

  /// The link is password protected and has no destination to return.
  passwordRequired('E_PASSWORD_REQUIRED'),

  /// A response or native payload could not be decoded.
  decodingError('E_DECODING_ERROR');

  const WarpLinkErrorCode(this.wireCode);

  /// The `E_*` string used on the platform channel and by the other SDKs.
  final String wireCode;

  /// Finds the code for a wire string. Returns `null` when unknown.
  static WarpLinkErrorCode? fromWire(String? wireCode) {
    for (final code in values) {
      if (code.wireCode == wireCode) {
        return code;
      }
    }
    return null;
  }
}

/// Base type of every error the SDK reports.
///
/// Match on the sealed subclasses with a `switch`, or read [code].
sealed class WarpLinkException implements Exception {
  const WarpLinkException(this.message);

  /// Builds the exception for [code]. An unknown [code] becomes a
  /// [WarpLinkServerException], as in the other SDKs.
  factory WarpLinkException.fromWire(
    String? code,
    String? message, {
    int? statusCode,
  }) {
    final errorCode = WarpLinkErrorCode.fromWire(code);
    final text = message ?? errorCode?.name ?? code ?? 'Unknown error';
    return switch (errorCode) {
      WarpLinkErrorCode.notConfigured => WarpLinkNotConfiguredException(text),
      WarpLinkErrorCode.invalidApiKeyFormat =>
        WarpLinkInvalidApiKeyFormatException(text),
      WarpLinkErrorCode.invalidApiKey => WarpLinkInvalidApiKeyException(text),
      WarpLinkErrorCode.networkError => WarpLinkNetworkException(text),
      WarpLinkErrorCode.invalidUrl => WarpLinkInvalidUrlException(text),
      WarpLinkErrorCode.linkNotFound => WarpLinkLinkNotFoundException(text),
      WarpLinkErrorCode.passwordRequired => WarpLinkPasswordRequiredException(
        text,
      ),
      WarpLinkErrorCode.decodingError => WarpLinkDecodingException(text),
      WarpLinkErrorCode.serverError ||
      null => WarpLinkServerException(text, statusCode: statusCode),
    };
  }

  /// Human-readable description.
  final String message;

  /// The machine-readable code for this failure.
  WarpLinkErrorCode get code;

  /// The `E_*` string for this failure, for example `E_NETWORK_ERROR`.
  String get wireCode => code.wireCode;

  @override
  String toString() => '$runtimeType($wireCode): $message';
}

/// An SDK call was made before a successful `configure`.
final class WarpLinkNotConfiguredException extends WarpLinkException {
  /// Creates the exception.
  const WarpLinkNotConfiguredException(super.message);

  @override
  WarpLinkErrorCode get code => WarpLinkErrorCode.notConfigured;
}

/// The API key has the wrong format.
final class WarpLinkInvalidApiKeyFormatException extends WarpLinkException {
  /// Creates the exception.
  const WarpLinkInvalidApiKeyFormatException(super.message);

  @override
  WarpLinkErrorCode get code => WarpLinkErrorCode.invalidApiKeyFormat;
}

/// The server rejected the API key.
final class WarpLinkInvalidApiKeyException extends WarpLinkException {
  /// Creates the exception.
  const WarpLinkInvalidApiKeyException(super.message);

  @override
  WarpLinkErrorCode get code => WarpLinkErrorCode.invalidApiKey;
}

/// The request did not reach the server.
final class WarpLinkNetworkException extends WarpLinkException {
  /// Creates the exception.
  const WarpLinkNetworkException(super.message);

  @override
  WarpLinkErrorCode get code => WarpLinkErrorCode.networkError;
}

/// The server answered with an unexpected status, or the failure is unknown.
final class WarpLinkServerException extends WarpLinkException {
  /// Creates the exception. [statusCode] is the HTTP status when known.
  const WarpLinkServerException(super.message, {this.statusCode});

  /// The HTTP status code, or `null` when the failure had no response.
  final int? statusCode;

  @override
  WarpLinkErrorCode get code => WarpLinkErrorCode.serverError;
}

/// The URL is not a WarpLink link.
final class WarpLinkInvalidUrlException extends WarpLinkException {
  /// Creates the exception.
  const WarpLinkInvalidUrlException(super.message);

  @override
  WarpLinkErrorCode get code => WarpLinkErrorCode.invalidUrl;
}

/// No link exists for the URL.
final class WarpLinkLinkNotFoundException extends WarpLinkException {
  /// Creates the exception.
  const WarpLinkLinkNotFoundException(super.message);

  @override
  WarpLinkErrorCode get code => WarpLinkErrorCode.linkNotFound;
}

/// The link is password protected.
///
/// Open the short URL in a browser, where the password form lives.
final class WarpLinkPasswordRequiredException extends WarpLinkException {
  /// Creates the exception.
  const WarpLinkPasswordRequiredException(super.message);

  @override
  WarpLinkErrorCode get code => WarpLinkErrorCode.passwordRequired;
}

/// A response or native payload could not be decoded.
final class WarpLinkDecodingException extends WarpLinkException {
  /// Creates the exception.
  const WarpLinkDecodingException(super.message);

  @override
  WarpLinkErrorCode get code => WarpLinkErrorCode.decodingError;
}
