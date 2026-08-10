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

struct DailyTokenUsageBucket: Equatable {
    let startDate: String
    let tokens: Int64
}

struct TokenUsageProfile: Equatable {
    let dailyUsageBuckets: [DailyTokenUsageBucket]
}

struct WeeklyTokenActivity: Equatable {
    let startDate: Date
    let endDate: Date
    let dailyTokens: [Int64]
    let currentDayIndex: Int?

    var totalTokens: Int64 {
        dailyTokens.reduce(0, +)
    }

    var totalDescription: String {
        TokenCountFormatter.compact(totalTokens)
    }

    func dateRangeDescription(calendar: Calendar = .current) -> String {
        let start = calendar.dateComponents([.month, .day], from: startDate)
        let end = calendar.dateComponents([.month, .day], from: endDate)
        guard let startMonth = start.month,
              let startDay = start.day,
              let endMonth = end.month,
              let endDay = end.day else {
            return "—"
        }

        let startName = Self.shortMonthName(startMonth)
        if startMonth == endMonth {
            return "\(startName) \(startDay)–\(endDay)"
        }
        return "\(startName) \(startDay)–\(Self.shortMonthName(endMonth)) \(endDay)"
    }

    private static func shortMonthName(_ month: Int) -> String {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard names.indices.contains(month - 1) else { return "" }
        return names[month - 1]
    }
}

enum TokenUsagePayloadParser {
    static func profile(from result: [String: Any]) -> TokenUsageProfile? {
        guard let values = result["dailyUsageBuckets"] as? [[String: Any]] else {
            return nil
        }
        let buckets = values.compactMap { value -> DailyTokenUsageBucket? in
            guard let startDate = value["startDate"] as? String,
                  let tokens = value["tokens"] as? NSNumber else {
                return nil
            }
            return DailyTokenUsageBucket(startDate: startDate, tokens: max(0, tokens.int64Value))
        }
        return TokenUsageProfile(dailyUsageBuckets: buckets)
    }
}

enum WeeklyTokenActivityBuilder {
    static func activity(
        profile: TokenUsageProfile,
        window: UsageWindow,
        now: Date,
        calendar: Calendar = .current
    ) -> WeeklyTokenActivity? {
        guard let resetsAt = window.resetsAt,
              let durationMinutes = window.windowDurationMinutes,
              durationMinutes >= 1_440,
              durationMinutes.isMultiple(of: 1_440) else {
            return nil
        }

        let dayCount = durationMinutes / 1_440
        guard dayCount == 7 else { return nil }

        let endDate = calendar.startOfDay(for: resetsAt)
        guard let startDate = calendar.date(byAdding: .day, value: -dayCount, to: endDate) else {
            return nil
        }

        let tokensByDate = Dictionary(
            profile.dailyUsageBuckets.map { ($0.startDate, $0.tokens) },
            uniquingKeysWith: +
        )
        let dailyTokens = (0..<dayCount).map { offset -> Int64 in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else { return 0 }
            return tokensByDate[dateKey(for: date, calendar: calendar), default: 0]
        }

        let today = calendar.startOfDay(for: now)
        let currentOffset = calendar.dateComponents([.day], from: startDate, to: today).day
        let currentDayIndex = currentOffset.flatMap { dailyTokens.indices.contains($0) ? $0 : nil }

        return WeeklyTokenActivity(
            startDate: startDate,
            endDate: endDate,
            dailyTokens: dailyTokens,
            currentDayIndex: currentDayIndex
        )
    }

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return ""
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

enum TokenCountFormatter {
    static func compact(_ tokens: Int64) -> String {
        switch tokens {
        case 1_000_000_000...:
            return format(Double(tokens) / 1_000_000_000, suffix: "B")
        case 1_000_000...:
            return format(Double(tokens) / 1_000_000, suffix: "M")
        case 1_000...:
            return format(Double(tokens) / 1_000, suffix: "K")
        default:
            return "\(tokens)"
        }
    }

    private static func format(_ value: Double, suffix: String) -> String {
        let formatted = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
        return formatted.replacingOccurrences(of: ".0", with: "") + suffix
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
