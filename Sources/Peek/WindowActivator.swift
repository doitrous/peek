import AppKit
import ApplicationServices

// Private but stable AX SPI (used by AltTab, Rectangle, etc.) that maps an
// AXUIElement window to its CGWindowID — the only reliable way to pick the exact
// window when an app has several with the same title.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Brings the chosen window's app forward and raises the matching window.
final class WindowActivator {
    func activate(_ window: WindowInfo) {
        let app = NSRunningApplication(processIdentifier: window.pid)
        app?.activate(options: [.activateIgnoringOtherApps])
        // No window to raise — reopen the app so it surfaces (or creates) one.
        if window.isWindowless {
            if let url = app?.bundleURL { NSWorkspace.shared.open(url) }
            return
        }
        raiseWindow(pid: window.pid, windowID: window.windowID, title: window.title)
    }

    // Match the exact AX window by CGWindowID (handles duplicate titles). Fall back
    // to title, then the app's first window, then just the app activation above.
    private func raiseWindow(pid: pid_t, windowID: CGWindowID, title: String) {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else { return }

        let byID = axWindows.first { axWindow in
            var wid: CGWindowID = 0
            return _AXUIElementGetWindow(axWindow, &wid) == .success && wid == windowID
        }
        let byTitle = axWindows.first { axWindow in
            var titleRef: CFTypeRef?
            return AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success
                && (titleRef as? String) == title
        }

        guard let target = byID ?? byTitle ?? axWindows.first else { return }
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
}
