import Flutter
import Foundation
import WarpLink

/// Dispatches the method channel calls of channel contract section 2.
///
/// Holds no state of its own: the ledger and the configuration are
/// process-wide. The native SDK delivers its callbacks on the main thread, so
/// every reply does too.
final class WarpLinkMethodHandler: @unchecked Sendable {
    private let process: PluginProcess

    init(process: PluginProcess) {
        self.process = process
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let native = process.native
        switch call.method {
        case "configure": configure(call.arguments, result: result)
        case "handleDeepLink": handleDeepLink(call.arguments, result: result)
        case "isWarpLinkUrl": result(isWarpLinkUrl(call.arguments))
        case "checkDeferredDeepLink": checkDeferredDeepLink(result: result)
        case "getAttributionResult": getAttributionResult(result: result)
        case "isConfigured": result(native.isConfigured)
        case "isAttributionComplete": result(native.isAttributionComplete)
        case "getSdkVersion": result(native.sdkVersion)
        case "getPendingArrivals": getPendingArrivals(result: result)
        case "resolveArrival": resolveArrival(call.arguments, result: result)
        case "claimDelivery": result(claimDelivery(call.arguments))
        default: result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - configure

    private func configure(_ arguments: Any?, result: FlutterResult) {
        switch ConfigureRequest.parse(arguments) {
        case .failure(let error):
            result(error.flutterError)
        case .success(let request):
            process.configurator.apply(request)
            result(nil)
        }
    }

    // MARK: - links

    /// An independent manual request, outside the ledger.
    private func handleDeepLink(_ arguments: Any?, result: @escaping FlutterResult) {
        let raw = Self.string("url", in: arguments)
        guard let raw, let url = URL(string: raw) else {
            let shown = raw ?? ""
            result(
                ContractError(code: ContractError.invalidUrl, message: "Invalid URL: \(shown)")
                    .flutterError
            )
            return
        }
        process.native.handleDeepLink(url) { outcome in
            switch outcome {
            case .success(let link): result(DeepLinkPayload.deepLink(link))
            case .failure(let error): result(ContractError.from(error).flutterError)
            }
        }
    }

    private func isWarpLinkUrl(_ arguments: Any?) -> Bool {
        guard let raw = Self.string("url", in: arguments), let url = URL(string: raw)
        else { return false }
        return process.classifier.isWarpLink(url)
    }

    // MARK: - arrivals

    /// Waits for the launch verdict, so the list never lacks a launch entry
    /// that is still on its way.
    private func getPendingArrivals(result: @escaping FlutterResult) {
        let ledger = process.ledger
        process.verdict.whenDecided { result(ledger.pending()) }
    }

    private func resolveArrival(_ arguments: Any?, result: @escaping FlutterResult) {
        guard let id = Self.string("arrivalId", in: arguments) else {
            result(nil)
            return
        }
        process.ledger.resolve(id, using: process.native) { outcome in
            switch outcome {
            case .success(let map): result(map)
            case .failure(let error): result(error.flutterError)
            }
        }
    }

    private func claimDelivery(_ arguments: Any?) -> Bool {
        guard let id = Self.string("arrivalId", in: arguments) else { return false }
        return process.ledger.claimDelivery(id)
    }

    // MARK: - deferred and attribution

    private func checkDeferredDeepLink(result: @escaping FlutterResult) {
        process.native.checkDeferredDeepLink { outcome in
            switch outcome {
            case .success(let link): result(link.map(DeepLinkPayload.deepLink))
            case .failure(let error): result(ContractError.from(error).flutterError)
            }
        }
    }

    private func getAttributionResult(result: FlutterResult) {
        guard process.native.isConfigured else {
            result(ContractError.unconfigured.flutterError)
            return
        }
        result(process.native.attributionResult.map(DeepLinkPayload.attribution))
    }

    private static func string(_ key: String, in arguments: Any?) -> String? {
        (arguments as? [String: Any])?[key] as? String
    }
}
