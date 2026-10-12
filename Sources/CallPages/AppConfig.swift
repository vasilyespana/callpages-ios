import Foundation

/// App-wide constants and runtime mode flags.
enum AppConfig {
    static let baseURL = URL(string: "https://callpages.me")!
    static let apiBase = "https://callpages.me/api"

    static var appVersionName: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }
    static var appVersionCode: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    /// UI-test stub mode: the API layer answers from canned fixtures and the
    /// app boots into a fixture session — no network, no real account.
    /// Enabled ONLY by the `-uitest-stub` launch argument (used by
    /// CallPagesUITests for the MVR-VP simulator screenshot flow, and by
    /// unit tests through direct transport injection). A normal launch
    /// never sets it. Stub data is fake demo data; nothing real is read
    /// or written while it is active.
    static var isStubMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-stub")
    }

    /// Stub variant whose fixture account owns zero pages, so the
    /// first-run onboarding (FTUE) flow is exercised.
    static var isStubEmptyMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-stub-empty")
    }

    /// Machine identifier for telemetry payloads (e.g. "iPhone16,1").
    /// No serial numbers or identifiers — just the hardware model string,
    /// mirroring Android's Build.MANUFACTURER + Build.MODEL field.
    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let identifier = mirror.children.reduce("") { acc, child in
            guard let value = child.value as? Int8, value != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? "iOS device" : identifier
    }
}
