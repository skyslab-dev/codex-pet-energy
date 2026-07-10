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
                "primary": ["usedPercent": 33, "resetsAt": 2_000],
                "secondary": ["usedPercent": 5, "resetsAt": 9_000],
            ],
        ]
        let windows = UsagePayloadParser.windows(from: result)
        XCTAssertEqual(windows.primary?.remainingPercent, 67)
        XCTAssertEqual(windows.secondary?.remainingPercent, 95)
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
}
