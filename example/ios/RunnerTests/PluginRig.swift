import Flutter
import UIKit
import WarpLink
import XCTest

@testable import warplink_flutter

/// A scripted stand-in for the native SDK singleton.
final class FakeWarpLinkNative: WarpLinkNative, @unchecked Sendable {
    var isConfigured = false
    var isAttributionComplete = false
    var attributionResult: WarpLinkDeepLink?
    var sdkVersion = "1.1.0"
    var knownHosts: Set<String> = ["aplnk.to"]
    var resolveResult: Result<WarpLinkDeepLink, WarpLinkError> = .failure(.linkNotFound)
    var deferredResult: Result<WarpLinkDeepLink?, WarpLinkError> = .success(nil)
    /// While `true`, a resolve waits in `heldResolves` until the test finishes it.
    var holdResolves = false

    private(set) var configureCalls: [(apiKey: String, options: WarpLinkOptions)] = []
    private(set) var resolveCalls: [URL] = []
    private var heldResolves: [(Result<WarpLinkDeepLink, WarpLinkError>) -> Void] = []

    var latestOptions: WarpLinkOptions? { configureCalls.last?.options }

    func configure(apiKey: String, options: WarpLinkOptions) {
        configureCalls.append((apiKey, options))
        isConfigured = true
    }

    func handleDeepLink(
        _ url: URL,
        completion: @escaping (Result<WarpLinkDeepLink, WarpLinkError>) -> Void
    ) {
        resolveCalls.append(url)
        if holdResolves {
            heldResolves.append(completion)
        } else {
            completion(resolveResult)
        }
    }

    /// Completes the oldest held resolve.
    func finishHeldResolve(_ result: Result<WarpLinkDeepLink, WarpLinkError>) {
        heldResolves.removeFirst()(result)
    }

    func checkDeferredDeepLink(
        completion: @escaping (Result<WarpLinkDeepLink?, WarpLinkError>) -> Void
    ) {
        completion(deferredResult)
    }

    func isWarpLinkURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), knownHosts.contains(host) else { return false }
        return url.pathComponents.filter { $0 != "/" }.count == 1
    }
}

/// What a method call answered.
enum Reply {
    case value(Any?)
    case error(FlutterError)
    case notImplemented
}

/// One process worth of plugin state around a fake native SDK. Engines made
/// from the same host share it, the way engines in one process do.
final class TestHost {
    let native = FakeWarpLinkNative()
    let process: PluginProcess
    private(set) var logs: [String] = []
    private var tick = 1_000
    private(set) var turn = 0

    init(declaredDomains: [String] = [], declaresScenes: Bool = false) {
        let native = native
        var host: TestHost?
        process = PluginProcess(
            native: native,
            matcher: PreConfigureLinkMatcher(declared: { declaredDomains }),
            declaresScenes: declaresScenes,
            clock: { host?.nextTick() ?? 0 },
            turn: { host?.turn ?? 0 },
            log: { host?.logs.append($0) }
        )
        host = self
    }

    var ledger: ArrivalLedger { process.ledger }
    var ingress: ArrivalIngress { process.ingress }

    /// Moves to the next main run-loop turn.
    func advanceTurn() {
        turn += 1
    }

    func nextTick() -> Int {
        tick += 1
        return tick
    }

    /// Ends the launch window with no launch arrival.
    func finishLaunch() {
        process.verdict.decide()
    }
}

/// One engine: a method handler and an arrivals stream onto a host's process.
final class PluginRig {
    static let validKey = "wl_live_abcdefghijklmnopqrstuvwxyz012345"

    let host: TestHost
    let methods: WarpLinkMethodHandler
    let arrivals: ArrivalsStreamHandler

    init(host: TestHost = TestHost()) {
        self.host = host
        methods = WarpLinkMethodHandler(process: host.process)
        arrivals = ArrivalsStreamHandler(ledger: host.ledger)
    }

    var native: FakeWarpLinkNative { host.native }

    /// Runs a method call and returns its reply. Fails when no reply came.
    func call(_ method: String, _ arguments: [String: Any]? = nil) -> Reply? {
        var reply: Reply?
        methods.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { value in
            reply = Self.classify(value)
        }
        return reply
    }

    private static func classify(_ value: Any?) -> Reply {
        if let error = value as? FlutterError { return .error(error) }
        if let object = value as? NSObject, object === FlutterMethodNotImplemented {
            return .notImplemented
        }
        return .value(value)
    }

    /// Arguments for a valid `configure` call, with `overrides` applied.
    func configureArguments(_ overrides: [String: Any] = [:]) -> [String: Any] {
        var arguments: [String: Any] = [
            "apiKey": Self.validKey,
            "apiEndpoint": "https://api.warplink.app/v1",
            "debugLogging": false,
            "linkDomains": [String](),
            "automaticDeepLinks": false,
            "automaticDeferredDeepLinks": false,
        ]
        overrides.forEach { arguments[$0.key] = $0.value }
        return arguments
    }

    /// Opens the arrivals channel and records every event it receives.
    func listen() -> EventRecorder {
        let recorder = EventRecorder()
        _ = arrivals.onListen(withArguments: nil) { recorder.events.append($0 as Any) }
        return recorder
    }
}

final class EventRecorder {
    var events: [Any] = []

    var maps: [[String: Any]] { events.compactMap { $0 as? [String: Any] } }
}

func sampleLink(id: String = "link-1") -> WarpLinkDeepLink {
    WarpLinkDeepLink(
        linkId: id,
        destination: "https://example.com/p",
        deepLinkUrl: "myapp://p",
        customParams: ["n": .int(3), "tags": .array([.string("a"), .null])],
        isDeferred: false,
        matchType: .deterministic,
        matchConfidence: 1.0,
        matchGuaranteed: true
    )
}

func link(_ text: String) -> URL {
    URL(string: text)!
}

extension Optional where Wrapped == Reply {
    /// The reply value; fails the test when the call did not reply with one.
    var value: Any? {
        guard case .value(let value)? = self else {
            XCTFail("expected a value reply")
            return nil
        }
        return value
    }

    var error: FlutterError? {
        guard case .error(let error)? = self else { return nil }
        return error
    }
}
