import Foundation

// MARK: - Fixtures + stub transport (test support)
//
// Canned API responses used by (a) unit tests through StubTransportRecorder
// and (b) the UI-test stub mode (-uitest-stub) through FixtureTransport —
// the same role Android's FakeCallPagesApi plays for its cloud E2E suite.
// All data is invented demo data ("Sleep Shop — Demo", "María Demo").

enum Fixtures {
    static let meJSON = """
    {"ok":true,"user":{"id":"user_demo","email":"demo@example.com","name":"Demo Owner","picture":""},"plan_active":true,"plan":"pro","billing_configured":true}
    """

    static let pagesJSON = """
    {"ok":true,"pages":[
      {"id":"page_demo_1","slug":"sleep-shop-demo","title":"Sleep Shop — Demo","business_name":"Sleep Shop","is_active":1,"status":"active","product_count":3,
       "config":{"collections":[{"id":"c_frames","name":"Frames","sort_order":0},{"id":"c_mattresses","name":"Mattresses","sort_order":1}],
                 "products":[
                   {"id":"p_1","name":"Frame Queen","price":"$110","description":"Heavy-duty steel frame.","collection_ids":["c_frames"]},
                   {"id":"p_2","name":"Frame Twin","price":"$85","description":"Compact steel frame.","collection_ids":["c_frames"]},
                   {"id":"p_3","name":"Mattress Queen 10in","price":"$199","description":"Hybrid mattress.","collection_ids":["c_mattresses"]}]}},
      {"id":"page_demo_2","slug":"consulting-demo","title":"Consulting — Demo","business_name":"Consulting","is_active":1,"status":"active","product_count":0,
       "config":{"collections":[],"products":[]}}
    ]}
    """

    static let emptyPagesJSON = """
    {"ok":true,"pages":[]}
    """

    static let pageDetailJSON = """
    {"ok":true,"page":{"id":"page_demo_1","slug":"sleep-shop-demo","title":"Sleep Shop — Demo","business_name":"Sleep Shop","is_active":1,"status":"active","product_count":3,
       "config":{"collections":[{"id":"c_frames","name":"Frames","sort_order":0},{"id":"c_mattresses","name":"Mattresses","sort_order":1}],
                 "products":[
                   {"id":"p_1","name":"Frame Queen","price":"$110","description":"Heavy-duty steel frame.","collection_ids":["c_frames"]},
                   {"id":"p_2","name":"Frame Twin","price":"$85","description":"Compact steel frame.","collection_ids":["c_frames"]},
                   {"id":"p_3","name":"Mattress Queen 10in","price":"$199","description":"Hybrid mattress.","collection_ids":["c_mattresses"]}]}}}
    """

    static let createdPageJSON = """
    {"ok":true,"page":{"id":"page_demo_new","slug":"new-demo","title":"New Demo Business","business_name":"New Demo Business","is_active":0,"status":"setup","product_count":0,"config":{"collections":[],"products":[]}}}
    """

    static let researchJSON = """
    {"ok":true,"products_found":4,"products_kept":3}
    """

    static let callsJSON = """
    {"ok":true,"calls":[
      {"id":"call_demo_1","page_id":"page_demo_1","caller_name":"María Demo","caller_phone":"+1 787-555-0101","summary":"Caller asked about a Queen frame and pickup times.","outcome":"booked","duration_ms":61000,"started_at":"2026-10-10T10:00:00Z","created_at":"2026-10-10T10:00:00Z","product_name":"Frame Queen","page_title":"Sleep Shop — Demo"},
      {"id":"call_demo_2","page_id":"page_demo_1","caller_name":"Walk-in Demo","caller_phone":"+1 787-555-0102","summary":"Asked about delivery to Bayamón.","outcome":"info","duration_ms":30000,"started_at":"2026-10-09T09:00:00Z","created_at":"2026-10-09T09:00:00Z","page_title":"Sleep Shop — Demo"}
    ],"next_cursor":null}
    """

    static let callDetailJSON = """
    {"ok":true,"call":{"id":"call_demo_1","page_id":"page_demo_1","caller_name":"María Demo","caller_phone":"+1 787-555-0101","summary":"Caller asked about a Queen frame and pickup times.","outcome":"booked","duration_seconds":61,"duration_ms":61000,"started_at":"2026-10-10T10:00:00Z","created_at":"2026-10-10T10:00:00Z","product_name":"Frame Queen","page_title":"Sleep Shop — Demo",
      "transcript":[
        {"role":"caller","text":"Hola, ¿tienen frames Queen disponibles?","ts":"0"},
        {"role":"ai","text":"Sí, tenemos el Frame Queen en $110. ¿Desea recogerlo hoy?","ts":"5"},
        {"role":"caller","text":"Perfecto, paso a la 1 de la tarde.","ts":"12"}
      ]}}
    """

    static let communicationsJSON = """
    {"ok":true,"communications":[
      {"id":"comm_demo_1","sender_type":"merchant","communication_type":"voicemail","status":"delivered","transcript":"Hi María, your Queen frame is ready for pickup.","duration_seconds":9,"created_at":"2026-10-10T10:05:00Z"}
    ]}
    """

    static let appointmentsJSON = """
    {"ok":true,"appointments":[
      {"id":"appt_demo_1","page_id":"page_demo_1","page_slug":"sleep-shop-demo","page_business":"Sleep Shop","customer_name":"María Demo","customer_phone":"+1 787-555-0101","start_at":"2026-10-12T13:00:00Z","end_at":"2026-10-12T13:30:00Z","notes":"Pickup: Frame Queen","status":"confirmed","sync_status":"synced","event_link":"https://www.google.com/calendar/event?eid=demo","created_at":"2026-10-10T10:01:00Z"},
      {"id":"appt_demo_2","page_id":"page_demo_1","page_slug":"sleep-shop-demo","page_business":"Sleep Shop","customer_name":"Juan Demo","customer_phone":"+1 787-555-0103","start_at":"2026-10-13T15:00:00Z","end_at":"2026-10-13T15:30:00Z","notes":"Delivery consult","status":"confirmed","sync_status":"pending","created_at":"2026-10-10T11:00:00Z"}
    ]}
    """

    static let activityJSON = """
    {"ok":true,"events":[
      {"id":"evt_demo_1","event_type":"call_completed","channel":"voice","page_id":"page_demo_1","page_title":"Sleep Shop — Demo","slug":"sleep-shop-demo","ts":"2026-10-10T10:01:00Z"},
      {"id":"evt_demo_2","event_type":"appointment_booked","channel":"voice","page_id":"page_demo_1","page_title":"Sleep Shop — Demo","slug":"sleep-shop-demo","ts":"2026-10-10T10:02:00Z"}
    ]}
    """

    static let gatewaysJSON = """
    {"ok":true,"gateways":[
      {"id":"gw_demo_1","gateway_type":"stripe","is_primary":1,"is_active":1,"failover_order":0,"supported_currencies":"USD"}
    ]}
    """

    static let tokenPairJSON = """
    {"ok":true,"accessToken":"stub-access-token","refreshToken":"stub-refresh-token","expiresIn":900}
    """

    static let refreshJSON = """
    {"ok":true,"accessToken":"stub-access-token-2","expiresIn":900}
    """

    static func jsonData(_ string: String) -> Data {
        Data(string.utf8)
    }
}

/// Answers API requests from Fixtures, keyed by URL path. Used only in
/// UI-test stub mode (never in a normal launch).
struct FixtureTransport: HTTPTransport {
    let emptyAccount: Bool

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? AppConfig.baseURL
        let path = url.path
        let body: String
        switch true {
        case path == "/api/me":
            body = Fixtures.meJSON
        case path == "/api/pages" && request.httpMethod == "POST":
            body = Fixtures.createdPageJSON
        case path == "/api/pages":
            body = emptyAccount ? Fixtures.emptyPagesJSON : Fixtures.pagesJSON
        case path.hasPrefix("/api/pages/") && path.hasSuffix("/research"):
            body = Fixtures.researchJSON
        case path.hasPrefix("/api/pages/"):
            body = Fixtures.pageDetailJSON
        case path == "/api/calls":
            body = Fixtures.callsJSON
        case path.hasPrefix("/api/calls/") && path.hasSuffix("/communications"):
            body = Fixtures.communicationsJSON
        case path.hasPrefix("/api/calls/"):
            body = Fixtures.callDetailJSON
        case path == "/api/owner/appointments":
            body = Fixtures.appointmentsJSON
        case path == "/api/activity":
            body = Fixtures.activityJSON
        case path == "/api/gateways":
            body = Fixtures.gatewaysJSON
        case path == "/api/v1/auth/mobile-status":
            body = "{\"ok\":false}"
        case path == "/api/v1/auth/google/code" || path == "/api/v1/auth/google":
            body = Fixtures.tokenPairJSON
        case path == "/api/v1/auth/refresh":
            body = Fixtures.refreshJSON
        default:
            body = "{\"ok\":true}"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Fixtures.jsonData(body), response)
    }
}
