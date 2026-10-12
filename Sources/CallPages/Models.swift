import Foundation

// MARK: - Flexible scalar decoding
//
// The worker's JSON mixes types for the same conceptual fields across
// endpoints (booleans as 0/1, timestamps as strings or numbers, prices as
// "$110" strings or numbers). Strict Codable types made the previous iOS
// models silently drop or fail whole payloads — the same class of bug as
// Android v1.4.1's missing `config`. These wrappers decode liberally so a
// shape drift degrades one field, never the whole screen.

/// Decodes a Bool from `true/false` or `1/0`.
struct FlexibleBool: Codable, Hashable {
    let value: Bool
    init(_ value: Bool) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let number = try? container.decode(Int.self) {
            value = number != 0
        } else {
            value = false
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Decodes a String from a JSON string or number.
struct FlexibleString: Codable, Hashable {
    let value: String
    init(_ value: String) { self.value = value }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else {
            value = ""
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Session / account (GET /api/me)

struct UserInfo: Codable, Hashable {
    let id: String?
    let email: String?
    let name: String?
    let picture: String?
}

struct MeResponse: Codable {
    let ok: Bool?
    let user: UserInfo?
    let plan_active: FlexibleBool?
    let plan: String?
    let billing_configured: FlexibleBool?
}

// MARK: - Auth token contract (POST /api/v1/auth/*)
//
// The same Bearer session contract the Android app uses post-#219:
// short-lived access JWT + long-lived refresh token, issued by
// /api/v1/auth/google (ID-token exchange) and /api/v1/auth/google/code
// (one-time device-flow code exchange).

struct TokenPairResponse: Codable {
    let ok: Bool?
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
}

struct RefreshResponse: Codable {
    let ok: Bool?
    let accessToken: String?
    let expiresIn: Int?
}

struct MobileStatusResponse: Codable {
    let ok: Bool?
    let code: String?
}

struct ClientIdResponse: Codable {
    let ok: Bool?
    let clientId: String?
}

// MARK: - Pages & catalog (GET /api/pages, GET /api/pages/:id)
//
// PARITY CONTRACT (#240): products and collections live in the page's
// canonical `config` — page.config.products[] / config.collections[].
// The flattened `product_count` is the server's count of the same data;
// the integrity checks cross-check the two (see IntegrityChecks).

struct Product: Codable, Hashable {
    let id: String?
    let name: String?
    let title: String?
    let price: FlexibleString?
    let description: String?
    let image_url: String?
    let photo_url: String?
    let collection_ids: [String]?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let title, !title.isEmpty { return title }
        return "Untitled product"
    }
    var displayPrice: String { price?.value ?? "" }
    var imageURL: URL? {
        let raw = image_url ?? photo_url
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
    /// Stable ForEach key: backend id when present, else the name.
    var stableKey: String { id ?? displayName }
}

struct PageCollection: Codable, Hashable {
    let id: String
    let name: String?
    let sort_order: Int?
}

struct PageConfig: Codable, Hashable {
    let products: [Product]?
    let collections: [PageCollection]?
}

struct Page: Codable, Identifiable, Hashable {
    let id: String
    let slug: String?
    let title: String?
    let business_name: String?
    let is_active: Int?
    let status: String?
    let product_count: Int?
    let config: PageConfig?

    var displayName: String {
        if let title, !title.isEmpty { return title }
        if let business_name, !business_name.isEmpty { return business_name }
        return slug ?? id
    }
    var isActive: Bool { is_active == 1 }
    var products: [Product] { config?.products ?? [] }
    var collections: [PageCollection] {
        (config?.collections ?? []).sorted { ($0.sort_order ?? 0) < ($1.sort_order ?? 0) }
    }
}

struct PagesResponse: Codable {
    let ok: Bool?
    let pages: [Page]?
}

struct PageDetailResponse: Codable {
    let ok: Bool?
    let page: Page?
}

struct CreatePageResponse: Codable {
    let ok: Bool?
    let page: Page?
}

struct ResearchResponse: Codable {
    let ok: Bool?
    let products_found: Int?
    let products_kept: Int?
    let error: String?
    let message: String?
}

struct ResearchResult {
    let productsFound: Int
    let productsKept: Int
}

// MARK: - Calls (GET /api/calls, GET /api/calls/:id, .../communications)
//
// List rows carry summary + duration_ms. The DETAIL payload carries the
// transcript — an array of {role, text, ts} turns (worker maps the
// dialer's who:"agent"|"caller" to role:"ai"|"caller"). That transcript
// IS the call log. The communications thread is a separate list
// (callback / voicemail history) and is empty for ordinary voice calls.

struct TranscriptTurn: Codable, Hashable {
    let role: String?
    let text: String?
    let ts: FlexibleString?

    var isAI: Bool { role == "ai" || role == "agent" }
    var speakerLabel: String { isAI ? "AI agent" : "Caller" }
}

struct CallItem: Codable, Identifiable, Hashable {
    let id: String
    let page_id: String?
    let caller_name: String?
    let caller_phone: String?
    let summary: String?
    let outcome: String?
    let created_at: String?
    let started_at: String?
    let duration_ms: Int?
    let duration_seconds: Int?
    let product_name: String?
    let page_title: String?
    let transcript: [TranscriptTurn]?

    var durationSeconds: Int {
        duration_seconds ?? ((duration_ms ?? 0) / 1000)
    }
    var displayCaller: String {
        if let caller_name, !caller_name.isEmpty { return caller_name }
        if let caller_phone, !caller_phone.isEmpty { return caller_phone }
        return "Unknown caller"
    }
    var durationLabel: String {
        let total = durationSeconds
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct CallsResponse: Codable {
    let ok: Bool?
    let calls: [CallItem]?
    let next_cursor: String?
}

struct CallDetailResponse: Codable {
    let ok: Bool?
    let call: CallItem?
}

struct Communication: Codable, Identifiable, Hashable {
    let id: FlexibleString
    let sender_type: String?
    let communication_type: String?
    let status: String?
    let transcript: String?
    let audio_recording_url: String?
    let duration_seconds: Int?
    let created_at: String?

    var stableId: String { id.value }
}

struct CommunicationsResponse: Codable {
    let ok: Bool?
    let communications: [Communication]?
}

// MARK: - Appointments (GET /api/owner/appointments)

struct Appointment: Codable, Identifiable, Hashable {
    let id: String
    let page_id: String?
    let page_slug: String?
    let page_business: String?
    let customer_name: String?
    let customer_phone: String?
    let start_at: String?
    let end_at: String?
    let notes: String?
    let status: String?
    let sync_status: String?
    let event_link: String?
    let created_at: String?

    var displayCustomer: String {
        if let customer_name, !customer_name.isEmpty { return customer_name }
        if let customer_phone, !customer_phone.isEmpty { return customer_phone }
        return "Appointment"
    }
}

struct AppointmentsResponse: Codable {
    let ok: Bool?
    let appointments: [Appointment]?
}

// MARK: - Activity (GET /api/activity)
//
// Response shape: { ok, events: [{ id, event_type, channel, page_id,
// page_title, slug, ts, data }] }. (The pre-parity iOS app expected
// { activity: [{ type, text, created_at }] } — a shape the worker has
// never sent, so its Activity tab could only ever be empty.)

struct ActivityEvent: Codable, Identifiable, Hashable {
    let id: FlexibleString
    let event_type: String?
    let channel: String?
    let page_id: String?
    let page_title: String?
    let slug: String?
    let ts: String?

    var stableId: String { id.value }
    var displayTitle: String {
        let type = (event_type ?? "event").replacingOccurrences(of: "_", with: " ")
        if let page_title, !page_title.isEmpty { return "\(type) · \(page_title)" }
        return type
    }
}

struct ActivityResponse: Codable {
    let ok: Bool?
    let events: [ActivityEvent]?
}

// MARK: - Payment gateways (GET /api/gateways)

struct Gateway: Codable, Hashable {
    let id: String?
    let gateway_type: String?
    let is_primary: FlexibleBool?
    let is_active: FlexibleBool?
    let failover_order: Int?
    let supported_currencies: FlexibleString?

    var stableId: String { id ?? (gateway_type ?? "gateway") }
    var displayName: String {
        switch gateway_type {
        case "stripe": return "Stripe"
        case "paypal": return "PayPal"
        case "mercadopago": return "MercadoPago"
        case "ath_movil": return "ATH Móvil"
        case "manual": return "Manual / Cash"
        default: return gateway_type ?? "Gateway"
        }
    }
}

struct GatewaysResponse: Codable {
    let ok: Bool?
    let gateways: [Gateway]?
}
