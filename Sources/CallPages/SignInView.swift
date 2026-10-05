import SwiftUI

struct SignInView: View {
    @StateObject private var auth = AuthService.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("📞 CallPages")
                .font(.largeTitle.bold())
            Text("Merchant dashboard for your CallPages — pages, calls, catalog, and activity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            Button {
                auth.signIn()
            } label: {
                if auth.isLoading {
                    ProgressView()
                } else {
                    Label("Sign in with Google", systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            Spacer()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            PagesView()
                .tabItem { Label("Pages", systemImage: "doc.text") }
            CallsView()
                .tabItem { Label("Calls", systemImage: "phone") }
            ActivityView()
                .tabItem { Label("Activity", systemImage: "bell") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
