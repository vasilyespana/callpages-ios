import SwiftUI

// MARK: - Calls list (cursor-paginated)

struct CallsView: View {
    @State private var calls: [CallItem] = []
    @State private var nextCursor: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let error, calls.isEmpty {
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                    }
                    .padding()
                } else if calls.isEmpty {
                    Text("No calls yet.").foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(calls) { call in
                            NavigationLink(value: call) {
                                CallRow(call: call)
                            }
                            .onAppear {
                                if call.id == calls.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                        if isLoadingMore {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        }
                    }
                }
            }
            .navigationTitle("Call Logs")
            .navigationDestination(for: CallItem.self) { call in
                CallDetailView(callId: call.id, summaryCall: call)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            let response = try await CallPagesAPI.shared.calls()
            calls = response.calls ?? []
            nextCursor = response.next_cursor
        } catch {
            LoadErrorHandling.handle(error, endpoint: "/api/calls")
            self.error = "Couldn't load calls. Pull to retry."
        }
        isLoading = false
    }

    private func loadMore() async {
        guard let cursor = nextCursor, !cursor.isEmpty, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let response = try await CallPagesAPI.shared.calls(cursor: cursor)
            let more = response.calls ?? []
            let known = Set(calls.map { $0.id })
            calls.append(contentsOf: more.filter { !known.contains($0.id) })
            nextCursor = response.next_cursor
        } catch {
            LoadErrorHandling.handle(error, endpoint: "/api/calls")
            nextCursor = nil
        }
        isLoadingMore = false
    }
}

struct CallRow: View {
    let call: CallItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(call.displayCaller).font(.headline)
                Spacer()
                Text(call.durationLabel)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let summary = call.summary, !summary.isEmpty {
                Text(summary).font(.subheadline).lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(DateFmt.display(call.started_at ?? call.created_at))
                if let product = call.product_name, !product.isEmpty {
                    Text("·").foregroundStyle(.secondary)
                    Text(product)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Call detail (summary + transcript call log + communications)

struct CallDetailView: View {
    let callId: String
    /// The list-row version of the call, shown instantly while the
    /// detail payload (which carries the transcript) loads.
    let summaryCall: CallItem?

    @State private var call: CallItem?
    @State private var communications: [Communication] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && call == nil {
                ProgressView()
            } else if let error, call == nil {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await load() } }
                }
                .padding()
            } else if let call {
                List {
                    Section {
                        LabeledContent("Caller", value: call.displayCaller)
                        if let page = call.page_title, !page.isEmpty {
                            LabeledContent("Page", value: page)
                        }
                        LabeledContent("When",
                                       value: DateFmt.display(call.started_at ?? call.created_at))
                        LabeledContent("Duration", value: call.durationLabel)
                        if let outcome = call.outcome, !outcome.isEmpty {
                            LabeledContent("Outcome", value: outcome)
                        }
                        if let product = call.product_name, !product.isEmpty {
                            LabeledContent("Product", value: product)
                        }
                    }

                    if let summary = call.summary, !summary.isEmpty {
                        Section("Summary") {
                            Text(summary)
                        }
                    }

                    Section("Call log") {
                        if let transcript = call.transcript, !transcript.isEmpty {
                            ForEach(Array(transcript.enumerated()), id: \.offset) { _, turn in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(turn.speakerLabel)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(turn.isAI ? .blue : .secondary)
                                    Text(turn.text ?? "")
                                }
                                .padding(.vertical, 2)
                            }
                        } else {
                            Text("No transcript for this call yet.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !communications.isEmpty {
                        Section("Messages") {
                            ForEach(communications, id: \.stableId) { comm in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text((comm.communication_type ?? "message")
                                            .capitalized)
                                            .font(.caption.weight(.semibold))
                                        Spacer()
                                        Text(DateFmt.display(comm.created_at))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let transcript = comm.transcript, !transcript.isEmpty {
                                        Text(transcript).font(.subheadline)
                                    } else if let status = comm.status, !status.isEmpty {
                                        Text(status).font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Call")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        if call == nil { call = summaryCall }
        async let detailTask = CallPagesAPI.shared.callDetail(id: callId)
        async let commsTask = CallPagesAPI.shared.communications(callId: callId)
        let detail = await try? detailTask
        let comms = await try? commsTask
        if let detail {
            call = detail
        } else if summaryCall == nil {
            // Without even a list row there is nothing honest to show.
            error = "Couldn't load this call."
            AppIntegrityReporter.shared.reportEndpointError(
                endpoint: "/api/calls/:id", statusCode: nil,
                detail: "call detail failed to load")
        }
        communications = comms ?? []
        // Automatic bug reporting: a call with substance but no log
        // anywhere is an impossible state — report it.
        if let call, IntegrityChecks.isCallLogMissing(
            call: call, communicationsCount: communications.count) {
            AppIntegrityReporter.shared.reportCallLogEmpty()
        }
        isLoading = false
    }
}
