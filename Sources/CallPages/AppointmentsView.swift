import SwiftUI

// MARK: - Appointments (GET /api/owner/appointments)

struct AppointmentsView: View {
    @State private var appointments: [Appointment] = []
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
                } else if appointments.isEmpty {
                    Text("No appointments yet.").foregroundStyle(.secondary)
                } else {
                    List(appointments) { appointment in
                        NavigationLink(value: appointment) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appointment.displayCustomer).font(.headline)
                                Text(DateFmt.display(appointment.start_at))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                if let business = appointment.page_business,
                                   !business.isEmpty {
                                    Text(business)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Appointments")
            .navigationDestination(for: Appointment.self) { appointment in
                AppointmentDetailView(appointment: appointment)
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            appointments = try await CallPagesAPI.shared.appointments()
        } catch {
            LoadErrorHandling.handle(error, endpoint: "/api/owner/appointments")
            self.error = "Couldn't load appointments. Pull to retry."
        }
        isLoading = false
    }
}

struct AppointmentDetailView: View {
    let appointment: Appointment

    var body: some View {
        List {
            Section {
                LabeledContent("Customer", value: appointment.displayCustomer)
                if let phone = appointment.customer_phone, !phone.isEmpty {
                    LabeledContent("Phone", value: phone)
                }
                LabeledContent("Starts", value: DateFmt.display(appointment.start_at))
                if let end = appointment.end_at, !end.isEmpty {
                    LabeledContent("Ends", value: DateFmt.display(end))
                }
                if let business = appointment.page_business, !business.isEmpty {
                    LabeledContent("Page", value: business)
                }
                if let status = appointment.status, !status.isEmpty {
                    LabeledContent("Status", value: status)
                }
                if let sync = appointment.sync_status, !sync.isEmpty {
                    LabeledContent("Calendar sync", value: sync)
                }
            }
            if let notes = appointment.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }
            if let link = appointment.event_link, let url = URL(string: link) {
                Section {
                    Link("Open in Google Calendar", destination: url)
                }
            }
        }
        .navigationTitle("Appointment")
        .navigationBarTitleDisplayMode(.inline)
    }
}
