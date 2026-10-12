import SwiftUI

@main
struct CallPagesApp: App {
    @StateObject private var auth = AuthService.shared
    /// nil = undecided, false = needs onboarding, true = has pages
    @State private var onboarded: Bool?

    var body: some Scene {
        WindowGroup {
            Group {
                if !auth.isSignedIn {
                    SignInView()
                } else if onboarded == nil {
                    // Validate the session, then run the zero-pages
                    // gate: check on every fresh launch.
                    ProgressView("Loading…")
                        .task {
                            await auth.validateSession()
                            if auth.isSignedIn {
                                onboarded = await checkHasPages()
                            }
                        }
                } else if onboarded == false {
                    NavigationStack {
                        OnboardingView {
                            onboarded = true
                        }
                    }
                } else {
                    MainTabView()
                }
            }
            // Re-check the gate when returning from background — the world
            // may have changed (but the SESSION persists via TokenStore).
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )) { _ in
                auth.appBecameActive()
            }
        }
    }

    private func checkHasPages() async -> Bool {
        do {
            let pages = try await CallPagesAPI.shared.pages()
            return !pages.isEmpty
        } catch APIError.unauthorized {
            auth.expireSession()
            return false
        } catch {
            // On network error, don't trap the user in onboarding —
            // let them into the app; lists will show retry states.
            return true
        }
    }
}
