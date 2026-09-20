import XCTest
@testable import PeekCore

final class StatsAggregatorTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testAggregations() {
        let cal = Calendar(identifier: .gregorian)
        let events = [
            SwitchEvent(timestamp: date("2026-09-18T09:00:00Z"), fromApp: "Safari", toApp: "Xcode"),
            SwitchEvent(timestamp: date("2026-09-18T09:30:00Z"), fromApp: "Xcode", toApp: "Safari"),
            SwitchEvent(timestamp: date("2026-09-18T10:00:00Z"), fromApp: "Safari", toApp: "Xcode"),
            SwitchEvent(timestamp: date("2026-09-19T14:00:00Z"), fromApp: "Xcode", toApp: "Terminal"),
        ]
        let agg = StatsAggregator(events: events, calendar: cal)

        XCTAssertEqual(agg.totalSwitches, 4)
        XCTAssertEqual(agg.switchesPerDay().count, 2, "two distinct days")

        let top = agg.topApps()
        XCTAssertEqual(top.first?.app, "Xcode")
        XCTAssertEqual(top.first?.count, 2)

        let trans = agg.topTransitions()
        XCTAssertEqual(trans.first?.from, "Safari")
        XCTAssertEqual(trans.first?.to, "Xcode")
        XCTAssertEqual(trans.first?.count, 2)

        XCTAssertEqual(agg.hourlyHistogram().reduce(0, +), 4, "every event lands in exactly one hour bucket")
    }

    func testEmpty() {
        let agg = StatsAggregator(events: [])
        XCTAssertEqual(agg.totalSwitches, 0)
        XCTAssertTrue(agg.switchesPerDay().isEmpty)
        XCTAssertTrue(agg.topApps().isEmpty)
        XCTAssertEqual(agg.hourlyHistogram().count, 24)
    }
}
