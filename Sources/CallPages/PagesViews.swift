import SwiftUI

// MARK: - Pages list

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
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                    }
                    .padding()
                } else if pages.isEmpty {
                    Text("No pages yet.").foregroundStyle(.secondary)
                } else {
                    List(pages) { page in
                        NavigationLink(value: page) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(page.displayName).font(.headline)
                                HStack(spacing: 8) {
                                    Text("\(page.product_count ?? page.products.count) products")
                                    Text("·")
                                    Text(page.isActive ? "Active" : "Draft")
                                }
                                .font(.caption).foregroundStyle(.secondary)
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
            let loaded = try await CallPagesAPI.shared.pages()
            pages = loaded
            // Automatic bug reporting: impossible states report
            // themselves — nobody has to notice first.
            if IntegrityChecks.isProductsZeroState(loaded) {
                AppIntegrityReporter.shared.reportProductsZero(pages: loaded.count)
            } else if IntegrityChecks.hasServerCountMismatch(loaded) {
                AppIntegrityReporter.shared.reportPagesMismatch(
                    pages: loaded.count,
                    pagesWithProducts: loaded.filter {
                        IntegrityChecks.configProductCount($0) > 0
                    }.count)
            }
        } catch {
            LoadErrorHandling.handle(error, endpoint: "/api/pages")
            self.error = "Couldn't load pages. Pull to retry."
        }
        isLoading = false
    }
}

// MARK: - Page detail (info + products from config + recent calls)

struct PageDetailView: View {
    let initialPage: Page
    @State private var page: Page
    @State private var calls: [CallItem] = []

    init(page: Page) {
        self.initialPage = page
        _page = State(initialValue: page)
    }

    var body: some View {
        List {
            Section("Page") {
                LabeledContent("Name", value: page.displayName)
                if let slug = page.slug {
                    LabeledContent("Slug", value: slug)
                }
                LabeledContent("Status", value: page.isActive ? "Active" : "Draft")
                LabeledContent("Products", value: "\(page.products.count)")
            }

            if page.products.isEmpty {
                Section("Products") {
                    Text("No products on this page yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(page.collections, id: \.id) { collection in
                    let items = page.products.filter {
                        ($0.collection_ids ?? []).contains(collection.id)
                    }
                    if !items.isEmpty {
                        Section(collection.name ?? "Products") {
                            ForEach(items, id: \.stableKey) { product in
                                ProductRow(product: product)
                            }
                        }
                    }
                }
                let grouped = Set(page.collections.map { $0.id })
                let ungrouped = page.products.filter {
                    Set($0.collection_ids ?? []).isDisjoint(with: grouped)
                }
                if !ungrouped.isEmpty {
                    Section(page.collections.isEmpty ? "Products" : "Other products") {
                        ForEach(ungrouped, id: \.stableKey) { product in
                            ProductRow(product: product)
                        }
                    }
                }
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
        .navigationDestination(for: CallItem.self) { call in
            CallDetailView(callId: call.id, summaryCall: call)
        }
        .task { await load() }
    }

    private func load() async {
        // Refresh the page so the products come from the canonical
        // config of the detail payload (the parity contract).
        do {
            let fresh = try await CallPagesAPI.shared.page(id: initialPage.id)
            page = fresh
            if (fresh.product_count ?? 0) > 0 && fresh.products.isEmpty {
                AppIntegrityReporter.shared.reportPagesMismatch(
                    pages: 1, pagesWithProducts: 0)
            }
        } catch {
            LoadErrorHandling.handle(error, endpoint: "/api/pages/:id")
            // Keep showing the list payload — better than an error wall.
        }
        calls = (try? await CallPagesAPI.shared.calls(pageId: initialPage.id).calls) ?? []
    }
}

private struct ProductRow: View {
    let product: Product

    var body: some View {
        HStack(spacing: 12) {
            if let url = product.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.secondary.opacity(0.15)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName).font(.body)
                if let description = product.description, !description.isEmpty {
                    Text(description).font(.caption)
                        .foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            if !product.displayPrice.isEmpty {
                Text(product.displayPrice).font(.subheadline.weight(.medium))
            }
        }
    }
}
