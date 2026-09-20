import XCTest
@testable import PeekCore

/// Round-trip tests for the JSON-backed stores, using a throwaway temp file each
/// so they never touch the real ~/Library/Application Support/Peek state.
final class PersistenceTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("peek-test-\(UUID().uuidString).json")
    }

    func testSettingsRoundTrip() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let a = SettingsStore(url: url)
        a.theme = .dark
        a.display = .mainDisplay
        a.appearDelayMs = 150
        a.language = .system
        a.hiddenApps = ["Finder", "Notes"]
        a.stickyApps = true
        a.position = .center
        a.maxVisibleRows = 12
        a.numberKeyJump = false
        a.showUsageChips = false
        a.wrapCycle = false

        let b = SettingsStore(url: url)   // reload from disk
        XCTAssertEqual(b.theme, .dark)
        XCTAssertEqual(b.display, .mainDisplay)
        XCTAssertEqual(b.appearDelayMs, 150)
        XCTAssertEqual(b.hiddenApps, ["Finder", "Notes"])
        XCTAssertTrue(b.stickyApps)
        XCTAssertEqual(b.position, .center)
        XCTAssertEqual(b.maxVisibleRows, 12)
        XCTAssertFalse(b.numberKeyJump)
        XCTAssertFalse(b.showUsageChips)
        XCTAssertFalse(b.wrapCycle)
    }

    func testSettingsDefaultsForMissingKeys() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // A settings file from an older build with only one key present.
        try! Data(#"{"theme":"light"}"#.utf8).write(to: url)

        let s = SettingsStore(url: url)
        XCTAssertEqual(s.theme, .light)          // decoded
        XCTAssertEqual(s.display, .pointerDisplay) // defaulted, not crashed
        XCTAssertTrue(s.showMenuBarIcon)
        XCTAssertEqual(s.iconStyle, .peek)
    }

    func testPinStoreTogglePersists() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let a = PinStore(url: url)
        a.toggle("Xcode")
        a.toggle("Mail")
        a.toggle("Xcode")   // unpin
        XCTAssertFalse(a.isPinned("Xcode"))
        XCTAssertTrue(a.isPinned("Mail"))

        XCTAssertEqual(PinStore(url: url).pinned, ["Mail"])
    }

    func testStatsStoreRecordPersists() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let a = StatsStore(url: url)
        a.record(SwitchEvent(fromApp: nil, toApp: "Safari"))
        a.record(SwitchEvent(fromApp: "Safari", toApp: "Xcode"))

        let reloaded = StatsStore(url: url).events
        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(reloaded.last?.toApp, "Xcode")
        XCTAssertEqual(reloaded.last?.fromApp, "Safari")
    }
}
