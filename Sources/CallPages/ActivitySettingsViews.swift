import SwiftUI

// MARK: - Activity (GET /api/activity → { events: [...] })

struct ActivityView: View {
    @State private var events: [ActivityEvent] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let error {
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                    }
                    .padding()
                } else if events.isEmpty {
                    Text("No activity yet.").foregroundStyle(.secondary)
                } else {
                    List(events, id: \.stableId) { event in
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: event.event_type))
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.displayTitle).font(.body)
                                Text(DateFmt.display(event.ts))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Activity")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func icon(for type: String?) -> String {
        let type = type ?? ""
        if type.hasPrefix("call") { return "phone.fill" }
        if type.hasPrefix("appointment") { return "calendar" }
        if type.hasPrefix("page") { return "doc.text" }
        if type.hasPrefix("login") { return "person.crop.circle" }
        return "bell"
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            events = try await CallPagesAPI.shared.activity()
        } catch {
            LoadErrorHandling.handle(error, endpoint: "/api/activity")
            self.error = "Couldn't load activity. Pull to retry."
        }
        isLoading = false
    }
}

// MARK: - Settings (account + gateways + links + sign out)

struct SettingsView: View {
    @StateObject private var auth = AuthService.shared
    @State private var me: MeResponse?
    @State private var gateways: [Gateway] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let user = me?.user {
                        if let name = user.name, !name.isEmpty {
                            LabeledContent("Name", value: name)
                        }
                        if let email = user.email, !email.isEmpty {
                            LabeledContent("Email", value: email)
                        }
                    } else {
                        Text(isLoading ? "Loading…" : "Account details unavailable")
                            .foregroundStyle(.secondary)
                    }
                    if let plan = me?.plan, !plan.isEmpty {
                        LabeledContent("Plan", value: plan.capitalized)
                    }
                    if let active = me?.plan_active {
                        LabeledContent("Plan active", value: active.value ? "Yes" : "No")
                    }
                }

                Section("Payment gateways") {
                    if gateways.isEmpty {
                        Text(isLoading ? "Loading…" : "No gateways connected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(gateways, id: \.stableId) { gateway in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gateway.displayName)
                                    if let currencies = gateway.supported_currencies?.value,
                                       !currencies.isEmpty {
                                        Text(currencies)
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if gateway.is_primary?.value == true {
                                    Text("Primary")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.blue)
                                }
                                if gateway.is_active?.value == false {
                                    Text("Inactive")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Link("Open dashboard on the web",
                         destination: URL(string: "https://callpages.me/dashboard")!)
                    Link("CallPages home",
                         destination: URL(string: "https://callpages.me/")!)
                }

                Section("About") {
                    LabeledContent("App version", value: AppConfig.appVersionName)
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        auth.signOut()
                    }
                }
            }
            .navigationTitle("Settings")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        me = try? await CallPagesAPI.shared.me()
        gateways = (try? await CallPagesAPI.shared.gateways()) ?? []
        isLoading = false
    }
}
