import AppKit
import ApplicationServices
import CoreGraphics
import ServiceManagement
import PeekCore

/// Wires the menu bar, hotkey, window list, switcher panel, activator, stats and settings together.
final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
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
    private var settingsWC: SettingsWindowController?
    private var intro: IntroWindowController?
    private var stickyItem: NSMenuItem?

    private var windows: [WindowInfo] = []
    private var lastApp: String?
    private var pendingShow: DispatchWorkItem?     // for the "appear delay" setting
    private var pendingSelection = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissions()

        panel.onSelect = { [weak self] _ in self?.updatePreview() }
        panel.onChoose = { [weak self] in self?.commit() }
        panel.onTogglePin = { [weak self] idx in self?.togglePin(at: idx) }
        panel.onQuit = { [weak self] idx, force in self?.quitApp(at: idx, force: force) }

        systemStats.onUpdate = { [weak self] snap in
            guard let self, self.panel.isShown else { return }
            self.panel.setSystemStats(snap)
        }
        systemStats.start()

        hotKey = HotKey(
            onCycle: { [weak self] backwards in self?.cycle(backwards: backwards) },
            onCommit: { [weak self] in self?.commit() },
            onCancel: { [weak self] in self?.cancel() }
        )
        settings.onChange = { [weak self] in self?.applyLiveSettings() }
        applyLiveSettings()                        // theme, login item, menu-bar icon, hotkey config
        if !hotKey.start() { notifyAccessibilityNeeded() }

        if !settings.hasSeenIntro {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.showIntro() }
        }
    }

    // MARK: Switching

    private func cycle(backwards: Bool) {
        if panel.isShown {
            panel.advance(backwards: backwards)
            updatePreview()
            return
        }
        if pendingShow != nil {                     // still within the appear delay — just move selection
            let n = windows.count
            if n > 0 { pendingSelection = ((pendingSelection + (backwards ? -1 : 1)) % n + n) % n }
            return
        }

        let listed = lister.listWindows().filter { !settings.isHidden($0.appName) }
        guard !listed.isEmpty else { return }

        let items = listed.enumerated().map {
            WindowRanker.Item(app: $0.element.appName, originalIndex: $0.offset)
        }
        let order = WindowRanker.order(items: items, events: stats.events,
                                       pinned: pins.pinned, useAffinity: settings.stickyApps)
        windows = order.map { listed[$0] }

        let aff = settings.stickyApps ? WindowRanker.affinity(events: stats.events) : [:]
        let maxAff = max(aff.values.max() ?? 0, 0.0001)
        let switcherItems = windows.map { w in
            SwitcherItem(title: w.title, appName: w.appName, icon: w.appIcon, pid: w.pid,
                         isPinned: pins.isPinned(w.appName),
                         strength: min(1, (aff[w.appName] ?? 0) / maxAff))
        }
        pendingSelection = backwards ? windows.count - 1 : min(1, windows.count - 1)

        let present = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingShow = nil
            self.panel.setSystemStats(self.systemStats.current)
            self.panel.show(items: switcherItems, selected: self.pendingSelection,
                            showStrength: self.settings.stickyApps,
                            showPreview: self.settings.showPreview,
                            animate: self.settings.animationsEnabled,
                            fade: self.settings.animationsEnabled && self.settings.fadeInOut,
                            onScreen: self.targetScreen(),
                            allSpaces: self.settings.spaces == .allSpaces,
                            appearance: self.switcherAppearance())
            self.startUsageSampling()
            self.updatePreview()
        }
        pendingShow = present
        let delay = settings.appearDelayMs / 1000
        if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: present) }
        else { present.perform() }
    }

    private func updatePreview() {
        guard settings.showPreview else { panel.setPreview(nil); return }
        let idx = panel.selectedIndex
        guard windows.indices.contains(idx) else { return }
        let wid = windows[idx].windowID
        panel.setPreview(nil)
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

    private func commit() {
        // Released during the appear delay → quick switch to the pending selection.
        if let p = pendingShow {
            p.cancel(); pendingShow = nil
            if settings.releaseAction == .switchToSelected, windows.indices.contains(pendingSelection) {
                switchTo(windows[pendingSelection])
            }
            return
        }
        guard panel.isShown, windows.indices.contains(panel.selectedIndex) else {
            stopUsageSampling(); panel.hide(); return
        }
        let chosen = windows[panel.selectedIndex]
        stopUsageSampling()
        panel.hide()
        guard settings.releaseAction == .switchToSelected else { return }
        switchTo(chosen)
    }

    private func switchTo(_ window: WindowInfo) {
        activator.activate(window)
        stats.record(SwitchEvent(fromApp: lastApp, toApp: window.appName))
        lastApp = window.appName
        dashboard?.refresh()
    }

    private func cancel() {
        if let p = pendingShow { p.cancel(); pendingShow = nil; return }
        stopUsageSampling()
        panel.hide()
    }

    // Live per-app CPU/RAM — only the visible pids, only while shown, on a serial queue.
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

    private func quitApp(at index: Int, force: Bool) {
        guard windows.indices.contains(index) else { return }
        let pid = windows[index].pid
        if let app = NSRunningApplication(processIdentifier: pid) {
            force ? app.forceTerminate() : app.terminate()
        }
        windows.removeAll { $0.pid == pid }
        panel.removeItems(pid: pid)
        if windows.isEmpty { stopUsageSampling(); panel.hide() } else { updatePreview() }
    }

    private func togglePin(at index: Int) {
        guard windows.indices.contains(index) else { return }
        let app = windows[index].appName
        pins.toggle(app)
        panel.setItemPinned(app: app, pinned: pins.isPinned(app))
        dashboard?.refresh()
    }

    // MARK: Applying settings

    private func applyLiveSettings() {
        applyTheme()
        applyLoginItem()
        applyMenuBarIcon()
        hotKey?.modifier = modifierFlag(settings.activation)
        hotKey?.arrowKeysEnabled = settings.arrowKeys
        stickyItem?.state = settings.stickyApps ? .on : .off
    }

    private func applyTheme() {
        NSApp.appearance = switcherAppearance()
    }

    /// The panel is a floating overlay, so it doesn't inherit NSApp.appearance —
    /// hand it the same appearance explicitly (nil = follow the system).
    private func switcherAppearance() -> NSAppearance? {
        switch settings.theme {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    private func applyLoginItem() {
        do {
            let svc = SMAppService.mainApp
            if settings.startAtLogin {
                if svc.status != .enabled { try svc.register() }
            } else if svc.status == .enabled {
                try svc.unregister()
            }
        } catch {
            NSLog("Peek: login-item update failed: \(error)")
        }
    }

    private func modifierFlag(_ s: ActivationShortcut) -> CGEventFlags {
        switch s {
        case .commandTab: return .maskCommand
        case .optionTab:  return .maskAlternate
        case .controlTab: return .maskControl
        }
    }

    private func targetScreen() -> NSScreen? {
        switch settings.display {
        case .mainDisplay:
            return NSScreen.screens.first
        case .pointerDisplay:
            let loc = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
        }
    }

    // MARK: Menu bar

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let sticky = menu.addItem(withTitle: "Sticky apps", action: #selector(toggleSticky), keyEquivalent: "")
        sticky.target = self
        sticky.state = settings.stickyApps ? .on : .off
        stickyItem = sticky
        let set = menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        set.target = self
        let dash = menu.addItem(withTitle: "Switching Insights…", action: #selector(showDashboard), keyEquivalent: "d")
        dash.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Peek", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        return menu
    }

    private func applyMenuBarIcon() {
        guard settings.showMenuBarIcon else {
            if let item = statusItem { NSStatusBar.system.removeStatusItem(item); statusItem = nil }
            return
        }
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem?.menu = buildMenu()
        }
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: settings.iconStyle.symbol, accessibilityDescription: "Peek")
            image?.isTemplate = settings.iconTint == .monochrome
            button.image = image
            button.contentTintColor = settings.iconTint == .accent ? .controlAccentColor : nil
        }
    }

    @objc private func toggleSticky() {
        settings.stickyApps.toggle()                 // persists + onChange updates the checkmark
    }

    @objc private func showSettings() {
        if settingsWC == nil { settingsWC = SettingsWindowController(settings: settings) }
        NSApp.activate(ignoringOtherApps: true)
        settingsWC?.window?.makeKeyAndOrderFront(nil)
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

    private func showIntro() {
        let wc = IntroWindowController(
            onEnable: { [weak self] in
                self?.settings.stickyApps = true
                self?.settings.hasSeenIntro = true
            },
            onNotNow: { [weak self] in self?.settings.hasSeenIntro = true }
        )
        intro = wc
        NSApp.activate(ignoringOtherApps: true)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Permissions

    private func requestPermissions() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
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
