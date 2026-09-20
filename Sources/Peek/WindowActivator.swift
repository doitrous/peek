import AppKit
import ApplicationServices

/// Brings the chosen window's app forward and raises the matching window.
final class WindowActivator {
    func activate(_ window: WindowInfo) {
        NSRunningApplication(processIdentifier: window.pid)?
            .activate(options: [.activateIgnoringOtherApps])
        raiseWindow(pid: window.pid, title: window.title)
    }

    // ponytail: matches the AX window by title. Precise CGWindowID matching needs the private
    // _AXUIElementGetWindow; title-match + app-activate is correct for the common case. Falls
    // back to the app's first window (or just the app activation above) when no title matches.
    private func raiseWindow(pid: pid_t, title: String) {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else { return }

        let target = axWindows.first { axWindow in
            var titleRef: CFTypeRef?
            return AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success
                && (titleRef as? String) == title
        } ?? axWindows.first

        guard let target else { return }
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
}
