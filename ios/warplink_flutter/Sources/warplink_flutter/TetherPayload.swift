import Foundation
import WarpLink

/// Builds the Tether maps of the channel contract. An absent value is null.
enum TetherPayload {
    /// A Tether outcome: `kind` plus `link`, `reason` or `receipt`.
    static func result(_ result: TetherReadResult) -> [String: Any] {
        switch result {
        case .matched(let link):
            return ["kind": "matched", "link": DeepLinkPayload.deepLink(link)]
        case .noCode(let reason):
            return ["kind": "noCode", "reason": reason.rawValue]
        case .unusable:
            return ["kind": "unusable"]
        case .test(let receipt):
            return ["kind": "test", "receipt": receipt ?? NSNull()]
        }
    }

    /// The body of a paste button event: `result` for an outcome, `error` for a
    /// failure, so Dart can tell the two apart.
    static func eventBody(_ outcome: Result<TetherReadResult, WarpLinkError>) -> [String: Any] {
        switch outcome {
        case .success(let read):
            return ["result": result(read)]
        case .failure(let error):
            let mapped = ContractError.from(error)
            return ["error": ["code": mapped.code, "message": mapped.message]]
        }
    }
}
