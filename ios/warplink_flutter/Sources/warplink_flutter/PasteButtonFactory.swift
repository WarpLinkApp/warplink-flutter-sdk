import Flutter
import UIKit

/// Makes a paste button view for each `UiKitView` Dart shows.
final class PasteButtonFactory: NSObject, FlutterPlatformViewFactory {
    static let viewType = "app.warplink/flutter/paste_button"

    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        PasteButtonPlatformView(frame: frame, viewId: viewId, arguments: args, messenger: messenger)
    }
}
