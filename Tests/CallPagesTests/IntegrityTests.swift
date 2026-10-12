import XCTest
@testable import CallPages

final class IntegrityChecksTests: XCTestCase {
    private func decodePages(_ json: String) throws -> [Page] {
        let response = try JSONDecoder().decode(PagesResponse.self, from: Data(json.utf8))
        return response.pages ?? []
    }

    /// The v1.4.1 symptom: pages exist, every one computes 0 products.
    func testProductsZeroStateDetected() throws {
        let pages = try decodePages("""
        {"ok":true,"pages":[
          {"id":"p1","title":"A","product_count":0,"config":{"products":[],"collections":[]}},
          {"id":"p2","title":"B","product_count":0,"config":{"products":[],"collections":[]}}
        ]}
        """)
        XCTAssertTrue(IntegrityChecks.isProductsZeroState(pages))
    }

    func testProductsZeroStateNotFiredWhenAnyPageHasProducts() throws {
        let pages = try JSONDecoder().decode(
            PagesResponse.self, from: Data(Fixtures.pagesJSON.utf8)).pages ?? []
        XCTAssertFalse(IntegrityChecks.isProductsZeroState(pages))
    }

    func testProductsZeroStateNotFiredWithNoPages() {
        XCTAssertFalse(IntegrityChecks.isProductsZeroState([]))
    }

    /// The actual #240 bug shape: server count says 20,720 products,
    /// the parsed config has none (missing `config` key entirely).
    func testServerCountMismatchDetectedWhenConfigMissing() throws {
        let pages = try decodePages("""
        {"ok":true,"pages":[
          {"id":"p1","title":"Big Shop","product_count":20720}
        ]}
        """)
        XCTAssertTrue(IntegrityChecks.hasServerCountMismatch(pages))
        // And with the config absent, the zero-state fires too.
        XCTAssertTrue(IntegrityChecks.isProductsZeroState(pages))
    }

    func testNoMismatchWhenCountsAgree() throws {
        let pages = try JSONDecoder().decode(
            PagesResponse.self, from: Data(Fixtures.pagesJSON.utf8)).pages ?? []
        XCTAssertFalse(IntegrityChecks.hasServerCountMismatch(pages))
    }

    /// The call-log symptom: summary exists, transcript empty,
    /// communications empty → missing log.
    func testCallLogMissingDetected() throws {
        let call = try JSONDecoder().decode(
            CallDetailResponse.self,
            from: Data("""
            {"ok":true,"call":{"id":"c1","summary":"Booked a pickup.","duration_seconds":45,"transcript":[]}}
            """.utf8)).call!
        XCTAssertTrue(IntegrityChecks.isCallLogMissing(call: call, communicationsCount: 0))
        XCTAssertFalse(IntegrityChecks.isCallLogMissing(call: call, communicationsCount: 1))
    }

    func testCallLogPresentWhenTranscriptExists() throws {
        let call = try JSONDecoder().decode(
            CallDetailResponse.self, from: Data(Fixtures.callDetailJSON.utf8)).call!
        XCTAssertFalse(IntegrityChecks.isCallLogMissing(call: call, communicationsCount: 0))
    }

    /// An empty call (no summary, no duration, nothing) is not an
    /// impossible state — no report.
    func testEmptyCallIsNotMissingLog() throws {
        let call = try JSONDecoder().decode(
            CallDetailResponse.self,
            from: Data("""
            {"ok":true,"call":{"id":"c2","summary":"","duration_seconds":0,"transcript":[]}}
            """.utf8)).call!
        XCTAssertFalse(IntegrityChecks.isCallLogMissing(call: call, communicationsCount: 0))
    }
}

final class ReporterPayloadTests: XCTestCase {
    /// The exact key set the worker whitelists for /api/v1/mobile/report
    /// (plus the platform attribution the iOS parity change adds).
    private let reportWhitelist: Set<String> = [
        "kind", "check", "endpoint", "statusCode", "pages", "pagesWithProducts",
        "callsTotal", "detail", "appVersionName", "appVersionCode",
        "androidVersion", "deviceModel", "platform", "osVersion",
    ]
    private let failureWhitelist: Set<String> = [
        "flow", "step", "exceptionClass", "statusCode", "message",
        "appVersionName", "appVersionCode", "androidVersion", "deviceModel",
        "platform", "osVersion",
    ]

    func testIntegrityPayloadKeysAreWhitelistedAndPlatformIsIOS() {
        let payload = ReportPayload.integrity(
            kind: "products-zero", check: "catalog-refresh",
            endpoint: "/api/pages", statusCode: 200, pages: 11,
            pagesWithProducts: 0, callsTotal: nil, detail: "x")
        XCTAssertTrue(Set(payload.keys).isSubset(of: reportWhitelist),
                      "non-whitelisted keys: \(Set(payload.keys).subtracting(reportWhitelist))")
        XCTAssertEqual(payload["platform"] as? String, "ios")
        XCTAssertNotNil(payload["osVersion"])
        // No identity-shaped data ever rides along.
        XCTAssertNil(payload["email"])
        XCTAssertNil(payload["token"])
        XCTAssertNil(payload["user_id"])
    }

    func testSignInFailurePayloadKeysAreWhitelisted() {
        let payload = ReportPayload.signInFailure(
            flow: "aswebauth-device-flow", step: "exchange-code",
            exceptionClass: "HttpError", statusCode: 500, message: "boom")
        XCTAssertTrue(Set(payload.keys).isSubset(of: failureWhitelist),
                      "non-whitelisted keys: \(Set(payload.keys).subtracting(failureWhitelist))")
        XCTAssertEqual(payload["platform"] as? String, "ios")
    }

    /// Caps mirror the worker's truncation limits, so what the app
    /// sends is what the server stores.
    func testPayloadCaps() {
        let long = String(repeating: "x", count: 1000)
        let payload = ReportPayload.integrity(
            kind: long, check: long, endpoint: long, detail: long,
            appVersionName: long, osVersion: long, deviceModel: long)
        XCTAssertEqual((payload["kind"] as? String)?.count, 40)
        XCTAssertEqual((payload["check"] as? String)?.count, 60)
        XCTAssertEqual((payload["endpoint"] as? String)?.count, 80)
        XCTAssertEqual((payload["detail"] as? String)?.count, 300)
        XCTAssertEqual((payload["appVersionName"] as? String)?.count, 20)
        XCTAssertEqual((payload["osVersion"] as? String)?.count, 20)
        XCTAssertEqual((payload["deviceModel"] as? String)?.count, 60)

        let failure = ReportPayload.signInFailure(
            flow: long, step: long, exceptionClass: long, message: long)
        XCTAssertEqual((failure["flow"] as? String)?.count, 40)
        XCTAssertEqual((failure["step"] as? String)?.count, 60)
        XCTAssertEqual((failure["exceptionClass"] as? String)?.count, 120)
        XCTAssertEqual((failure["message"] as? String)?.count, 300)
    }

    func testPayloadsAreJSONSerializable() {
        let payload = ReportPayload.integrity(
            kind: "generic", check: "endpoint-load", statusCode: 500, pages: 2)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: payload))
    }

    /// Throttle: same kind|check inside 10 minutes sends once; after
    /// the window it sends again. Different checks are independent.
    func testIntegrityReporterThrottle() {
        let reporter = AppIntegrityReporter()
        var sent: [[String: Any]] = []
        reporter.sender = { sent.append($0) }
        var now = Date(timeIntervalSince1970: 1_000_000)
        reporter.clock = { now }

        reporter.reportProductsZero(pages: 3)
        reporter.reportProductsZero(pages: 3)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["kind"] as? String, "products-zero")
        XCTAssertEqual(sent.first?["pages"] as? Int, 3)
        XCTAssertEqual(sent.first?["platform"] as? String, "ios")

        reporter.reportCallLogEmpty()
        XCTAssertEqual(sent.count, 2)

        now = now.addingTimeInterval(11 * 60)
        reporter.reportProductsZero(pages: 3)
        XCTAssertEqual(sent.count, 3)
    }
}
