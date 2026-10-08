import Flutter
import Foundation
import WarpLink

/// An error in the shape the channel contract defines (section 5).
struct ContractError: Error, Equatable {
    static let notConfigured = "E_NOT_CONFIGURED"
    static let invalidApiKeyFormat = "E_INVALID_API_KEY_FORMAT"
    static let invalidApiKey = "E_INVALID_API_KEY"
    static let networkError = "E_NETWORK_ERROR"
    static let serverError = "E_SERVER_ERROR"
    static let invalidUrl = "E_INVALID_URL"
    static let linkNotFound = "E_LINK_NOT_FOUND"
    static let passwordRequired = "E_PASSWORD_REQUIRED"
    static let decodingError = "E_DECODING_ERROR"

    let code: String
    let message: String
    /// Set only for `E_SERVER_ERROR`, when native knows the status.
    let statusCode: Int?

    init(code: String, message: String, statusCode: Int? = nil) {
        self.code = code
        self.message = message
        self.statusCode = statusCode
    }

    /// The error reply for a method call.
    var flutterError: FlutterError {
        FlutterError(
            code: code,
            message: message,
            details: statusCode.map { ["statusCode": $0] }
        )
    }

    /// Maps a native failure. Anything that is not a `WarpLinkError` is a
    /// server error, as the contract requires.
    static func from(_ error: Error) -> ContractError {
        guard let native = error as? WarpLinkError else {
            return ContractError(code: serverError, message: error.localizedDescription)
        }
        let message = native.errorDescription ?? String(describing: native)
        switch native {
        case .notConfigured: return ContractError(code: notConfigured, message: message)
        case .invalidApiKeyFormat: return ContractError(code: invalidApiKeyFormat, message: message)
        case .invalidApiKey: return ContractError(code: invalidApiKey, message: message)
        case .networkError: return ContractError(code: networkError, message: message)
        case .serverError(let status, _):
            return ContractError(code: serverError, message: message, statusCode: status)
        case .invalidURL: return ContractError(code: invalidUrl, message: message)
        case .linkNotFound: return ContractError(code: linkNotFound, message: message)
        case .passwordRequired: return ContractError(code: passwordRequired, message: message)
        case .decodingError: return ContractError(code: decodingError, message: message)
        }
    }

    /// The error for a call made before `configure`.
    static var unconfigured: ContractError {
        from(WarpLinkError.notConfigured)
    }
}
