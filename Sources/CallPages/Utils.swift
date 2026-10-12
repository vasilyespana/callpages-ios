import Foundation

/// Shared display formatting for server timestamps.
enum DateFmt {
    private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let isoParserPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return isoParser.date(from: raw) ?? isoParserPlain.date(from: raw)
    }

    /// "Oct 10, 2026 at 10:00 AM" — or the raw string when unparseable.
    static func display(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        guard let date = parse(raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// "Oct 10, 2026" — or the raw string when unparseable.
    static func displayDay(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        guard let date = parse(raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// Shared load-error handling for list/detail screens: an unauthorized
/// error expires the session; HTTP and decode failures are reported to
/// the integrity endpoint (endpoint paths and status codes only).
enum LoadErrorHandling {
    static func handle(_ error: Error, endpoint: String) {
        switch error {
        case APIError.unauthorized:
            AuthService.shared.expireSession()
        case APIError.http(let status):
            AppIntegrityReporter.shared.reportEndpointError(
                endpoint: endpoint, statusCode: status, detail: nil)
        case APIError.decoding:
            AppIntegrityReporter.shared.reportUnparseableBody(endpoint: endpoint)
        case APIError.network(let message):
            AppIntegrityReporter.shared.reportEndpointError(
                endpoint: endpoint, statusCode: nil, detail: "network: \(message)")
        default:
            AppIntegrityReporter.shared.reportEndpointError(
                endpoint: endpoint, statusCode: nil,
                detail: String(describing: type(of: error)))
        }
    }
}
