import Foundation
import Security
import WebKit

/// Persistent session storage — the iOS equivalent of Android's PersistentCookieJar.
///
/// The backend authenticates with an HttpOnly session cookie (cp_session).
/// HTTPCookieStorage.shared persists cookies to disk automatically, which
/// survives app backgrounding/minimization. This store additionally mirrors
/// the session cookie into the Keychain so the login survives even if the
/// cookie jar is ever purged.
final class SessionStore {
    static let shared = SessionStore()
    private let service = "com.callpages.merchant.session"
    private let base = URL(string: "https://callpages.me")!

    private init() {}

    /// Call after any authenticated response: mirrors cp_session into the Keychain.
    func captureSessionCookie() {
        let cookies = HTTPCookieStorage.shared.cookies(for: base) ?? []
        guard let session = cookies.first(where: { $0.name == "cp_session" || $0.name == "session" }) else { return }
        save(key: "cp_session", value: session.value)
    }

    /// Restores the session cookie into the shared jar (e.g. after a purge).
    func restoreSessionCookie() {
        guard let value = load(key: "cp_session"), !value.isEmpty else { return }
        let cookies = HTTPCookieStorage.shared.cookies(for: base) ?? []
        guard !cookies.contains(where: { $0.name == "cp_session" }) else { return }
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: "cp_session",
            .value: value,
            .domain: "callpages.me",
            .path: "/",
            .secure: "TRUE",
        ]
        // Far-future expiry; the server decides the real lifetime via 401s.
        props[.expires] = Date(timeIntervalSinceNow: 365 * 24 * 3600)
        if let cookie = HTTPCookie(properties: props) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    func hasSession() -> Bool {
        restoreSessionCookie()
        let cookies = HTTPCookieStorage.shared.cookies(for: base) ?? []
        return cookies.contains { $0.name == "cp_session" || $0.name == "session" }
    }

    func clear() {
        delete(key: "cp_session")
        HTTPCookieStorage.shared.cookies(for: base)?.forEach {
            HTTPCookieStorage.shared.deleteCookie($0)
        }
        // Also clear WebKit's store (dashboard WebView).
        WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let callpages = records.filter { $0.displayName.contains("callpages") }
            WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: callpages) {}
        }
    }

    // MARK: - Keychain

    private func save(key: String, value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = value.data(using: .utf8)!
        SecItemAdd(add as CFDictionary, nil)
    }

    private func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
