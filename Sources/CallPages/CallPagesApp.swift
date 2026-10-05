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
                    // Zero-pages gate: check on every launch.
                    ProgressView("Loading…")
                        .task {
                            let hasPages = await checkHasPages()
                            onboarded = hasPages
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
            // may have changed (but the SESSION persists via SessionStore).
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )) { _ in
                auth.checkSession()
            }
        }
    }

    private func checkHasPages() async -> Bool {
        do {
            let pages = try await CallPagesAPI.shared.pages()
            return !pages.isEmpty
        } catch APIError.unauthorized {
            await MainActor.run { auth.isSignedIn = false }
            return false
        } catch {
            // On network error, don't trap the user in onboarding —
            // let them into the app; lists will show retry states.
            return true
        }
    }
}
