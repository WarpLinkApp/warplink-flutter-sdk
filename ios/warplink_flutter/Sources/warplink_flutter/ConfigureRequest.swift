import Foundation
import WarpLink

/// The parsed `configure` arguments (channel contract section 2.1).
///
/// The automatic switches are not read: the plugin always configures native
/// with both automatic paths off, whatever Dart sends.
struct ConfigureRequest: Equatable {
    private static let keyPattern = "^wl_(live|test)_[a-zA-Z0-9]{32}\\z"

    let apiKey: String
    let apiEndpoint: String
    let debugLogging: Bool
    let linkDomains: [String]

    /// The native options for this request: both automatic paths off and no
    /// `onLink` sink, because Dart owns all link dispatch.
    var nativeOptions: WarpLinkOptions {
        WarpLinkOptions(
            apiEndpoint: apiEndpoint,
            debugLogging: debugLogging,
            autoDeepLinkHandling: false,
            autoDeferredCheck: false,
            linkDomains: linkDomains,
            onLink: nil
        )
    }

    /// Parses and validates the arguments.
    ///
    /// Dart validates the key first, so a bad key here is a second guard. A
    /// non-string entry in `linkDomains` is dropped, not fatal.
    static func parse(_ arguments: Any?) -> Result<ConfigureRequest, ContractError> {
        let map = arguments as? [String: Any] ?? [:]
        guard let apiKey = map["apiKey"] as? String else {
            return .failure(
                ContractError(code: ContractError.invalidApiKeyFormat, message: "apiKey is required")
            )
        }
        guard apiKey.range(of: keyPattern, options: .regularExpression) != nil else {
            return .failure(ContractError.from(WarpLinkError.invalidApiKeyFormat))
        }
        let defaults = WarpLinkOptions()
        let domains = (map["linkDomains"] as? [Any])?.compactMap { $0 as? String } ?? []
        return .success(
            ConfigureRequest(
                apiKey: apiKey,
                apiEndpoint: map["apiEndpoint"] as? String ?? defaults.apiEndpoint,
                debugLogging: map["debugLogging"] as? Bool ?? defaults.debugLogging,
                linkDomains: domains
            )
        )
    }
}
