import Flutter
import WarpLink
import XCTest

@testable import warplink_flutter

final class ErrorMappingTests: XCTestCase {
    private struct Boom: Error {}

    func testEveryNativeErrorMapsToItsContractCode() {
        let cases: [(WarpLinkError, String)] = [
            (.notConfigured, "E_NOT_CONFIGURED"),
            (.invalidApiKeyFormat, "E_INVALID_API_KEY_FORMAT"),
            (.invalidApiKey, "E_INVALID_API_KEY"),
            (.networkError(Boom()), "E_NETWORK_ERROR"),
            (.serverError(statusCode: 500, message: "x"), "E_SERVER_ERROR"),
            (.invalidURL, "E_INVALID_URL"),
            (.linkNotFound, "E_LINK_NOT_FOUND"),
            (.passwordRequired, "E_PASSWORD_REQUIRED"),
            (.decodingError(Boom()), "E_DECODING_ERROR"),
        ]
        for (native, code) in cases {
            let mapped = ContractError.from(native)
            XCTAssertEqual(mapped.code, code)
            XCTAssertEqual(mapped.message, native.errorDescription)
        }
    }

    func testOnlyServerErrorCarriesDetails() {
        let server = ContractError.from(WarpLinkError.serverError(statusCode: 502, message: "bad"))
        XCTAssertEqual(server.flutterError.details as? [String: Int], ["statusCode": 502])
        XCTAssertNil(ContractError.from(WarpLinkError.linkNotFound).flutterError.details)
        XCTAssertNil(ContractError.from(WarpLinkError.networkError(Boom())).flutterError.details)
    }

    func testForeignFailureBecomesServerError() {
        let mapped = ContractError.from(Boom())
        XCTAssertEqual(mapped.code, "E_SERVER_ERROR")
        XCTAssertNil(mapped.statusCode)
    }

    func testUnconfiguredUsesTheNativeText() {
        XCTAssertEqual(
            ContractError.unconfigured.message, WarpLinkError.notConfigured.errorDescription
        )
    }
}
