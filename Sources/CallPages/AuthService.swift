import Foundation
import AuthenticationServices
import SwiftUI

/// Handles Google OAuth via ASWebAuthenticationSession and keeps the session cookie.
final class AuthService: ObservableObject {
    static let shared = AuthService()
    private let base = "https://callpages.me"

    @Published var isSignedIn = false
    @Published var isLoading = false

    private var authSession: ASWebAuthenticationSession?

    private init() {
        // Restore any persisted session (survives backgrounding/restarts).
        SessionStore.shared.restoreSessionCookie()
        checkSession()
    }

    func checkSession() {
        isSignedIn = SessionStore.shared.hasSession()
    }

    func signIn() {
        guard let authURL = URL(string: "\(base)/api/auth/google") else { return }
        isLoading = true
        authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "callpages",
            completionHandler: { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.isLoading = false
                    self?.checkSession()
                }
            }
        )
        authSession?.presentationContextProvider = ContextProvider()
        authSession?.prefersEphemeralWebBrowserSession = false
        authSession?.start()
    }

    func signOut() {
        guard let url = URL(string: "\(base)/api/auth/logout") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] _, _, _ in
            DispatchQueue.main.async {
                SessionStore.shared.clear()
                self?.isSignedIn = false
            }
        }.resume()
    }
}

private final class ContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

// MARK: - API client

enum APIError: Error {
    case unauthorized
    case http(Int)
    case decoding
}

struct CreatePageResponse: Codable {
    let ok: Bool?
    let page: Page?
}

struct ResearchResponse: Codable {
    let ok: Bool?
    let products_found: Int?
    let products_kept: Int?
    let error: String?
    let message: String?
}

struct ResearchResult {
    let productsFound: Int
    let productsKept: Int
}

final class CallPagesAPI {
    static let shared = CallPagesAPI()
    private let base = "https://callpages.me"
    private let decoder = JSONDecoder()

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpShouldHandleCookies = true
        let (data, resp) = try await URLSession.shared.data(for: req)
        SessionStore.shared.captureSessionCookie()
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 401 { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any?]) async throws -> T {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpShouldHandleCookies = true
        // Strip nils.
        let clean = body.compactMapValues { $0 }
        req.httpBody = try JSONSerialization.data(withJSONObject: clean)
        let (data, resp) = try await URLSession.shared.data(for: req)
        SessionStore.shared.captureSessionCookie()
        if let http = resp as? HTTPURLResponse {
            if http.statusCode == 401 { throw APIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    func pages() async throws -> [Page] {
        let r: PagesResponse = try await get("/api/pages")
        return r.pages ?? []
    }

    func page(id: String) async throws -> Page {
        try await get("/api/pages/\(id)")
    }

    func createPage(title: String, businessName: String, template: String, website: String?) async throws -> Page {
        var body: [String: Any?] = [
            "title": title,
            "business_name": businessName,
            "template": template,
        ]
        if let website {
            body["links"] = ["website": website]
        }
        let r: CreatePageResponse = try await post("/api/pages", body: body)
        guard let page = r.page else { throw APIError.decoding }
        return page
    }

    func researchPage(pageId: String) async throws -> ResearchResult {
        let r: ResearchResponse = try await post("/api/pages/\(pageId)/research", body: [:])
        guard r.ok == true else {
            throw NSError(domain: "research", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: r.message ?? r.error ?? "research failed"])
        }
        return ResearchResult(
            productsFound: r.products_found ?? 0,
            productsKept: r.products_kept ?? 0
        )
    }

    func calls(pageId: String? = nil) async throws -> [CallLog] {
        var path = "/api/calls"
        if let pid = pageId { path += "?page_id=\(pid)" }
        let r: CallsResponse = try await get(path)
        return r.calls ?? []
    }

    func activity() async throws -> [ActivityItem] {
        let r: ActivityResponse = try await get("/api/activity")
        return r.activity ?? []
    }
}
