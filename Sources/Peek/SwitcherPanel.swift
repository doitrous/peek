import AppKit
import SwiftUI

struct SwitcherItem: Identifiable {
    let id = UUID()
    let title: String
    let appName: String
    let icon: NSImage?
    let pid: pid_t
    var isPinned: Bool
    var strength: Double = 0                  // 0...1 learned affinity (shown when learning is on)
}

final class SwitcherModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var selected: Int = 0
    @Published var preview: NSImage?          // only the selected window's thumbnail — RAM-lite
    @Published var showStrength = false       // affinity meters (learning on)
    @Published var showPreview = true         // big window preview at the top
    @Published var animate = true             // entrance animation
    @Published var system: SystemSnapshot?    // live CPU / RAM / battery footer
    @Published var usage: [pid_t: AppUsage] = [:]   // live per-app CPU / RAM
    var onSelect: ((Int) -> Void)?            // hover moved the highlight
    var onChoose: (() -> Void)?               // a row was clicked
    var onTogglePin: ((Int) -> Void)?         // pin button on a row
    var onQuit: ((Int, Bool) -> Void)?        // quit button on a row (force = ⌥)
}

/// Borderless, non-activating column pinned to the left edge of the main screen.
final class SwitcherPanel {
    private let panel: NSPanel
    private let model = SwitcherModel()

    private(set) var isShown = false
    var selectedIndex: Int { model.selected }

    /// Called when the mouse hover changes the highlighted row (so the preview can refresh).
    var onSelect: ((Int) -> Void)? {
        get { model.onSelect } set { model.onSelect = newValue }
    }
    /// Called when a row is clicked (commit to that window).
    var onChoose: (() -> Void)? {
        get { model.onChoose } set { model.onChoose = newValue }
    }
    /// Called when a row's pin button is clicked.
    var onTogglePin: ((Int) -> Void)? {
        get { model.onTogglePin } set { model.onTogglePin = newValue }
    }
    /// Called when a row's quit button is clicked (force == ⌥ held).
    var onQuit: ((Int, Bool) -> Void)? {
        get { model.onQuit } set { model.onQuit = newValue }
    }

    private let width: CGFloat = 380
    private let rowHeight: CGFloat = 74                 // taller rows: title + app + CPU/RAM chips
    private let previewHeight: CGFloat = 220
    private let nonPreviewChrome: CGFloat = 28 + 36 + 40   // hints + system bar + padding
    private var fadeOnHide = false

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: SwitcherRoot(model: model))
    }

    func show(items: [SwitcherItem], selected: Int, showStrength: Bool,
              showPreview: Bool, animate: Bool, fade: Bool,
              onScreen: NSScreen?, allSpaces: Bool, appearance: NSAppearance?) {
        model.items = items
        model.selected = max(0, min(selected, items.count - 1))
        model.preview = nil
        model.usage = [:]
        model.showStrength = showStrength
        model.showPreview = showPreview
        model.animate = animate
        isShown = true
        fadeOnHide = fade
        panel.appearance = appearance          // nil = follow system; drives light/dark colors

        panel.collectionBehavior = allSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]

        let screen = (onScreen ?? NSScreen.main ?? NSScreen.screens.first)?.frame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let base = nonPreviewChrome + (showPreview ? previewHeight + 12 : 0)
        let wanted = base + CGFloat(items.count) * rowHeight
        let height = min(wanted, screen.height - 80)
        panel.setContentSize(NSSize(width: width, height: height))
        panel.setFrameOrigin(NSPoint(x: screen.minX + 20, y: screen.midY - height / 2))

        panel.alphaValue = fade ? 0 : 1
        panel.orderFrontRegardless()
        if fade {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                panel.animator().alphaValue = 1
            }
        }
    }

    func advance(backwards: Bool) {
        let n = model.items.count
        guard n > 0 else { return }
        model.selected = ((model.selected + (backwards ? -1 : 1)) % n + n) % n
    }

    func setPreview(_ image: NSImage?) { model.preview = image }

    func setSystemStats(_ snap: SystemSnapshot?) { model.system = snap }

    func setUsage(_ usage: [pid_t: AppUsage]) { model.usage = usage }

    /// Flip the pin badge on every row belonging to `app` (keeps row identity/animation).
    func setItemPinned(app: String, pinned: Bool) {
        for i in model.items.indices where model.items[i].appName == app {
            model.items[i].isPinned = pinned
        }
    }

    /// Remove every row for a quit app and keep the selection in range.
    func removeItems(pid: pid_t) {
        model.items.removeAll { $0.pid == pid }
        if model.selected >= model.items.count {
            model.selected = max(0, model.items.count - 1)
        }
    }

    var itemCount: Int { model.items.count }

    func hide() {
        isShown = false
        if fadeOnHide {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.1
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak panel] in panel?.orderOut(nil) })
        } else {
            panel.orderOut(nil)
        }
    }
}

private struct SwitcherRoot: View {
    @ObservedObject var model: SwitcherModel
    var body: some View {
        SwitcherColumn(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SwitcherColumn: View {
    @ObservedObject var model: SwitcherModel
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            if model.showPreview { preview }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { idx, item in
                        row(item, index: idx, selected: idx == model.selected)
                    }
                }
            }
            hints
            statsFooter
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
        .offset(x: appeared ? 0 : -32)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if model.animate {
                appeared = false
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { appeared = true }
            } else {
                appeared = true
            }
        }
        // No animation on selection — hover/keyboard highlight must snap instantly.
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(.primary.opacity(0.06))
            if let img = model.preview {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(8)
            } else if let icon = current?.icon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: 72, height: 72)
            }
            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                Text(current?.title ?? "").font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(current?.appName ?? "").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .foregroundStyle(.primary)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ item: SwitcherItem, index: Int, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable().frame(width: 30, height: 30)
                } else {
                    RoundedRectangle(cornerRadius: 7).fill(.secondary.opacity(0.25)).frame(width: 30, height: 30)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 15)).lineLimit(1)
                Text(item.appName).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                if let u = model.usage[item.pid] {
                    HStack(spacing: 8) {
                        usageChip("cpu", "CPU", "\(Int(u.cpuPercent.rounded()))%")
                        usageChip("memorychip", "RAM", memText(u.memMB))
                    }
                    .help(String(format: L("%@: live CPU and memory usage"), item.appName))
                }
            }
            Spacer(minLength: 0)
            if model.showStrength && item.strength > 0.02 {
                AffinityMeter(level: item.strength)
                    .help(L("Peek favors this app based on how often you switch to it"))
            }
            Button {
                model.onQuit?(index, NSEvent.modifierFlags.contains(.option))
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.red.opacity(0.75))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(format: L("Quit %@ — hold ⌥ to force quit"), item.appName))
            Button {
                model.onTogglePin?(index)
            } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(item.isPinned ? Color.peekAccent : .secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.isPinned ? String(format: L("Unpin %@"), item.appName)
                                : String(format: L("Pin %@"), item.appName))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Color.peekAccent.opacity(0.34) : .clear)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.peekAccent)
                .frame(width: 3, height: selected ? 32 : 0)
                .padding(.leading, 3)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering, model.selected != index {
                model.selected = index
                model.onSelect?(index)
            }
        }
        .onTapGesture {
            model.selected = index
            model.onChoose?()
        }
    }

    private var hints: some View {
        HStack(spacing: 14) {
            hint("⌘Tab", "cycle"); hint("hover / click", "pick"); hint("esc", "cancel")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.top, 6)
        .frame(maxWidth: .infinity)
        .overlay(Divider().overlay(.primary.opacity(0.12)), alignment: .top)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).foregroundStyle(.primary)
            Text(label)
        }
    }

    // Whole-machine stats on their own padded bar (vs. the per-app chips on each tile).
    @ViewBuilder private var statsFooter: some View {
        if let s = model.system {
            HStack(spacing: 12) {
                stat("cpu", "CPU", String(format: "%.0f%%", s.cpuPercent))
                stat("memorychip", "RAM", String(format: "%.1f/%.0f GB", s.memUsedGB, s.memTotalGB))
                if let b = s.batteryPercent {
                    stat(batterySymbol(b), "", "\(b)%")   // battery icon is self-evident
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func stat(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 11))
            if !label.isEmpty {
                Text(label).font(.system(size: 9, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(.secondary)
            }
            Text(value).monospacedDigit()
        }
    }

    // Labelled, padded per-app usage chip (e.g. "🖥 CPU 12%").
    private func usageChip(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9))
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(.primary.opacity(0.85))
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(.primary.opacity(0.08), in: Capsule())
    }

    private func batterySymbol(_ p: Int) -> String {
        switch p {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default:    return "battery.100"
        }
    }

    private var current: SwitcherItem? {
        model.items.indices.contains(model.selected) ? model.items[model.selected] : nil
    }
}

private func memText(_ mb: Double) -> String {
    mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : "\(Int(mb.rounded())) MB"
}

/// Signal-strength style bars showing how strongly Peek has learned to favor an app.
private struct AffinityMeter: View {
    let level: Double            // 0...1
    private let heights: [CGFloat] = [6, 9, 12, 15]

    var body: some View {
        let filled = max(1, Int((level * 4).rounded(.up)))
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i < filled ? Color.peekAccent : Color.secondary.opacity(0.25))
                    .frame(width: 3, height: heights[i])
            }
        }
        .frame(height: 15)
        .accessibilityLabel(String(format: L("Affinity %d percent"), Int((level * 100).rounded())))
    }
}
