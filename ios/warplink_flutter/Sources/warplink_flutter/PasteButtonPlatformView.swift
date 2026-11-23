import Flutter
import UIKit
import WarpLink

/// Hosts the real `WarpLinkUIPasteButton`, so the system paste control is the
/// only thing that ever reads the clipboard for a Tether code. Dart never sees
/// the pasted text: the native SDK redeems it and this view sends back only the
/// outcome.
///
/// The host view is empty below iOS 16, the same guard the iOS SDK puts on
/// its own control. Dart does not show an
/// empty host, because `isPasteButtonSupported` answers `false` first.
final class PasteButtonPlatformView: NSObject, FlutterPlatformView {
    private let host: UIView
    private let channel: FlutterMethodChannel

    init(frame: CGRect, viewId: Int64, arguments: Any?, messenger: FlutterBinaryMessenger) {
        host = UIView(frame: frame)
        channel = FlutterMethodChannel(
            name: "\(PasteButtonFactory.viewType)/\(viewId)",
            binaryMessenger: messenger
        )
        super.init()
        install(arguments)
    }

    func view() -> UIView { host }

    private func install(_ arguments: Any?) {
        guard #available(iOS 16.0, *) else { return }
        let button = WarpLinkUIPasteButton(
            configuration: PasteButtonStyle(arguments: arguments).configuration
        )
        // Only `onTether` is set: setting `onResult` would make the control
        // accept the older invitation text as well.
        button.onTether = { [channel] outcome in
            channel.invokeMethod("onTether", arguments: TetherPayload.eventBody(outcome))
        }
        button.frame = host.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(button)
    }
}
