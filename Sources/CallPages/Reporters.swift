import Foundation

// MARK: - Integrity checks (pure, unit-tested)
//
// Impossible-state detectors for automatic bug reporting — the iOS port
// of Android's IntegrityChecks.kt (2026-10-11 parity program). Pure
// functions over already-parsed models, cheap enough to run on every
// refresh. Each check maps to a symptom that previously needed the
// owner, on his phone, to notice first.

enum IntegrityChecks {
    /// Products the app can see in a page's parsed config.
    static func configProductCount(_ page: Page) -> Int {
        page.config?.products?.count ?? 0
    }

    /// Signed in, pages exist, and EVERY page computes to 0 products.
    static func isProductsZeroState(_ pages: [Page]) -> Bool {
        !pages.isEmpty && pages.allSatisfy { configProductCount($0) == 0 }
    }

    /// Server says a page has products; the parsed config shows none.
    static func hasServerCountMismatch(_ pages: [Page]) -> Bool {
        pages.contains { ($0.product_count ?? 0) > 0 && configProductCount($0) == 0 }
    }

    /// A call that demonstrably happened (summary and/or duration) but
    /// has neither a transcript nor any communications — the log the
    /// owner opened the detail screen for does not exist anywhere.
    static func isCallLogMissing(call: CallItem, communicationsCount: Int) -> Bool {
        let hasSubstance = !(call.summary ?? "").isEmpty || call.durationSeconds > 0
        return hasSubstance && (call.transcript ?? []).isEmpty && communicationsCount == 0
    }
}

// MARK: - Payload builders (pure, unit-tested)
//
// Field names, caps and semantics mirror the worker's whitelists for
// POST /api/v1/mobile/report and POST /api/v1/auth/mobile/failure
// exactly, plus the platform attribution the iOS parity change adds:
// platform:"ios" and osVersion (the iOS counterpart of androidVersion).
// NO tokens, NO emails, NO page/call/customer ids — counts, endpoint
// paths and error classes only.

enum ReportPayload {
    static func cap(_ value: String, _ max: Int) -> String {
        value.count > max ? String(value.prefix(max)) : value
    }

    static func integrity(
        kind: String,
        check: String,
        endpoint: String? = nil,
        statusCode: Int? = nil,
        pages: Int? = nil,
        pagesWithProducts: Int? = nil,
        callsTotal: Int? = nil,
        detail: String? = nil,
        appVersionName: String = AppConfig.appVersionName,
        appVersionCode: Int = AppConfig.appVersionCode,
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        deviceModel: String = AppConfig.deviceModel
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "kind": cap(kind, 40),
            "check": cap(check, 60),
            "detail": cap(detail ?? "", 300),
            "appVersionName": cap(appVersionName, 20),
            "appVersionCode": appVersionCode,
            "platform": "ios",
            "osVersion": cap(osVersion, 20),
            "deviceModel": cap(deviceModel, 60),
        ]
        if let endpoint { payload["endpoint"] = cap(endpoint, 80) }
        if let statusCode { payload["statusCode"] = statusCode }
        if let pages { payload["pages"] = pages }
        if let pagesWithProducts { payload["pagesWithProducts"] = pagesWithProducts }
        if let callsTotal { payload["callsTotal"] = callsTotal }
        return payload
    }

    static func signInFailure(
        flow: String,
        step: String,
        exceptionClass: String,
        statusCode: Int? = nil,
        message: String? = nil,
        appVersionName: String = AppConfig.appVersionName,
        appVersionCode: Int = AppConfig.appVersionCode,
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        deviceModel: String = AppConfig.deviceModel
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "flow": cap(flow, 40),
            "step": cap(step, 60),
            "exceptionClass": cap(exceptionClass, 120),
            "message": cap(message ?? "", 300),
            "appVersionName": cap(appVersionName, 20),
            "appVersionCode": appVersionCode,
            "platform": "ios",
            "osVersion": cap(osVersion, 20),
            "deviceModel": cap(deviceModel, 60),
        ]
        if let statusCode { payload["statusCode"] = statusCode }
        return payload
    }
}

// MARK: - Fire-and-forget sender
//
// Isolated URLSession (no shared cookie jar, no auth) — reporting must
// work even when the session stack is the thing that failed, and a
// reporting failure must never surface, block, or crash a UI flow.
// Every entry point swallows all errors, exactly like the Android
// reporters.

private enum ReportSender {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    static func post(path: String, payload: [String: Any]) {
        guard let url = URL(string: AppConfig.apiBase + path),
              let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let task = session.dataTask(with: request) { _, _, _ in }
        task.resume()
    }
}

// MARK: - Sign-in failure reporter
//
// Mirror of Android's SignInFailureReporter: EVERY sign-in failure —
// every flow, every step — is POSTed to /api/v1/auth/mobile/failure so
// it lands in error_log (kind='mobile-signin-failure', source='ios-app')
// within seconds instead of living only in a device log nobody can see.

enum SignInFailureReporter {
    /// Test seam: replaces the network send. Never set in production.
    static var sender: ([String: Any]) -> Void = { payload in
        ReportSender.post(path: "/v1/auth/mobile/failure", payload: payload)
    }

    static func report(flow: String, step: String, exceptionClass: String,
                       statusCode: Int? = nil, message: String? = nil) {
        let payload = ReportPayload.signInFailure(
            flow: flow, step: step, exceptionClass: exceptionClass,
            statusCode: statusCode, message: message)
        sender(payload)
    }

    static func report(flow: String, step: String, error: Error) {
        report(flow: flow, step: step,
               exceptionClass: String(describing: type(of: error)),
               message: error.localizedDescription)
    }
}

// MARK: - App integrity reporter
//
// Mirror of Android's AppIntegrityReporter: when a runtime check in
// IntegrityChecks fires (pages exist but every page computes 0
// products; the server count disagrees with the parsed config; a
// summary-bearing call has no log anywhere; a key endpoint errors),
// the app POSTs a whitelisted, PII-free report to
// /api/v1/mobile/report (error_log kind='app-integrity',
// source='ios-app'). Sends are throttled per check (10 min) so a
// re-rendering screen cannot flood the endpoint; the server-side
// parity sweep + deduped tickets are the backstop.

final class AppIntegrityReporter {
    static let shared = AppIntegrityReporter()

    /// Minimum interval between two reports of the same check.
    static let minInterval: TimeInterval = 10 * 60

    /// Test seams: replace the send and the clock. Never set in production.
    var sender: ([String: Any]) -> Void = { payload in
        ReportSender.post(path: "/v1/mobile/report", payload: payload)
    }
    var clock: () -> Date = { Date() }

    private var lastSentAt: [String: Date] = [:]
    private let lock = NSLock()

    func reportProductsZero(pages: Int) {
        report(kind: "products-zero", check: "catalog-refresh",
               pages: pages, pagesWithProducts: 0,
               detail: "signed in with pages but every page reports 0 products")
    }

    func reportPagesMismatch(pages: Int, pagesWithProducts: Int) {
        report(kind: "pages-mismatch", check: "catalog-refresh",
               pages: pages, pagesWithProducts: pagesWithProducts,
               detail: "server product_count disagrees with parsed config products")
    }

    func reportCallLogEmpty() {
        report(kind: "call-log-empty", check: "call-detail",
               detail: "call has summary/duration but transcript and communications are both empty")
    }

    func reportEndpointError(endpoint: String, statusCode: Int?, detail: String?) {
        report(kind: "endpoint-error", check: "endpoint-load",
               endpoint: endpoint, statusCode: statusCode, detail: detail)
    }

    func reportUnparseableBody(endpoint: String) {
        report(kind: "unparseable-body", check: "endpoint-load",
               endpoint: endpoint,
               detail: "response body did not decode into the expected model")
    }

    func report(kind: String, check: String,
                endpoint: String? = nil, statusCode: Int? = nil,
                pages: Int? = nil, pagesWithProducts: Int? = nil,
                callsTotal: Int? = nil, detail: String? = nil) {
        let key = "\(kind)|\(check)"
        lock.lock()
        let now = clock()
        if let last = lastSentAt[key], now.timeIntervalSince(last) < Self.minInterval {
            lock.unlock()
            return
        }
        lastSentAt[key] = now
        lock.unlock()
        let payload = ReportPayload.integrity(
            kind: kind, check: check, endpoint: endpoint, statusCode: statusCode,
            pages: pages, pagesWithProducts: pagesWithProducts,
            callsTotal: callsTotal, detail: detail)
        sender(payload)
    }
}
