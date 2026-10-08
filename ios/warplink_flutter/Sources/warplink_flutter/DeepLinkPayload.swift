import Foundation
import WarpLink

/// Builds the standard-codec maps of channel contract section 3.
enum DeepLinkPayload {
    /// The deep link map (section 3.1).
    static func deepLink(_ link: WarpLinkDeepLink) -> [String: Any] {
        [
            "linkId": link.linkId,
            "destination": link.destination,
            "deepLinkUrl": link.deepLinkUrl ?? NSNull(),
            "customParams": link.customParams.mapValues(foundationValue),
            "isDeferred": link.isDeferred,
            "matchType": link.matchType?.rawValue ?? NSNull(),
            "matchConfidence": link.matchConfidence ?? NSNull(),
            "matchGuaranteed": link.matchGuaranteed,
        ]
    }

    /// The attribution map (section 3.2).
    static func attribution(_ link: WarpLinkDeepLink) -> [String: Any] {
        [
            "linkId": link.linkId,
            "matchType": link.matchType?.rawValue ?? NSNull(),
            "matchConfidence": link.matchConfidence ?? NSNull(),
            "matchGuaranteed": link.matchGuaranteed,
            "isDeferred": link.isDeferred,
        ]
    }

    /// Lowers a `JSONValue` to the types the standard codec carries.
    static func foundationValue(_ value: JSONValue) -> Any {
        switch value {
        case .string(let text): return text
        case .int(let number): return number
        case .double(let number): return number
        case .bool(let flag): return flag
        case .object(let members): return members.mapValues(foundationValue)
        case .array(let items): return items.map(foundationValue)
        case .null: return NSNull()
        }
    }
}
