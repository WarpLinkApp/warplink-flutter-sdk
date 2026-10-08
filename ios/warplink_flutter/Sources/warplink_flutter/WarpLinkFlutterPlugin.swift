import Flutter
import UIKit

/// Platform channel host for the WarpLink Flutter plugin.
///
/// The channels, methods, payloads, and errors are fixed by
/// `doc/channel-contract.md`. The plugin registers as an application delegate
/// and a scene delegate, so the host app needs no AppDelegate or SceneDelegate
/// edits. It records every URL the OS delivers in the process-wide arrival
/// ledger and dispatches nothing itself. Each engine gets its own instance,
/// which is a transport onto that ledger. Flutter hands a callback to the
/// instances of the engines it concerns, and every one of them reports it: the
/// ingress tells the repeats of one delivery apart by callback kind and URLs within one run-loop turn.
public final class WarpLinkFlutterPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
    static let methodChannelName = "app.warplink/flutter"
    static let arrivalsChannelName = "app.warplink/flutter/arrivals"

    private let process: PluginProcess
    private let methods: WarpLinkMethodHandler
    let arrivals: ArrivalsStreamHandler

    init(process: PluginProcess) {
        self.process = process
        methods = WarpLinkMethodHandler(process: process)
        arrivals = ArrivalsStreamHandler(ledger: process.ledger)
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = WarpLinkFlutterPlugin(process: .shared)
        let messenger = registrar.messenger()
        registrar.addMethodCallDelegate(
            plugin,
            channel: FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
        )
        FlutterEventChannel(name: arrivalsChannelName, binaryMessenger: messenger)
            .setStreamHandler(plugin.arrivals)
        registrar.addApplicationDelegate(plugin)
        registrar.addSceneDelegate(plugin)
        if UIApplication.shared.applicationState == .active {
            plugin.process.ingress.becameActive()
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        methods.handle(call, result: result)
    }

    /// Closes this engine's channels. The ledger keeps every entry.
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        arrivals.invalidate()
    }

    // MARK: - Application delegate

    /// Always answers `true`: a plugin must not veto the launch.
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any] = [:]
    ) -> Bool {
        process.ingress.applicationDidFinishLaunching(
            launchURLs: IncomingUrlExtractor.urls(fromLaunchOptions: launchOptions)
        )
        return true
    }

    public func applicationDidBecomeActive(_ application: UIApplication) {
        process.ingress.becameActive()
    }

    public func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([Any]) -> Void
    ) -> Bool {
        guard let url = IncomingUrlExtractor.url(from: userActivity) else { return false }
        return process.ingress.applicationContinue(
            url,
            identity: DeliveryIdentity(callback: .continue, urls: [url])
        )
    }

    public func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        process.ingress.applicationOpen(
            url,
            identity: DeliveryIdentity(callback: .open, urls: [url])
        )
    }

    // MARK: - Scene delegate

    public func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions?
    ) -> Bool {
        let activityURLs = connectionOptions?.userActivities.compactMap(IncomingUrlExtractor.url)
        let contextURLs = connectionOptions?.urlContexts.map(\.url)
        return process.ingress.sceneConnecting(
            activityURLs: activityURLs,
            contextURLs: contextURLs,
            identity: DeliveryIdentity(
                callback: .connect, urls: (activityURLs ?? []) + (contextURLs ?? [])
            )
        )
    }

    public func sceneDidBecomeActive(_ scene: UIScene) {
        process.ingress.becameActive()
    }

    public func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
        guard let url = IncomingUrlExtractor.url(from: userActivity) else { return false }
        return process.ingress.sceneContinue(
            url,
            identity: DeliveryIdentity(callback: .continue, urls: [url])
        )
    }

    public func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
        let urls = URLContexts.map(\.url)
        return process.ingress.sceneOpen(urls, identity: DeliveryIdentity(callback: .open, urls: urls))
    }
}
