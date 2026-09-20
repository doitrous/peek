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
    private let systemStats = SystemStats()
    private let sampler = ProcessSampler()
    private let sampleQueue = DispatchQueue(label: "com.peek.sampler")
    private var usageTimer: Timer?
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
        panel.onQuit = { [weak self] idx, force in self?.quitApp(at: idx, force: force) }

        systemStats.onUpdate = { [weak self] snap in
            guard let self, self.panel.isShown else { return }
            self.panel.setSystemStats(snap)   // live-refresh while the column is visible
        }
        systemStats.start()

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
            // Pins always float; the learning layer (affinity) only when sticky is on.
            let items = listed.enumerated().map {
                WindowRanker.Item(app: $0.element.appName, originalIndex: $0.offset)
            }
            let order = WindowRanker.order(items: items, events: stats.events,
                                           pinned: pins.pinned, useAffinity: settings.stickyApps)
            windows = order.map { listed[$0] }

            // Normalised affinity strength for the on-row meters (learning on only).
            let aff = settings.stickyApps ? WindowRanker.affinity(events: stats.events) : [:]
            let maxAff = max(aff.values.max() ?? 0, 0.0001)

            let switcherItems = windows.map { w in
                SwitcherItem(title: w.title, appName: w.appName, icon: w.appIcon, pid: w.pid,
                             isPinned: pins.isPinned(w.appName),
                             strength: min(1, (aff[w.appName] ?? 0) / maxAff))
            }
            // First press lands on the previous window (index 1), like ⌘-Tab.
            let start = backwards ? windows.count - 1 : min(1, windows.count - 1)
            panel.setSystemStats(systemStats.current)
            panel.show(items: switcherItems, selected: start, showStrength: settings.stickyApps)
            startUsageSampling()
        } else {
            panel.advance(backwards: backwards)
        }
        updatePreview()
    }

    // Capture only the highlighted window's thumbnail — one image in memory at a time.
    // Captured OFF the main thread so hover/cycle stays instant; the icon shows
    // immediately and the screenshot drops in a beat later (stale results discarded).
    private func updatePreview() {
        let idx = panel.selectedIndex
        guard windows.indices.contains(idx) else { return }
        let wid = windows[idx].windowID
        panel.setPreview(nil)   // instant: fall back to the app icon while capturing
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let image = WindowLister.capture(wid)
            DispatchQueue.main.async {
                guard let self, self.panel.isShown,
                      self.windows.indices.contains(self.panel.selectedIndex),
                      self.windows[self.panel.selectedIndex].windowID == wid else { return }
                self.panel.setPreview(image)
            }
        }
    }

    // Live per-app CPU/RAM — only the visible pids, only while shown, on a serial
    // background queue. Stops the moment the switcher hides.
    private func startUsageSampling() {
        let pids = Set(windows.map(\.pid))
        usageTimer?.invalidate()
        sampleUsage(pids)
        usageTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            self?.sampleUsage(pids)
        }
    }

    private func sampleUsage(_ pids: Set<pid_t>) {
        sampleQueue.async { [weak self] in
            guard let self else { return }
            let usage = self.sampler.sample(pids: pids)
            DispatchQueue.main.async {
                guard self.panel.isShown else { return }
                self.panel.setUsage(usage)
            }
        }
    }

    private func stopUsageSampling() {
        usageTimer?.invalidate()
        usageTimer = nil
    }

    private func commit() {
        guard panel.isShown, windows.indices.contains(panel.selectedIndex) else {
            stopUsageSampling(); panel.hide(); return
        }
        let chosen = windows[panel.selectedIndex]
        stopUsageSampling()
        panel.hide()
        activator.activate(chosen)
        stats.record(SwitchEvent(fromApp: lastApp, toApp: chosen.appName))
        lastApp = chosen.appName
        dashboard?.refresh()
    }

    private func cancel() { stopUsageSampling(); panel.hide() }

    // Quit (or force-quit) the app for a row, then drop its windows from the list.
    private func quitApp(at index: Int, force: Bool) {
        guard windows.indices.contains(index) else { return }
        let pid = windows[index].pid
        if let app = NSRunningApplication(processIdentifier: pid) {
            force ? app.forceTerminate() : app.terminate()
        }
        windows.removeAll { $0.pid == pid }
        panel.removeItems(pid: pid)
        if windows.isEmpty {
            panel.hide()
        } else {
            updatePreview()
        }
    }

    // Pin/unpin from a switcher row without switching. Pins float immediately next ⌘-Tab.
    private func togglePin(at index: Int) {
        guard windows.indices.contains(index) else { return }
        let app = windows[index].appName
        pins.toggle(app)
        panel.setItemPinned(app: app, pinned: pins.isPinned(app))
        dashboard?.refresh()
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
