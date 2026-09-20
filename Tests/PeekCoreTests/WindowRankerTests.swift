import XCTest
@testable import PeekCore

final class WindowRankerTests: XCTestCase {
    private func minutesAgo(_ m: Double, from now: Date) -> Date {
        now.addingTimeInterval(-m * 60)
    }

    func testAffinityFavorsRecentFrequent() {
        let now = Date()
        let events = [
            SwitchEvent(timestamp: minutesAgo(1, from: now), fromApp: nil, toApp: "Xcode"),
            SwitchEvent(timestamp: minutesAgo(2, from: now), fromApp: nil, toApp: "Xcode"),
            SwitchEvent(timestamp: minutesAgo(3, from: now), fromApp: nil, toApp: "Mail"),
        ]
        let aff = WindowRanker.affinity(events: events, now: now)
        XCTAssertGreaterThan(aff["Xcode"] ?? 0, aff["Mail"] ?? 0)
    }

    func testOrderKeepsCurrentFirstThenRanksRest() {
        let now = Date()
        // Terminal is current (index 0). Xcode used more than Mail.
        let items = [
            WindowRanker.Item(app: "Terminal", originalIndex: 0),
            WindowRanker.Item(app: "Mail", originalIndex: 1),
            WindowRanker.Item(app: "Xcode", originalIndex: 2),
        ]
        let events = [
            SwitchEvent(timestamp: minutesAgo(1, from: now), fromApp: nil, toApp: "Xcode"),
            SwitchEvent(timestamp: minutesAgo(2, from: now), fromApp: nil, toApp: "Xcode"),
            SwitchEvent(timestamp: minutesAgo(3, from: now), fromApp: nil, toApp: "Mail"),
        ]
        let order = WindowRanker.order(items: items, events: events, pinned: [], now: now)
        XCTAssertEqual(order, [0, 2, 1], "current stays first; Xcode outranks Mail")
    }

    func testLearningOffKeepsZOrderButPinsStillFloat() {
        let now = Date()
        let items = [
            WindowRanker.Item(app: "Terminal", originalIndex: 0),
            WindowRanker.Item(app: "Mail", originalIndex: 1),
            WindowRanker.Item(app: "Xcode", originalIndex: 2),   // most-used, but learning off
        ]
        let events = [
            SwitchEvent(timestamp: minutesAgo(1, from: now), fromApp: nil, toApp: "Xcode"),
            SwitchEvent(timestamp: minutesAgo(2, from: now), fromApp: nil, toApp: "Xcode"),
        ]
        // Learning off, no pins → pure z-order.
        XCTAssertEqual(
            WindowRanker.order(items: items, events: events, pinned: [], now: now, useAffinity: false),
            [0, 1, 2]
        )
        // Learning off, but Xcode pinned → it floats above Mail regardless.
        XCTAssertEqual(
            WindowRanker.order(items: items, events: events, pinned: ["Xcode"], now: now, useAffinity: false),
            [0, 2, 1]
        )
    }

    func testPinnedAppJumpsToFront() {
        let now = Date()
        let items = [
            WindowRanker.Item(app: "Terminal", originalIndex: 0),
            WindowRanker.Item(app: "Mail", originalIndex: 1),      // pinned
            WindowRanker.Item(app: "Xcode", originalIndex: 2),     // higher affinity
        ]
        let events = [
            SwitchEvent(timestamp: minutesAgo(1, from: now), fromApp: nil, toApp: "Xcode"),
            SwitchEvent(timestamp: minutesAgo(2, from: now), fromApp: nil, toApp: "Xcode"),
        ]
        let order = WindowRanker.order(items: items, events: events, pinned: ["Mail"], now: now)
        XCTAssertEqual(order, [0, 1, 2], "current first, then pinned Mail ahead of Xcode")
    }
}
