import AppKit
import CoreGraphics

/// Intercepts ⌘-Tab (and ⌘-⇧-Tab) via a CGEventTap, replacing the system switcher.
///
/// - ⌘ held + Tab            → cycle forward   (onCycle(false))
/// - ⌘ held + ⇧ + Tab        → cycle backward  (onCycle(true))
/// - ⌘ released while active  → commit          (onCommit)
/// - Esc while active         → cancel          (onCancel)
///
/// Requires Accessibility permission (keyboard event taps).
final class HotKey {
    private let onCycle: (Bool) -> Void
    private let onCommit: () -> Void
    private let onCancel: () -> Void
    private let onJump: (Int) -> Void         // number key 1-9 → that row (and commit)
    private let onEnd: (Bool) -> Void         // Home/End → first (false) / last (true)
    private let onPinSelected: () -> Void     // P → pin/unpin highlighted
    private let onQuitSelected: (Bool) -> Void // Q/W → quit highlighted (force = ⌥)

    private var tap: CFMachPort?
    private var active = false        // between the first trigger and modifier release

    /// The activation modifier (⌘ by default). Settable live from Settings.
    var modifier: CGEventFlags = .maskCommand
    /// Whether ↑/↓/←/→ navigate while the switcher is open.
    var arrowKeysEnabled = true
    /// Whether 1-9 jump straight to that row.
    var numberJumpEnabled = true
    /// Whether P (pin) and Q/W (quit) act on the highlighted row.
    var rowActionKeysEnabled = true

    private let tabKey: CGKeyCode = 48
    private let escKey: CGKeyCode = 53
    private let homeKey: CGKeyCode = 115, endKey: CGKeyCode = 119
    private let pKey: CGKeyCode = 35, qKey: CGKeyCode = 12, wKey: CGKeyCode = 13
    private let arrowDown: CGKeyCode = 125, arrowUp: CGKeyCode = 126
    private let arrowLeft: CGKeyCode = 123, arrowRight: CGKeyCode = 124
    // Keycodes for the top-row digits 1…9 → zero-based index.
    private let digitKeys: [CGKeyCode: Int] =
        [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]

    init(onCycle: @escaping (Bool) -> Void,
         onCommit: @escaping () -> Void,
         onCancel: @escaping () -> Void,
         onJump: @escaping (Int) -> Void,
         onEnd: @escaping (Bool) -> Void,
         onPinSelected: @escaping () -> Void,
         onQuitSelected: @escaping (Bool) -> Void) {
        self.onCycle = onCycle
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onJump = onJump
        self.onEnd = onEnd
        self.onPinSelected = onPinSelected
        self.onQuitSelected = onQuitSelected
    }

    /// Returns false if the tap couldn't be created (missing Accessibility permission).
    @discardableResult
    func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,           // earliest point — needed to beat the system switcher
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotKeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Peek: could not create event tap — grant Accessibility permission and relaunch.")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // Called on the main run loop (that's where the source is attached).
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let modifierDown = flags.contains(modifier)

        switch type {
        case .keyDown:
            let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if code == tabKey, modifierDown {
                active = true
                onCycle(flags.contains(.maskShift))
                return nil                 // swallow → system switcher never sees it
            }
            if active, arrowKeysEnabled, [arrowDown, arrowUp, arrowLeft, arrowRight].contains(code) {
                onCycle(code == arrowUp || code == arrowLeft)   // up/left = backward
                return nil
            }
            if active, code == escKey {
                active = false
                onCancel()
                return nil
            }
            if active, numberJumpEnabled, let idx = digitKeys[code] {
                active = false
                onJump(idx)                // jump to that row and commit
                return nil
            }
            if active, code == homeKey { onEnd(false); return nil }
            if active, code == endKey  { onEnd(true);  return nil }
            if active, rowActionKeysEnabled, code == pKey {
                onPinSelected()
                return nil
            }
            if active, rowActionKeysEnabled, code == qKey || code == wKey {
                onQuitSelected(flags.contains(.maskAlternate))   // ⌥ = force quit
                return nil
            }
        case .flagsChanged:
            if active, !modifierDown {      // modifier released → commit
                active = false
                onCommit()
            }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}

private func hotKeyCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<HotKey>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}
