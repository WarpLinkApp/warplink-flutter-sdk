import Foundation

/// Whether the native paste control can show on this device.
enum PasteButtonSupport {
    /// `false` below iOS 16, which has no system paste control.
    static var isSupported: Bool {
        if #available(iOS 16.0, *) { return true }
        return false
    }
}
