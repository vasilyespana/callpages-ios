import SwiftUI

@main
struct CallPagesApp: App {
    @StateObject private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            if auth.isSignedIn {
                MainTabView()
            } else {
                SignInView()
            }
        }
    }
}
