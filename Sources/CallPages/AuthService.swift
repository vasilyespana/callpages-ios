import Foundation
import AuthenticationServices
import SwiftUI

/// Sign-in and session lifecycle — parity with Android's AuthManager.
///
/// Primary flow (native, no password typing): the app opens the system
/// browser (ASWebAuthenticationSession — never an embedded WebView;
/// Google blocks OAuth inside WebViews) at
/// /api/auth/google?mobile_app=1&login_id=<uuid>. The system browser
/// presents Google's account picker with the accounts already signed in
/// on the device. On completion the worker mints a one-time code; the
/// app either receives it through the session callback or polls
/// GET /api/v1/auth/mobile-status for it (device flow — the polling
/// path needs no URL-scheme interception and is the reliable route on
/// iOS), then exchanges it at POST /api/v1/auth/google/code for the
/// Bearer token pair. Tokens live in the Keychain (TokenStore); the
/// API client refreshes the access token automatically.
///
/// The ID-token exchange (POST /api/v1/auth/google) is also implemented
/// (signInWithIDToken) — it is the entry point a GoogleSignIn-SDK
/// integration calls once an iOS OAuth client ID exists in Google
/// Cloud Console.
///
/// EVERY failure in every step reports through SignInFailureReporter
/// before surfacing, mirroring Android: failure capture ships in v1.
final class AuthService: ObservableObject {
    static let shared = AuthService()

    /// Flow label used in failure reports (mirrors Android's flow ids).
    static let deviceFlowName = "aswebauth-device-flow"

    @Published var isSignedIn = false
    @Published var isLoading = false
    @Published var signInError: String?

    /// Last validated account payload (GET /api/me).
    private(set) var me: MeResponse?

    private var authSession: ASWebAuthenticationSession?
    private var pollTask: Task<Void, Never>?
    private var signInCompleted = false

    private init() {
        // Optimistic signed-in state from the durable credential; the
        // root gate validates it against /api/me before showing data.
        isSignedIn = AppConfig.isStubMode || TokenStore.shared.hasRefreshToken
        SessionStore.shared.restoreSessionCookie()
    }

    // MARK: - Session state

    /// Marks the session signed in after a successful validation.
    func markSignedIn(me: MeResponse?) {
        if let me { self.me = me }
        DispatchQueue.main.async { self.isSignedIn = true }
    }

    /// The session is dead (401 after refresh): clear everything and
    /// route back to sign-in.
    func expireSession() {
        TokenStore.shared.clear()
        me = nil
        DispatchQueue.main.async { self.isSignedIn = false }
    }

    /// Validates the stored session against /api/me. A 401 expires the
    /// session; a network error leaves the optimistic state alone (the
    /// lists surface their own retry states).
    func validateSession() async {
        if AppConfig.isStubMode {
            me = try? await CallPagesAPI.shared.me()
            return
        }
        guard TokenStore.shared.hasRefreshToken else {
            DispatchQueue.main.async { self.isSignedIn = false }
            return
        }
        do {
            let me = try await CallPagesAPI.shared.me()
            markSignedIn(me: me)
        } catch APIError.unauthorized {
            expireSession()
        } catch {
            // Offline or server blip: keep the optimistic state.
        }
    }

    /// Foreground re-check (the world may have changed while the app
    /// was backgrounded — but the session itself persists).
    func appBecameActive() {
        if !AppConfig.isStubMode, isSignedIn, !TokenStore.shared.hasRefreshToken {
            DispatchQueue.main.async { self.isSignedIn = false }
        }
    }

    // MARK: - Sign-in (device flow)

    func signIn() {
        guard !isLoading else { return }
        signInError = nil
        isLoading = true
        signInCompleted = false

        let loginId = UUID().uuidString
        var components = URLComponents(string: AppConfig.apiBase + "/auth/google")
        components?.queryItems = [
            URLQueryItem(name: "mobile_app", value: "1"),
            URLQueryItem(name: "login_id", value: loginId),
        ]
        guard let authURL = components?.url else {
            SignInFailureReporter.report(flow: Self.deviceFlowName, step: "open-auth-session",
                                         exceptionClass: "BadAuthURL")
            finishWithError("Couldn't start sign-in. Please try again.")
            return
        }

        pollTask = Task { [weak self] in
            await self?.pollForCode(loginId: loginId)
        }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "callpages",
            completionHandler: { [weak self] callbackURL, error in
                self?.handleSessionEnd(callbackURL: callbackURL, error: error)
            })
        session.presentationContextProvider = AuthPresentationContext.shared
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        if !session.start() {
            SignInFailureReporter.report(flow: Self.deviceFlowName, step: "open-auth-session",
                                         exceptionClass: "ASWebAuthenticationSessionStartFailed")
            finishWithError("Couldn't open the browser sign-in. Please try again.")
        }
    }

    private func handleSessionEnd(callbackURL: URL?, error: Error?) {
        // Fast path: the return was intercepted with the code attached.
        if let callbackURL,
           let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
               .queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            Task { [weak self] in await self?.finishSignIn(code: code) }
            return
        }
        if let error {
            // If polling already completed the sign-in, the session's
            // cancellation (triggered by us) lands here — ignore it.
            guard !signInCompleted else { return }
            let nsError = error as NSError
            if nsError.domain == ASWebAuthenticationSessionErrorDomain,
               nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                SignInFailureReporter.report(
                    flow: Self.deviceFlowName, step: "aswebauth-session",
                    exceptionClass: "ASWebAuthenticationSessionError.canceledLogin",
                    message: "user cancelled")
                finishWithError(nil)
            } else {
                SignInFailureReporter.report(
                    flow: Self.deviceFlowName, step: "aswebauth-session", error: error)
                finishWithError("Sign-in didn't complete. Please try again.")
            }
        }
        // No code and no error: the browser flow ended without an
        // intercepted return — polling remains the source of truth and
        // will finish (or time out) on its own.
    }

    /// Device-flow polling: ~5 minutes at 2s intervals, mirroring
    /// Android's pollMobileCode.
    private func pollForCode(loginId: String) async {
        for _ in 0..<150 {
            if signInCompleted || Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if signInCompleted || Task.isCancelled { return }
            do {
                let status = try await CallPagesAPI.shared.mobileStatus(loginId: loginId)
                if status.ok == true, let code = status.code, !code.isEmpty {
                    await finishSignIn(code: code)
                    return
                }
            } catch {
                // Keep polling — a server blip must not kill a sign-in
                // the user is still completing in the browser.
            }
        }
        guard !signInCompleted else { return }
        SignInFailureReporter.report(flow: Self.deviceFlowName, step: "poll-mobile-status",
                                     exceptionClass: "AuthError.timeout",
                                     message: "no code after ~5 minutes of polling")
        // Mark completed first so the session's cancellation callback
        // (triggered by our own cancel) doesn't clear the timeout error.
        signInCompleted = true
        authSession?.cancel()
        finishWithError("Sign-in timed out. Please try again.")
    }

    private func finishSignIn(code: String) async {
        guard !signInCompleted else { return }
        signInCompleted = true
        pollTask?.cancel()
        authSession?.cancel()
        authSession = nil
        do {
            let pair = try await CallPagesAPI.shared.exchangeCode(code)
            guard pair.ok == true,
                  let access = pair.accessToken, !access.isEmpty,
                  let refresh = pair.refreshToken, !refresh.isEmpty else {
                SignInFailureReporter.report(flow: Self.deviceFlowName, step: "exchange-code",
                                             exceptionClass: "BadResponse",
                                             message: "token pair missing from exchange response")
                finishWithError("Sign-in didn't complete. Please try again.")
                return
            }
            TokenStore.shared.savePair(accessToken: access, refreshToken: refresh)
            // The exchange response also sets the web session cookies —
            // mirror them for the dashboard WebView.
            SessionStore.shared.captureSessionCookie()
            let me = try await CallPagesAPI.shared.me()
            self.me = me
            DispatchQueue.main.async {
                self.isLoading = false
                self.isSignedIn = true
            }
        } catch APIError.http(let status) {
            SignInFailureReporter.report(flow: Self.deviceFlowName, step: "exchange-code",
                                         exceptionClass: "HttpError", statusCode: status)
            finishWithError("Sign-in didn't complete. Please try again.")
        } catch {
            SignInFailureReporter.report(flow: Self.deviceFlowName, step: "exchange-code",
                                         error: error)
            finishWithError("Sign-in didn't complete. Please try again.")
        }
    }

    // MARK: - Sign-in (ID-token exchange; GoogleSignIn SDK entry point)

    /// Exchanges a Google ID token for the app token pair — the call a
    /// GoogleSignIn-SDK integration makes after its account picker.
    /// Returns true on success; failures are reported with the same
    /// step labels Android uses ("exchange-id-token").
    func signInWithIDToken(_ idToken: String) async -> Bool {
        guard !idToken.isEmpty else { return false }
        do {
            let pair = try await CallPagesAPI.shared.exchangeIDToken(idToken)
            guard pair.ok == true,
                  let access = pair.accessToken, !access.isEmpty,
                  let refresh = pair.refreshToken, !refresh.isEmpty else {
                SignInFailureReporter.report(flow: "googlesignin-sdk", step: "exchange-id-token",
                                             exceptionClass: "BadResponse")
                return false
            }
            TokenStore.shared.savePair(accessToken: access, refreshToken: refresh)
            SessionStore.shared.captureSessionCookie()
            let me = try await CallPagesAPI.shared.me()
            self.me = me
            DispatchQueue.main.async { self.isSignedIn = true }
            return true
        } catch APIError.http(let status) {
            SignInFailureReporter.report(flow: "googlesignin-sdk", step: "exchange-id-token",
                                         exceptionClass: "HttpError", statusCode: status)
            return false
        } catch {
            SignInFailureReporter.report(flow: "googlesignin-sdk", step: "exchange-id-token",
                                         error: error)
            return false
        }
    }

    // MARK: - Sign-out

    func signOut() {
        pollTask?.cancel()
        authSession?.cancel()
        Task { await CallPagesAPI.shared.logout() }
        TokenStore.shared.clear()
        SessionStore.shared.clear()
        me = nil
        DispatchQueue.main.async { self.isSignedIn = false }
    }

    private func finishWithError(_ message: String?) {
        pollTask?.cancel()
        DispatchQueue.main.async {
            self.isLoading = false
            self.signInError = message
        }
    }
}

/// Retained presentation-context provider for ASWebAuthenticationSession
/// (the session holds it weakly, so it must be a shared instance).
private final class AuthPresentationContext: NSObject,
        ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
