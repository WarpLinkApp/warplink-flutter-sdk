import Foundation

/// The OS entry point an arrival came through. A diagnostic label only.
enum ArrivalSource: String {
    case universalLink = "universal_link"
    case customScheme = "custom_scheme"
    case openUrl = "open_url"

    /// The label for a URL that the OS handed over through an open-URL call.
    static func forOpenedURL(_ url: URL) -> ArrivalSource {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https" ? .openUrl : .customScheme
    }
}

/// What a resolve produced: a deep link map, no match, or a contract error.
typealias ArrivalOutcome = Result<[String: Any]?, ContractError>

/// One URL the host app received, as native recorded it (contract section 4.1).
struct ArrivalEntry {
    let id: String
    let url: URL
    let source: ArrivalSource
    let isLaunch: Bool
    let seq: Int
    let arrivedAtMs: Int

    /// The map carried by a ledger entry and by an arrivals event.
    var payload: [String: Any] {
        [
            "arrivalId": id,
            "url": url.absoluteString,
            "source": source.rawValue,
            "isLaunch": isLaunch,
            "seq": seq,
            "arrivedAtMs": arrivedAtMs,
        ]
    }
}
