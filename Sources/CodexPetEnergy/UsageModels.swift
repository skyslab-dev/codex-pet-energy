import Foundation

struct UsageWindow: Equatable {
    let label: String
    let usedPercent: Int
    let resetsAt: Date?

    var remainingPercent: Int {
        min(100, max(0, 100 - usedPercent))
    }

    func resetDescription(relativeTo now: Date) -> String {
        guard let resetsAt else { return "Reset time unavailable" }
        let remaining = max(0, Int(ceil(resetsAt.timeIntervalSince(now))))
        if remaining < 86_400 {
            let hours = remaining / 3_600
            let minutes = (remaining % 3_600) / 60
            let seconds = remaining % 60
            return String(format: "Resets in %02d:%02d:%02d", hours, minutes, seconds)
        }
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        return "Resets in \(days)d \(hours)h"
    }
}

enum ConnectionState: Equatable {
    case connecting
    case connected
    case unavailable(String)

    var menuDescription: String {
        switch self {
        case .connecting: return "Connecting to Codex…"
        case .connected: return "Codex usage is live"
        case .unavailable(let reason): return reason
        }
    }
}

enum UsagePayloadParser {
    static func windows(from result: [String: Any]) -> (primary: UsageWindow?, secondary: UsageWindow?) {
        let snapshotsByID = result["rateLimitsByLimitId"] as? [String: Any]
        let codexSnapshot = snapshotsByID?["codex"] as? [String: Any]
        guard let snapshot = codexSnapshot ?? result["rateLimits"] as? [String: Any] else {
            return (nil, nil)
        }
        return windows(fromSnapshot: snapshot)
    }

    static func windows(fromSnapshot snapshot: [String: Any]) -> (primary: UsageWindow?, secondary: UsageWindow?) {
        (
            parseWindow(snapshot["primary"], label: "5-HOUR LIMIT"),
            parseWindow(snapshot["secondary"], label: "WEEKLY LIMIT")
        )
    }

    private static func parseWindow(_ value: Any?, label: String) -> UsageWindow? {
        guard let object = value as? [String: Any],
              let usedPercent = object["usedPercent"] as? NSNumber else {
            return nil
        }
        let resetSeconds = object["resetsAt"] as? NSNumber
        return UsageWindow(
            label: label,
            usedPercent: usedPercent.intValue,
            resetsAt: resetSeconds.map { Date(timeIntervalSince1970: $0.doubleValue) }
        )
    }
}
