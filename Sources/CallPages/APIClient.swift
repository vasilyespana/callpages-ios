import Foundation

// MARK: - Errors

enum APIError: Error, Equatable {
    case unauthorized
    case http(Int)
    case decoding
    case network(String)
    case server(String)
}

// MARK: - Transport
//
// All networking goes through this seam so unit tests (and the UI-test
// stub mode) can substitute canned responses without touching the API
// surface.

protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("non-HTTP response")
        }
        return (data, http)
    }
}

// MARK: - API client
//
// Bearer-token client for the CallPages worker API — the same session
// contract as the Android app: Authorization: Bearer <access JWT> on
// every authenticated call; a 401 triggers ONE refresh via
// POST /api/v1/auth/refresh and a single retry; a second 401 (or a
// failed refresh) surfaces APIError.unauthorized, which the UI treats
// as "session expired → back to sign-in". The web session cookies the
// auth endpoints also set are captured into the shared cookie jar by
// URLSession automatically and bridged to the dashboard WebView via
// SessionStore.

final class CallPagesAPI {
    static let shared: CallPagesAPI = {
        if AppConfig.isStubMode {
            return CallPagesAPI(
                transport: FixtureTransport(emptyAccount: AppConfig.isStubEmptyMode),
                tokenStore: TokenStore(service: "com.callpages.merchant.tokens.stub"))
        }
        return CallPagesAPI()
    }()

    private let transport: HTTPTransport
    private let tokenStore: TokenStore
    private let decoder = JSONDecoder()

    init(transport: HTTPTransport = URLSessionTransport(),
         tokenStore: TokenStore = .shared) {
        self.transport = transport
        self.tokenStore = tokenStore
    }

    // MARK: Request pipeline

    /// Performs one request. Returns (body, status) for 2xx; throws
    /// APIError otherwise. Handles the refresh-and-retry-once policy.
    private func perform(path: String, method: String = "GET",
                         jsonBody: [String: Any]? = nil,
                         authenticated: Bool = true,
                         isRetry: Bool = false) async throws -> (Data, Int) {
        guard let url = URL(string: AppConfig.apiBase + path) else {
            throw APIError.network("bad URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        if authenticated, let access = tokenStore.accessToken, !access.isEmpty {
            request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        // The session cookies that auth responses also set (used by the
        // dashboard WebView) are mirrored into the Keychain opportunistically.
        SessionStore.shared.captureSessionCookie()

        if response.statusCode == 401 {
            if authenticated && !isRetry {
                let refreshed = await refreshAccessToken()
                if refreshed {
                    return try await perform(path: path, method: method, jsonBody: jsonBody,
                                             authenticated: authenticated, isRetry: true)
                }
            }
            throw APIError.unauthorized
        }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.http(response.statusCode)
        }
        return (data, response.statusCode)
    }

    private func refreshAccessToken() async -> Bool {
        guard let refresh = tokenStore.refreshToken, !refresh.isEmpty else { return false }
        do {
            let (data, _) = try await perform(
                path: "/v1/auth/refresh", method: "POST",
                jsonBody: ["refreshToken": refresh],
                authenticated: false, isRetry: true)
            let response = try decoder.decode(RefreshResponse.self, from: data)
            guard response.ok == true,
                  let access = response.accessToken, !access.isEmpty else { return false }
            tokenStore.accessToken = access
            return true
        } catch {
            return false
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, _) = try await perform(path: path)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any],
                                     authenticated: Bool = true) async throws -> T {
        let (data, _) = try await perform(path: path, method: "POST",
                                          jsonBody: body, authenticated: authenticated)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    // MARK: Session

    func me() async throws -> MeResponse {
        try await get("/me")
    }

    func logout() async {
        _ = try? await perform(path: "/auth/logout")
    }

    /// Public Google OAuth Web client ID (not a secret). Used by the
    /// GoogleSignIn-SDK integration path; the device flow below does
    /// not need it.
    func googleClientId() async throws -> String? {
        let response: ClientIdResponse = try await get("/auth/google/client-id")
        return response.clientId
    }

    // MARK: Mobile auth (device flow + token exchange)

    /// Polls the device-flow status for a login started with
    /// ?mobile_app=1&login_id= — { ok:true, code } once the user has
    /// completed Google OAuth in the system browser.
    func mobileStatus(loginId: String) async throws -> MobileStatusResponse {
        let (data, _) = try await perform(
            path: "/v1/auth/mobile-status?login_id=\(loginId)", authenticated: false)
        do {
            return try decoder.decode(MobileStatusResponse.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    /// Exchanges the one-time device-flow code for the token pair.
    func exchangeCode(_ code: String) async throws -> TokenPairResponse {
        try await post("/v1/auth/google/code", body: ["code": code], authenticated: false)
    }

    /// Exchanges a Google ID token for the token pair — the entry point
    /// a GoogleSignIn-SDK integration calls (the SDK needs an iOS OAuth
    /// client ID from Google Cloud Console; the device flow above is
    /// the shipping flow and needs no extra credential).
    func exchangeIDToken(_ idToken: String) async throws -> TokenPairResponse {
        try await post("/v1/auth/google", body: ["idToken": idToken], authenticated: false)
    }

    // MARK: Pages & catalog

    func pages() async throws -> [Page] {
        let response: PagesResponse = try await get("/pages")
        return response.pages ?? []
    }

    func page(id: String) async throws -> Page {
        let response: PageDetailResponse = try await get("/pages/\(id)")
        guard let page = response.page else { throw APIError.decoding }
        return page
    }

    func createPage(title: String, businessName: String, template: String,
                    website: String?) async throws -> Page {
        var body: [String: Any] = [
            "title": title,
            "business_name": businessName,
            "template": template,
        ]
        if let website {
            body["links"] = ["website": website]
        }
        let response: CreatePageResponse = try await post("/pages", body: body)
        guard let page = response.page else { throw APIError.decoding }
        return page
    }

    func researchPage(pageId: String) async throws -> ResearchResult {
        let response: ResearchResponse = try await post("/pages/\(pageId)/research", body: [:])
        guard response.ok == true else {
            throw APIError.server(response.message ?? response.error ?? "research failed")
        }
        return ResearchResult(productsFound: response.products_found ?? 0,
                              productsKept: response.products_kept ?? 0)
    }

    // MARK: Calls

    func calls(pageId: String? = nil, cursor: String? = nil,
               limit: Int = 50) async throws -> CallsResponse {
        var path = "/calls?limit=\(limit)"
        if let pageId { path += "&page_id=\(pageId)" }
        if let cursor, let encoded = cursor.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) {
            path += "&cursor=\(encoded)"
        }
        return try await get(path)
    }

    func callDetail(id: String) async throws -> CallItem {
        let response: CallDetailResponse = try await get("/calls/\(id)")
        guard let call = response.call else { throw APIError.decoding }
        return call
    }

    func communications(callId: String) async throws -> [Communication] {
        let response: CommunicationsResponse = try await get("/calls/\(callId)/communications")
        return response.communications ?? []
    }

    // MARK: Appointments

    func appointments() async throws -> [Appointment] {
        let response: AppointmentsResponse = try await get("/owner/appointments")
        return response.appointments ?? []
    }

    // MARK: Activity

    func activity(limit: Int = 50) async throws -> [ActivityEvent] {
        let response: ActivityResponse = try await get("/activity?limit=\(limit)")
        return response.events ?? []
    }

    // MARK: Gateways

    func gateways() async throws -> [Gateway] {
        let response: GatewaysResponse = try await get("/gateways")
        return response.gateways ?? []
    }
}
