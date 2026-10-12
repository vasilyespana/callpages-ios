import Foundation
import Security

/// Keychain storage for the Bearer token pair (access + refresh) — the
/// iOS counterpart of Android's TokenManager (encrypted DataStore).
///
/// The access token is short-lived (15 min); the refresh token is the
/// durable credential and the only thing that decides "signed in" at
/// launch. Tokens never leave the Keychain except into the
/// Authorization header of API requests.
///
/// An in-memory cache sits in front of the Keychain: it keeps reads
/// consistent within the process even where Keychain access is
/// unavailable (unsigned builds have no keychain-access-group
/// entitlement — e.g. the CI test host, where SecItem calls fail with
/// errSecMissingEntitlement). The Keychain remains the persistent
/// store across launches on properly signed installs.
final class TokenStore {
    static let shared = TokenStore()

    private let service: String
    private let accessKey = "access_token"
    private let refreshKey = "refresh_token"
    private var cache: [String: String] = [:]
    private let cacheLock = NSLock()

    /// The service string is injectable so unit tests use an isolated
    /// Keychain namespace and never touch the app's real tokens.
    init(service: String = "com.callpages.merchant.tokens") {
        self.service = service
    }

    var accessToken: String? {
        get { load(accessKey) }
        set {
            if let newValue { save(accessKey, newValue) } else { delete(accessKey) }
        }
    }

    var refreshToken: String? {
        get { load(refreshKey) }
        set {
            if let newValue { save(refreshKey, newValue) } else { delete(refreshKey) }
        }
    }

    var hasRefreshToken: Bool {
        !(refreshToken ?? "").isEmpty
    }

    func savePair(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    func clear() {
        accessToken = nil
        refreshToken = nil
    }

    // MARK: - Keychain primitives

    private func save(_ key: String, _ value: String) {
        cacheLock.lock()
        cache[key] = value
        cacheLock.unlock()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = value.data(using: .utf8)!
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private func load(_ key: String) -> String? {
        cacheLock.lock()
        let cached = cache[key]
        cacheLock.unlock()
        if let cached { return cached }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)
        if let value {
            cacheLock.lock()
            cache[key] = value
            cacheLock.unlock()
        }
        return value
    }

    private func delete(_ key: String) {
        cacheLock.lock()
        cache[key] = nil
        cacheLock.unlock()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
