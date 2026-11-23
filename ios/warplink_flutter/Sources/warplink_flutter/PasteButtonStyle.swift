#if canImport(UIKit)
import UIKit

/// The look of the paste control, read from the platform view creation
/// parameters. `UIPasteControl.Configuration` is init-only, so Dart makes a new
/// view when the look changes.
@available(iOS 16.0, *)
struct PasteButtonStyle {
    let background: UIColor?
    let foreground: UIColor?
    let cornerStyle: UIButton.Configuration.CornerStyle
    let displayMode: UIPasteControl.DisplayMode

    init(arguments: Any?) {
        let map = arguments as? [String: Any] ?? [:]
        background = Self.color(map["baseBackgroundColor"])
        foreground = Self.color(map["baseForegroundColor"])
        cornerStyle = Self.cornerStyle(named: map["cornerStyle"] as? String)
        displayMode = Self.displayMode(named: map["displayMode"] as? String)
    }

    var configuration: UIPasteControl.Configuration {
        let configuration = UIPasteControl.Configuration()
        configuration.baseBackgroundColor = background
        configuration.baseForegroundColor = foreground
        configuration.cornerStyle = cornerStyle
        configuration.displayMode = displayMode
        return configuration
    }

    /// Reads an ARGB integer. Anything else is the system color.
    static func color(_ value: Any?) -> UIColor? {
        guard let argb = (value as? NSNumber)?.uint32Value else { return nil }
        return UIColor(
            red: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255
        )
    }

    static func cornerStyle(named name: String?) -> UIButton.Configuration.CornerStyle {
        switch name {
        case "fixed": return .fixed
        case "small": return .small
        case "medium": return .medium
        case "large": return .large
        case "capsule": return .capsule
        default: return .dynamic
        }
    }

    static func displayMode(named name: String?) -> UIPasteControl.DisplayMode {
        switch name {
        case "iconOnly": return .iconOnly
        case "labelOnly": return .labelOnly
        default: return .iconAndLabel
        }
    }
}
#endif
