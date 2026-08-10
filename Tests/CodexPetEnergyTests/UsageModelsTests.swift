import XCTest
@testable import CodexPetEnergy

final class UsageModelsTests: XCTestCase {
    func testRemainingPercentIsClamped() {
        XCTAssertEqual(UsageWindow(label: "A", usedPercent: 33, resetsAt: nil).remainingPercent, 67)
        XCTAssertEqual(UsageWindow(label: "A", usedPercent: -5, resetsAt: nil).remainingPercent, 100)
        XCTAssertEqual(UsageWindow(label: "A", usedPercent: 120, resetsAt: nil).remainingPercent, 0)
    }

    func testShortResetDescription() {
        let now = Date(timeIntervalSince1970: 1_000)
        let window = UsageWindow(label: "A", usedPercent: 10, resetsAt: now.addingTimeInterval(3_661))
        XCTAssertEqual(window.resetDescription(relativeTo: now), "Resets in 01:01:01")
    }

    func testLongResetDescription() {
        let now = Date(timeIntervalSince1970: 1_000)
        let window = UsageWindow(label: "A", usedPercent: 10, resetsAt: now.addingTimeInterval(2 * 86_400 + 3 * 3_600))
        XCTAssertEqual(window.resetDescription(relativeTo: now), "Resets in 2d 3h")
    }

    func testElapsedResetDoesNotBecomeNegative() {
        let now = Date(timeIntervalSince1970: 2_000)
        let window = UsageWindow(label: "A", usedPercent: 10, resetsAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(window.resetDescription(relativeTo: now), "Resets in 00:00:00")
    }

    func testParserReadsPrimaryAndSecondary() {
        let result: [String: Any] = [
            "rateLimits": [
                "primary": ["usedPercent": 33, "windowDurationMins": 300, "resetsAt": 2_000],
                "secondary": ["usedPercent": 5, "windowDurationMins": 10_080, "resetsAt": 9_000],
            ],
        ]
        let windows = UsagePayloadParser.windows(from: result)
        XCTAssertEqual(windows.primary?.remainingPercent, 67)
        XCTAssertEqual(windows.primary?.label, "5-Hour Limit")
        XCTAssertEqual(windows.secondary?.remainingPercent, 95)
        XCTAssertEqual(windows.secondary?.label, "Weekly Limit")
    }

    func testParserRecognizesWeeklyOnlyPrimaryWindow() {
        let result: [String: Any] = [
            "rateLimits": [
                "primary": ["usedPercent": 9, "windowDurationMins": 10_080, "resetsAt": 2_000],
                "secondary": NSNull(),
            ],
        ]
        let windows = UsagePayloadParser.windows(from: result)
        XCTAssertEqual(windows.primary?.label, "Weekly Limit")
        XCTAssertEqual(windows.primary?.remainingPercent, 91)
        XCTAssertEqual(windows.primary?.windowDurationMinutes, 10_080)
        XCTAssertNil(windows.secondary)
    }

    func testParserOrdersKnownWindowsByDuration() {
        let result: [String: Any] = [
            "rateLimits": [
                "primary": ["usedPercent": 10, "windowDurationMins": 10_080],
                "secondary": ["usedPercent": 20, "windowDurationMins": 300],
            ],
        ]
        let windows = UsagePayloadParser.windows(from: result)
        XCTAssertEqual(windows.primary?.label, "5-Hour Limit")
        XCTAssertEqual(windows.secondary?.label, "Weekly Limit")
    }

    func testParserPrefersCodexBucketFromMultiLimitPayload() {
        let result: [String: Any] = [
            "rateLimits": [
                "primary": ["usedPercent": 80],
            ],
            "rateLimitsByLimitId": [
                "codex": [
                    "primary": ["usedPercent": 25],
                    "secondary": ["usedPercent": 10],
                ],
                "codex_other": [
                    "primary": ["usedPercent": 1],
                ],
            ],
        ]
        let windows = UsagePayloadParser.windows(from: result)
        XCTAssertEqual(windows.primary?.remainingPercent, 75)
        XCTAssertEqual(windows.secondary?.remainingPercent, 90)
    }

    func testTokenUsageParserReadsDailyBuckets() {
        let result: [String: Any] = [
            "summary": ["lifetimeTokens": 99_000_000],
            "dailyUsageBuckets": [
                ["startDate": "2026-08-04", "tokens": 1_200_000],
                ["startDate": "2026-08-05", "tokens": 2_300_000],
            ],
        ]

        let profile = TokenUsagePayloadParser.profile(from: result)
        XCTAssertEqual(profile?.dailyUsageBuckets, [
            DailyTokenUsageBucket(startDate: "2026-08-04", tokens: 1_200_000),
            DailyTokenUsageBucket(startDate: "2026-08-05", tokens: 2_300_000),
        ])
    }

    func testWeeklyTokenActivityUsesResetCycleAndSevenDailyBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reset = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 17)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 9)))
        let window = UsageWindow(
            label: "Weekly Limit",
            usedPercent: 7,
            resetsAt: reset,
            windowDurationMinutes: 10_080
        )
        let profile = TokenUsageProfile(dailyUsageBuckets: [
            DailyTokenUsageBucket(startDate: "2026-08-03", tokens: 99_000_000),
            DailyTokenUsageBucket(startDate: "2026-08-04", tokens: 1_000_000),
            DailyTokenUsageBucket(startDate: "2026-08-05", tokens: 2_000_000),
            DailyTokenUsageBucket(startDate: "2026-08-06", tokens: 3_000_000),
            DailyTokenUsageBucket(startDate: "2026-08-07", tokens: 4_000_000),
            DailyTokenUsageBucket(startDate: "2026-08-08", tokens: 5_000_000),
            DailyTokenUsageBucket(startDate: "2026-08-09", tokens: 6_000_000),
            DailyTokenUsageBucket(startDate: "2026-08-10", tokens: 7_000_000),
            DailyTokenUsageBucket(startDate: "2026-08-11", tokens: 99_000_000),
        ])

        let activity = try XCTUnwrap(WeeklyTokenActivityBuilder.activity(
            profile: profile,
            window: window,
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(activity.dailyTokens, [1, 2, 3, 4, 5, 6, 7].map { Int64($0) * 1_000_000 })
        XCTAssertEqual(activity.totalTokens, 28_000_000)
        XCTAssertEqual(activity.currentDayIndex, 3)
        XCTAssertEqual(activity.dateRangeDescription(calendar: calendar), "Aug 4–11")
    }

    func testWeeklyTokenActivityFormatsCrossMonthRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 29)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 5)))
        let activity = WeeklyTokenActivity(
            startDate: start,
            endDate: end,
            dailyTokens: Array(repeating: 0, count: 7),
            currentDayIndex: nil
        )
        XCTAssertEqual(activity.dateRangeDescription(calendar: calendar), "Jul 29–Aug 5")
    }

    func testTokenCountFormatterUsesCompactUnits() {
        XCTAssertEqual(TokenCountFormatter.compact(12_800_000), "12.8M")
        XCTAssertEqual(TokenCountFormatter.compact(4_000_000), "4M")
        XCTAssertEqual(TokenCountFormatter.compact(950_000), "950K")
        XCTAssertEqual(TokenCountFormatter.compact(42), "42")
    }
}
