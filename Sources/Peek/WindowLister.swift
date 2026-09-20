import AppKit

/// One switchable window. Thumbnails are captured on demand (see `capture`),
/// not here — so listing stays cheap and only the selected window's image is
/// ever held in memory.
struct WindowInfo {
    let windowID: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let appIcon: NSImage?
}

/// Enumerates on-screen windows. Needs Screen Recording permission for titles
/// and (on demand) thumbnails on modern macOS.
final class WindowLister {
    func listWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let myPID = ProcessInfo.processInfo.processIdentifier

        // Front-to-back z-order preserved so index 0 == frontmost window.
        return raw.compactMap { dict -> WindowInfo? in
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t, pid != myPID
            else { return nil }

            if let bounds = dict[kCGWindowBounds as String] as? [String: CGFloat],
               let w = bounds["Width"], let h = bounds["Height"], w < 80 || h < 80 {
                return nil   // skip tiny/utility windows
            }

            let appName = (dict[kCGWindowOwnerName as String] as? String) ?? "Unknown"
            let rawTitle = (dict[kCGWindowName as String] as? String) ?? ""
            return WindowInfo(
                windowID: windowID,
                pid: pid,
                appName: appName,
                title: rawTitle.isEmpty ? appName : rawTitle,
                appIcon: NSRunningApplication(processIdentifier: pid)?.icon
            )
        }
    }

    // RAM-lite: capture a single window's thumbnail only when it becomes the selection.
    // ponytail: CGWindowListCreateImage is deprecated for ScreenCaptureKit but works with
    // Screen Recording permission and is far less code. Swap to SCK if capture ever breaks.
    static func capture(_ windowID: CGWindowID) -> NSImage? {
        guard let cg = CGWindowListCreateImage(
            .null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .nominalResolution]
        ), cg.width > 1, cg.height > 1 else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
