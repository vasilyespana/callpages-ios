import SwiftUI

// MARK: - Pages (dashboard)

struct PagesView: View {
    @State private var pages: [Page] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let error {
                    Text(error).foregroundStyle(.red)
                } else if pages.isEmpty {
                    Text("No pages yet.").foregroundStyle(.secondary)
                } else {
                    List(pages) { page in
                        NavigationLink(value: page) {
                            VStack(alignment: .leading) {
                                Text(page.displayName).font(.headline)
                                if let count = page.product_count {
                                    Text("\(count) products")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Pages")
            .navigationDestination(for: Page.self) { page in
                PageDetailView(page: page)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            pages = try await CallPagesAPI.shared.pages()
        } catch {
            self.error = "Couldn't load pages. Pull to retry."
        }
        isLoading = false
    }
}

struct PageDetailView: View {
    let page: Page
    @State private var calls: [CallLog] = []

    var body: some View {
        List {
            Section("Page") {
                LabeledContent("Name", value: page.displayName)
                if let slug = page.slug {
                    LabeledContent("Slug", value: slug)
                }
                LabeledContent("Status", value: (page.is_active == 1) ? "Active" : "Draft")
            }
            Section("Recent calls") {
                if calls.isEmpty {
                    Text("No calls yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(calls.prefix(5)) { call in
                        NavigationLink(value: call) {
                            CallRow(call: call)
                        }
                    }
                }
            }
        }
        .navigationTitle(page.displayName)
        .navigationDestination(for: CallLog.self) { call in
            CallDetailView(call: call)
        }
        .task {
            calls = (try? await CallPagesAPI.shared.calls(pageId: page.id)) ?? []
        }
    }
}

// MARK: - Calls

struct CallsView: View {
    @State private var calls: [CallLog] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if calls.isEmpty {
                    Text("No calls yet.").foregroundStyle(.secondary)
                } else {
                    List(calls) { call in
                        NavigationLink(value: call) {
                            CallRow(call: call)
                        }
                    }
                }
            }
            .navigationTitle("Call Logs")
            .navigationDestination(for: CallLog.self) { call in
                CallDetailView(call: call)
            }
            .task {
                calls = (try? await CallPagesAPI.shared.calls()) ?? []
                isLoading = false
            }
            .refreshable {
                calls = (try? await CallPagesAPI.shared.calls()) ?? []
            }
        }
    }
}

struct CallRow: View {
    let call: CallLog
    var body: some View {
        VStack(alignment: .leading) {
            Text(call.from_number ?? "Unknown caller").font(.headline)
            if let summary = call.summary {
                Text(summary).font(.subheadline).lineLimit(2)
            }
            if let started = call.started_at {
                Text(started).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct CallDetailView: View {
    let call: CallLog
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let summary = call.summary {
                    Text("Summary").font(.headline)
                    Text(summary)
                }
                if let transcript = call.transcript {
                    Text("Transcript").font(.headline)
                    Text(transcript).font(.body)
                }
            }
            .padding()
        }
        .navigationTitle("Call")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Activity

struct ActivityView: View {
    @State private var items: [ActivityItem] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if items.isEmpty {
                    Text("No activity yet.").foregroundStyle(.secondary)
                } else {
                    List(items) { item in
                        VStack(alignment: .leading) {
                            Text(item.text ?? item.type ?? "").font(.body)
                            if let at = item.created_at {
                                Text(at).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Activity")
            .task {
                items = (try? await CallPagesAPI.shared.activity()) ?? []
                isLoading = false
            }
            .refreshable {
                items = (try? await CallPagesAPI.shared.activity()) ?? []
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @StateObject private var auth = AuthService.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Link("Open dashboard on the web",
                         destination: URL(string: "https://callpages.me/dashboard")!)
                    Link("CallPages home",
                         destination: URL(string: "https://callpages.me/")!)
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        auth.signOut()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
