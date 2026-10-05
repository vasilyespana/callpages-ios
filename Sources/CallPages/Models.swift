import Foundation

// MARK: - API models (CallPages worker)

struct Page: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let slug: String?
    let is_active: Int?
    let product_count: Int?

    var displayName: String { name ?? slug ?? id }
}

struct PagesResponse: Codable {
    let pages: [Page]?
}

struct CallLog: Codable, Identifiable, Hashable {
    let id: String
    let page_id: String?
    let started_at: String?
    let duration_sec: Int?
    let from_number: String?
    let summary: String?
    let transcript: String?
    let recording_url: String?
}

struct CallsResponse: Codable {
    let calls: [CallLog]?
}

struct ActivityItem: Codable, Identifiable, Hashable {
    let id: String
    let type: String?
    let text: String?
    let created_at: String?
}

struct ActivityResponse: Codable {
    let activity: [ActivityItem]?
}

struct Product: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let price: Double?
    let description: String?
    let image_url: String?

    var displayPrice: String {
        if let p = price { return String(format: "$%.2f", p) }
        return ""
    }
}
