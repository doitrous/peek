import AppKit
import ApplicationServices
import PeekCore

/// Wires the menu bar, hotkey, window list, switcher panel, activator, and stats together.
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let lister = WindowLister()
    private let activator = WindowActivator()
    private let stats = StatsStore()
    private let pins = PinStore()
    private let settings = SettingsStore()
    private let panel = SwitcherPanel()
    private var hotKey: HotKey!
    private var dashboard: DashboardWindowController?
    private var intro: IntroWindowController?
    private var stickyItem: NSMenuItem?

    private var windows: [WindowInfo] = []
    private var lastApp: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        requestPermissions()

        panel.onSelect = { [weak self] _ in self?.updatePreview() }   // hover moved highlight
        panel.onChoose = { [weak self] in self?.commit() }            // row clicked
        panel.onTogglePin = { [weak self] idx in self?.togglePin(at: idx) }

        hotKey = HotKey(
            onCycle: { [weak self] backwards in self?.cycle(backwards: backwards) },
            onCommit: { [weak self] in self?.commit() },
            onCancel: { [weak self] in self?.cancel() }
        )
        if !hotKey.start() {
            notifyAccessibilityNeeded()
        }

        if !settings.hasSeenIntro {
            // Slight delay so it doesn't stack on top of the permission prompts.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.showIntro() }
        }
    }

    // MARK: Switching

    private func cycle(backwards: Bool) {
        if !panel.isShown {
            let listed = lister.listWindows()
            guard !listed.isEmpty else { return }
            if settings.stickyApps {
                // Reorder by learned affinity + pins (current window stays first).
                let items = listed.enumerated().map {
                    WindowRanker.Item(app: $0.element.appName, originalIndex: $0.offset)
                }
                let order = WindowRanker.order(items: items, events: stats.events, pinned: pins.pinned)
                windows = order.map { listed[$0] }
            } else {
                windows = listed   // classic front-to-back order
            }
            // First press lands on the previous window (index 1), like ⌘-Tab.
            let start = backwards ? windows.count - 1 : min(1, windows.count - 1)
            panel.show(items: windows.map { Self.item(from: $0, pinned: pins.isPinned($0.appName)) },
                       selected: start, showPins: settings.stickyApps)
        } else {
            panel.advance(backwards: backwards)
        }
        updatePreview()
    }

    // Capture only the highlighted window's thumbnail — one image in memory at a time.
    private func updatePreview() {
        guard windows.indices.contains(panel.selectedIndex) else { return }
        panel.setPreview(WindowLister.capture(windows[panel.selectedIndex].windowID))
    }

    private func commit() {
        guard panel.isShown, windows.indices.contains(panel.selectedIndex) else {
            panel.hide(); return
        }
        let chosen = windows[panel.selectedIndex]
        panel.hide()
        activator.activate(chosen)
        stats.record(SwitchEvent(fromApp: lastApp, toApp: chosen.appName))
        lastApp = chosen.appName
        dashboard?.refresh()
    }

    private func cancel() { panel.hide() }

    // Pin/unpin from a switcher row without switching. Order re-applies next ⌘-Tab.
    private func togglePin(at index: Int) {
        guard windows.indices.contains(index) else { return }
        let app = windows[index].appName
        pins.toggle(app)
        panel.setItemPinned(app: app, pinned: pins.isPinned(app))
        dashboard?.refresh()
    }

    private static func item(from w: WindowInfo, pinned: Bool) -> SwitcherItem {
        SwitcherItem(title: w.title, appName: w.appName, icon: w.appIcon, isPinned: pinned)
    }

    // MARK: Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Peek"
        )
        let menu = NSMenu()
        let sticky = menu.addItem(withTitle: "Sticky apps", action: #selector(toggleSticky), keyEquivalent: "")
        sticky.target = self
        sticky.state = settings.stickyApps ? .on : .off
        stickyItem = sticky
        let dash = menu.addItem(withTitle: "Switching Insights…", action: #selector(showDashboard), keyEquivalent: "d")
        dash.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Peek", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        statusItem.menu = menu
    }

    @objc private func toggleSticky() {
        settings.stickyApps.toggle()
        stickyItem?.state = settings.stickyApps ? .on : .off
    }

    private func showIntro() {
        let wc = IntroWindowController(
            onEnable: { [weak self] in
                self?.settings.stickyApps = true
                self?.settings.hasSeenIntro = true
                self?.stickyItem?.state = .on
            },
            onNotNow: { [weak self] in self?.settings.hasSeenIntro = true }
        )
        intro = wc
        NSApp.activate(ignoringOtherApps: true)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func showDashboard() {
        if dashboard == nil {
            let dash = DashboardWindowController(stats: stats, pins: pins, settings: settings)
            dash.onTogglePin = { [weak self] app in
                self?.pins.toggle(app)
                self?.dashboard?.refresh()
            }
            dashboard = dash
        }
        dashboard?.refresh()
        NSApp.activate(ignoringOtherApps: true)
        dashboard?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Permissions

    private func requestPermissions() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)          // Accessibility (raise windows + event tap)
        if !CGPreflightScreenCaptureAccess() {           // Screen Recording (titles + thumbnails)
            CGRequestScreenCaptureAccess()
        }
    }

    private func notifyAccessibilityNeeded() {
        let alert = NSAlert()
        alert.messageText = "Peek needs Accessibility permission"
        alert.informativeText = "Enable Peek under System Settings → Privacy & Security → Accessibility, then relaunch."
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
