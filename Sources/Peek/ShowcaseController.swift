import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PeekCore

/// Screenshot mode: `PEEK_SHOWCASE=1` opens the real Settings + Dashboard windows
/// and the switcher panel with representative mock data, then prints each window's
/// id so `make-screenshots.sh` can capture them. Never runs in normal use.
final class ShowcaseController: NSObject, NSApplicationDelegate {
    private let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("peek-showcase-\(UUID().uuidString)")
    private var settingsWC: SettingsWindowController?
    private var dashboardWC: DashboardWindowController?
    private let panel = SwitcherPanel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSApp.activate(ignoringOtherApps: true)

        let settings = SettingsStore(url: file("settings.json"))
        let pins = PinStore(url: file("pins.json"))
        pins.toggle("Slack"); pins.toggle("Notes")
        let stats = StatsStore(url: file("stats.json"))
        seed(stats)

        // Dashboard (seeded history)
        let dash = DashboardWindowController(stats: stats, pins: pins, settings: settings)
        dash.refresh()
        dash.window?.setFrameOrigin(NSPoint(x: 60, y: 80))
        dash.window?.orderFront(nil)
        dashboardWC = dash

        // Settings
        let set = SettingsWindowController(settings: settings)
        set.window?.setFrameOrigin(NSPoint(x: 1000, y: 520))
        set.window?.orderFront(nil)
        settingsWC = set

        // Switcher panel with mock rows + live stats
        let items = mockItems()
        panel.show(items: items, selected: 1, showStrength: true, showPreview: true,
                   showUsage: true, showFooter: true, wrap: true, maxRows: 9,
                   position: .leftEdge, animate: false, fade: false,
                   onScreen: NSScreen.main, allSpaces: true, appearance: nil)
        panel.setSystemStats(mockSystem())
        panel.setUsage(mockUsage(for: items))

        // Give AppKit a beat to lay windows out, then print ids for the capture script.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.printWindowIDs() }
    }

    private func file(_ name: String) -> URL { dir.appendingPathComponent(name) }

    // MARK: Mock data

    private struct MockApp { let name: String; let bundleID: String; let title: String
                             let pid: pid_t; let strength: Double; let pinned: Bool }

    private let apps: [MockApp] = [
        .init(name: "Safari",   bundleID: "com.apple.Safari",       title: "GitHub — doitrous/peek", pid: 101, strength: 1.0,  pinned: false),
        .init(name: "Xcode",    bundleID: "com.apple.dt.Xcode",     title: "Peek — AppController.swift", pid: 102, strength: 0.82, pinned: false),
        .init(name: "Slack",    bundleID: "com.tinyspeck.slackmacgap", title: "#engineering", pid: 103, strength: 0.7,  pinned: true),
        .init(name: "Notes",    bundleID: "com.apple.Notes",        title: "Release checklist", pid: 104, strength: 0.5,  pinned: true),
        .init(name: "Terminal", bundleID: "com.apple.Terminal",     title: "peek — zsh",  pid: 105, strength: 0.38, pinned: false),
        .init(name: "Messages", bundleID: "com.apple.MobileSMS",    title: "Omar",        pid: 106, strength: 0.22, pinned: false),
    ]

    private func mockItems() -> [SwitcherItem] {
        apps.map { a in
            SwitcherItem(title: a.title, appName: a.name, icon: icon(a.bundleID),
                         pid: a.pid, isPinned: a.pinned, strength: a.strength)
        }
    }

    private func mockUsage(for items: [SwitcherItem]) -> [pid_t: AppUsage] {
        let cpu: [pid_t: Double] = [101: 6.2, 102: 41.0, 103: 2.1, 104: 0.4, 105: 1.3, 106: 0.8]
        let mem: [pid_t: Double] = [101: 812, 102: 2240, 103: 496, 104: 138, 105: 92, 106: 210]
        var out: [pid_t: AppUsage] = [:]
        for i in items { out[i.pid] = AppUsage(cpuPercent: cpu[i.pid] ?? 1, memMB: mem[i.pid] ?? 100) }
        return out
    }

    private func mockSystem() -> SystemSnapshot {
        var s = SystemSnapshot()
        s.cpuPercent = 18; s.memUsedGB = 11.2; s.memTotalGB = 16; s.batteryPercent = 76
        return s
    }

    private func icon(_ bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: UTType.applicationBundle)
    }

    // A believable switching history: weighted by each app's strength, spread over
    // the last 10 days and across working hours, so every dashboard chart is populated.
    private func seed(_ stats: StatsStore) {
        let cal = Calendar.current
        let now = Date()
        var prev: String? = nil
        var rng = SystemRandomNumberGenerator()
        let weighted = apps.flatMap { a in Array(repeating: a.name, count: Int(a.strength * 10) + 1) }
        for day in 0..<10 {
            let switches = Int.random(in: 8...22, using: &rng)
            for _ in 0..<switches {
                let hour = [9,10,10,11,13,14,15,15,16,17,20].randomElement(using: &rng)!
                let base = cal.date(byAdding: .day, value: -day, to: now)!
                let ts = cal.date(bySettingHour: hour, minute: Int.random(in: 0...59, using: &rng),
                                  second: 0, of: base)!
                let to = weighted.randomElement(using: &rng)!
                stats.record(SwitchEvent(timestamp: ts, fromApp: prev, toApp: to))
                prev = to
            }
        }
    }

    // MARK: Window ids

    private func printWindowIDs() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == myPID {
            let num = w[kCGWindowNumber as String] as? Int ?? 0
            let name = (w[kCGWindowName as String] as? String) ?? ""
            let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let width = Int(b["Width"] ?? 0), height = Int(b["Height"] ?? 0)
            guard width > 60, height > 60 else { continue }
            print("SHOT id=\(num) w=\(width) h=\(height) title=\(name)")
        }
        print("SHOT done")
    }
}
