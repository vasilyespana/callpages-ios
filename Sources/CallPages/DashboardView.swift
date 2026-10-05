import SwiftUI
import WebKit

/// WebView dashboard (parity with Android DashboardScreen).
///
/// CRITICAL: session cookies are synced from the shared HTTPCookieStorage
/// into the WebView's WKWebsiteDataStore BEFORE the first load — the
/// dashboard must open authenticated. If the WebView ever lands on the
/// public landing page instead of the dashboard, that is surfaced as an
/// auth error, never silently.
struct DashboardView: View {
    @State private var loadState: LoadState = .loading
    @State private var webView: WKWebView?

    enum LoadState { case loading, loaded, authError }

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .loading:
                    ProgressView("Loading dashboard…")
                case .loaded:
                    WebViewWrapper(webView: $webView, onAuthError: {
                        loadState = .authError
                    })
                case .authError:
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text("Session expired")
                            .font(.headline)
                        Text("Your login session ended. Please sign in again.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Sign in again") {
                            AuthService.shared.isSignedIn = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct WebViewWrapper: UIViewRepresentable {
    @Binding var webView: WKWebView?
    var onAuthError: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        context.coordinator.onAuthError = onAuthError
        // Sync session cookies BEFORE the first load.
        syncCookies(into: wv) {
            wv.load(URLRequest(url: URL(string: "https://callpages.me/dashboard")!))
        }
        DispatchQueue.main.async { webView = wv }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Copies the session cookies into the WebView's data store before loading.
    private func syncCookies(into wv: WKWebView, done: @escaping () -> Void) {
        SessionStore.shared.restoreSessionCookie()
        let jar = HTTPCookieStorage.shared
        guard let baseURL = URL(string: "https://callpages.me") else { done(); return }
        let cookies = jar.cookies(for: baseURL) ?? []
        let store = wv.configuration.websiteDataStore.httpCookieStore
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) { done() }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onAuthError: (() -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // If we landed on the public landing/marketing page instead of
            // the dashboard, the session is dead — surface it, never silently.
            if let url = webView.url?.absoluteString,
               url == "https://callpages.me/" || url == "https://callpages.me" {
                onAuthError?()
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let ns = error as NSError
            if ns.code == 401 { onAuthError?() }
        }
    }
}
