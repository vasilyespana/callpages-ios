import SwiftUI

struct SignInView: View {
    @StateObject private var auth = AuthService.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("📞 CallPages")
                .font(.largeTitle.bold())
            Text("Merchant dashboard for your CallPages — pages, calls, catalog, appointments, and activity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            if let error = auth.signInError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
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
            .disabled(auth.isLoading)
            .padding(.horizontal, 32)
            Text("Opens Google in your browser — pick the account you already use. No password typing here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
            PagesView()
                .tabItem { Label("Pages", systemImage: "doc.text") }
            CallsView()
                .tabItem { Label("Calls", systemImage: "phone") }
            AppointmentsView()
                .tabItem { Label("Appointments", systemImage: "calendar") }
            ActivityView()
                .tabItem { Label("Activity", systemImage: "bell") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
