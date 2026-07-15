import Foundation

struct UsageWindow: Equatable {
    let label: String
    let usedPercent: Int
    let resetsAt: Date?
    let windowDurationMinutes: Int?

    init(label: String, usedPercent: Int, resetsAt: Date?, windowDurationMinutes: Int? = nil) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowDurationMinutes = windowDurationMinutes
    }

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
        let primary = parseWindow(snapshot["primary"], fallbackLabel: "5-Hour Limit")
        let secondary = parseWindow(snapshot["secondary"], fallbackLabel: "Weekly Limit")
        guard let primary, let secondary else { return (primary, secondary) }

        if let primaryDuration = primary.windowDurationMinutes,
           let secondaryDuration = secondary.windowDurationMinutes,
           primaryDuration > secondaryDuration {
            return (secondary, primary)
        }
        return (primary, secondary)
    }

    private static func parseWindow(_ value: Any?, fallbackLabel: String) -> UsageWindow? {
        guard let object = value as? [String: Any],
              let usedPercent = object["usedPercent"] as? NSNumber else {
            return nil
        }
        let resetSeconds = object["resetsAt"] as? NSNumber
        let durationMinutes = (object["windowDurationMins"] as? NSNumber)?.intValue
        return UsageWindow(
            label: label(forDurationMinutes: durationMinutes, fallback: fallbackLabel),
            usedPercent: usedPercent.intValue,
            resetsAt: resetSeconds.map { Date(timeIntervalSince1970: $0.doubleValue) },
            windowDurationMinutes: durationMinutes
        )
    }

    private static func label(forDurationMinutes minutes: Int?, fallback: String) -> String {
        guard let minutes, minutes > 0 else { return fallback }
        switch minutes {
        case 300:
            return "5-Hour Limit"
        case 1_440:
            return "Daily Limit"
        case 10_080:
            return "Weekly Limit"
        case let value where value.isMultiple(of: 1_440):
            return "\(value / 1_440)-Day Limit"
        case let value where value.isMultiple(of: 60):
            return "\(value / 60)-Hour Limit"
        default:
            return "Usage Limit"
        }
    }
}
