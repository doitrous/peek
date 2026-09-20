import AppKit
import ScreenCaptureKit

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
    // Uses ScreenCaptureKit (the supported replacement for the deprecated
    // CGWindowListCreateImage); needs Screen Recording permission, same as listing.
    static func capture(_ windowID: CGWindowID) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let win = content.windows.first(where: { $0.windowID == windowID }),
                  win.frame.width > 1, win.frame.height > 1 else { return nil }

            let cfg = SCStreamConfiguration()
            cfg.width = Int(win.frame.width)         // nominal (point) resolution, like before
            cfg.height = Int(win.frame.height)
            cfg.showsCursor = false
            cfg.ignoreShadowsSingleWindow = true

            let filter = SCContentFilter(desktopIndependentWindow: win)
            let cg = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: cfg)
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } catch {
            return nil
        }
    }
}
