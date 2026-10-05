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
        // Check for existing session cookie.
        checkSession()
    }

    func checkSession() {
        guard let url = URL(string: base) else { return }
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        isSignedIn = cookies.contains { $0.name == "session" || $0.name == "cp_session" }
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
                if let baseURL = URL(string: self?.base ?? "") {
                    HTTPCookieStorage.shared.cookies(for: baseURL)?.forEach {
                        HTTPCookieStorage.shared.deleteCookie($0)
                    }
                }
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

final class CallPagesAPI {
    static let shared = CallPagesAPI()
    private let base = "https://callpages.me"
    private let decoder = JSONDecoder()

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        let (data, resp) = try await URLSession.shared.data(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
            throw URLError(.userAuthenticationRequired)
        }
        return try decoder.decode(T.self, from: data)
    }

    func pages() async throws -> [Page] {
        let r: PagesResponse = try await get("/api/pages")
        return r.pages ?? []
    }

    func page(id: String) async throws -> Page {
        try await get("/api/pages/\(id)")
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
