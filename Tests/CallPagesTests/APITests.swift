import XCTest
@testable import CallPages

/// Records requests and answers from a routing closure — the unit-test
/// counterpart of the app's FixtureTransport.
final class StubTransport: HTTPTransport {
    struct Stub {
        let status: Int
        let body: String
    }

    var handler: (URLRequest) -> Stub
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping (URLRequest) -> Stub) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let stub = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(stub.body.utf8), response)
    }
}

final class APITests: XCTestCase {
    private var tokenStore: TokenStore!

    override func setUp() {
        super.setUp()
        tokenStore = TokenStore(service: "com.callpages.merchant.tokens.tests")
        tokenStore.clear()
    }

    override func tearDown() {
        tokenStore.clear()
        super.tearDown()
    }

    private func fixtureAPI(pagesStatus: Int = 200) -> (CallPagesAPI, StubTransport) {
        let transport = StubTransport { request in
            let path = request.url?.path ?? ""
            switch true {
            case path == "/api/pages":
                return .init(status: pagesStatus, body: Fixtures.pagesJSON)
            case path == "/api/calls/call_demo_1":
                return .init(status: 200, body: Fixtures.callDetailJSON)
            case path == "/api/owner/appointments":
                return .init(status: 200, body: Fixtures.appointmentsJSON)
            case path == "/api/me":
                return .init(status: 200, body: Fixtures.meJSON)
            default:
                return .init(status: 404, body: "{\"ok\":false}")
            }
        }
        return (CallPagesAPI(transport: transport, tokenStore: tokenStore), transport)
    }

    /// The #240 parity contract: products come from page.config, and the
    /// parsed counts agree with the server's product_count.
    func testPagesParseConfigProductsAndCounts() async throws {
        let (api, _) = fixtureAPI()
        let pages = try await api.pages()
        XCTAssertEqual(pages.count, 2)
        let shop = pages.first { $0.id == "page_demo_1" }
        XCTAssertEqual(shop?.product_count, 3)
        XCTAssertEqual(shop?.products.count, 3)
        XCTAssertEqual(shop?.products.map { $0.displayName },
                       ["Frame Queen", "Frame Twin", "Mattress Queen 10in"])
        XCTAssertEqual(shop?.collections.map { $0.name }, ["Frames", "Mattresses"])
        XCTAssertEqual(shop?.products.first?.displayPrice, "$110")
        let consulting = pages.first { $0.id == "page_demo_2" }
        XCTAssertEqual(consulting?.products.count, 0)
        XCTAssertFalse(IntegrityChecks.isProductsZeroState(pages))
        XCTAssertFalse(IntegrityChecks.hasServerCountMismatch(pages))
    }

    /// The call-log contract: the detail payload's transcript turns are
    /// parsed with roles mapped (caller / ai).
    func testCallDetailParsesTranscript() async throws {
        let (api, _) = fixtureAPI()
        let call = try await api.callDetail(id: "call_demo_1")
        XCTAssertEqual(call.summary?.contains("Queen frame"), true)
        XCTAssertEqual(call.transcript?.count, 3)
        XCTAssertEqual(call.transcript?.first?.role, "caller")
        XCTAssertEqual(call.transcript?.first?.isAI, false)
        XCTAssertEqual(call.transcript?[1].role, "ai")
        XCTAssertEqual(call.transcript?[1].isAI, true)
        XCTAssertEqual(call.durationSeconds, 61)
    }

    func testAppointmentsParse() async throws {
        let (api, _) = fixtureAPI()
        let appointments = try await api.appointments()
        XCTAssertEqual(appointments.count, 2)
        XCTAssertEqual(appointments.first?.displayCustomer, "María Demo")
        XCTAssertEqual(appointments.first?.page_business, "Sleep Shop")
        XCTAssertEqual(appointments.first?.status, "confirmed")
    }

    func testMeParses() async throws {
        let (api, _) = fixtureAPI()
        let me = try await api.me()
        XCTAssertEqual(me.user?.email, "demo@example.com")
        XCTAssertEqual(me.plan_active?.value, true)
        XCTAssertEqual(me.plan, "pro")
    }

    /// 401 → refresh → retry once: the session self-heals without the
    /// user ever seeing a sign-in screen.
    func testUnauthorizedRefreshesAndRetries() async throws {
        tokenStore.savePair(accessToken: "old-access", refreshToken: "the-refresh")
        var pagesAttempts = 0
        let transport = StubTransport { request in
            let path = request.url?.path ?? ""
            if path == "/api/v1/auth/refresh" {
                return .init(status: 200, body: Fixtures.refreshJSON)
            }
            if path == "/api/pages" {
                pagesAttempts += 1
                if pagesAttempts == 1 {
                    return .init(status: 401, body: "{\"ok\":false}")
                }
                // The retry must carry the NEW access token.
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"),
                               "Bearer stub-access-token-2")
                return .init(status: 200, body: Fixtures.pagesJSON)
            }
            return .init(status: 404, body: "{\"ok\":false}")
        }
        let api = CallPagesAPI(transport: transport, tokenStore: tokenStore)
        let pages = try await api.pages()
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(tokenStore.accessToken, "stub-access-token-2")
        XCTAssertEqual(pagesAttempts, 2)
    }

    /// A dead refresh token surfaces .unauthorized (→ sign-in), and no
    /// retry storm happens.
    func testUnauthorizedWhenRefreshFails() async {
        tokenStore.savePair(accessToken: "old-access", refreshToken: "dead-refresh")
        let transport = StubTransport { request in
            let path = request.url?.path ?? ""
            if path == "/api/v1/auth/refresh" {
                return .init(status: 401, body: "{\"ok\":false}")
            }
            return .init(status: 401, body: "{\"ok\":false}")
        }
        let api = CallPagesAPI(transport: transport, tokenStore: tokenStore)
        do {
            _ = try await api.pages()
            XCTFail("expected APIError.unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(transport.requests.count, 2) // original + refresh, no loop
    }

    /// Device-flow endpoints parse: mobile-status code + code exchange.
    func testMobileStatusAndCodeExchange() async throws {
        let transport = StubTransport { request in
            let path = request.url?.path ?? ""
            switch path {
            case "/api/v1/auth/mobile-status":
                return .init(status: 200, body: "{\"ok\":true,\"code\":\"one-time-code\"}")
            case "/api/v1/auth/google/code":
                return .init(status: 200, body: Fixtures.tokenPairJSON)
            default:
                return .init(status: 404, body: "{\"ok\":false}")
            }
        }
        let api = CallPagesAPI(transport: transport, tokenStore: tokenStore)
        let status = try await api.mobileStatus(loginId: "login-123")
        XCTAssertEqual(status.ok, true)
        XCTAssertEqual(status.code, "one-time-code")
        let pair = try await api.exchangeCode("one-time-code")
        XCTAssertEqual(pair.ok, true)
        XCTAssertEqual(pair.accessToken, "stub-access-token")
        XCTAssertEqual(pair.refreshToken, "stub-refresh-token")
    }

    /// A malformed body surfaces .decoding (which the UI reports as
    /// unparseable-body) instead of a crash or a silent empty list.
    func testDecodingErrorSurfaces() async {
        let transport = StubTransport { _ in .init(status: 200, body: "{not json") }
        let api = CallPagesAPI(transport: transport, tokenStore: tokenStore)
        do {
            _ = try await api.pages()
            XCTFail("expected APIError.decoding")
        } catch let error as APIError {
            XCTAssertEqual(error, .decoding)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
