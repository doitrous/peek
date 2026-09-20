import AppKit
import SwiftUI

struct SwitcherItem: Identifiable {
    let id = UUID()
    let title: String
    let appName: String
    let icon: NSImage?
    var isPinned: Bool
    var strength: Double = 0                  // 0...1 learned affinity (shown when learning is on)
}

final class SwitcherModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var selected: Int = 0
    @Published var preview: NSImage?          // only the selected window's thumbnail — RAM-lite
    @Published var showStrength = false       // affinity meters (learning on)
    @Published var system: SystemSnapshot?    // live CPU / RAM / battery footer
    var onSelect: ((Int) -> Void)?            // hover moved the highlight
    var onChoose: (() -> Void)?               // a row was clicked
    var onTogglePin: ((Int) -> Void)?         // pin button on a row
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

    private let width: CGFloat = 380
    private let rowHeight: CGFloat = 56
    private let chrome: CGFloat = 220 + 28 + 26 + 40   // preview + hints + stats + padding

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

    func show(items: [SwitcherItem], selected: Int, showStrength: Bool) {
        model.items = items
        model.selected = max(0, min(selected, items.count - 1))
        model.preview = nil
        model.showStrength = showStrength
        isShown = true

        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let wanted = chrome + CGFloat(items.count) * rowHeight
        let height = min(wanted, screen.height - 80)
        panel.setContentSize(NSSize(width: width, height: height))
        panel.setFrameOrigin(NSPoint(x: screen.minX + 20, y: screen.midY - height / 2))
        panel.orderFrontRegardless()
    }

    func advance(backwards: Bool) {
        let n = model.items.count
        guard n > 0 else { return }
        model.selected = ((model.selected + (backwards ? -1 : 1)) % n + n) % n
    }

    func setPreview(_ image: NSImage?) { model.preview = image }

    func setSystemStats(_ snap: SystemSnapshot?) { model.system = snap }

    /// Flip the pin badge on every row belonging to `app` (keeps row identity/animation).
    func setItemPinned(app: String, pinned: Bool) {
        for i in model.items.indices where model.items[i].appName == app {
            model.items[i].isPinned = pinned
        }
    }

    func hide() {
        isShown = false
        panel.orderOut(nil)
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
            preview
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
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .offset(x: appeared ? 0 : -32)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            appeared = false
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { appeared = true }
        }
        // No animation on selection — hover/keyboard highlight must snap instantly.
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.5))
            if let img = model.preview {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(8)
            } else if let icon = current?.icon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: 72, height: 72)
            }
            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                Text(current?.title ?? "").font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(current?.appName ?? "").font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .foregroundStyle(.white)
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
                    RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.2)).frame(width: 30, height: 30)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 15)).lineLimit(1)
                Text(item.appName).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            if model.showStrength && item.strength > 0.02 {
                AffinityMeter(level: item.strength)
                    .help("Peek favors this app based on how often you switch to it")
            }
            Button {
                model.onTogglePin?(index)
            } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(item.isPinned ? Color.accentColor : .white.opacity(0.38))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.isPinned ? "Unpin \(item.appName)" : "Pin \(item.appName)")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Color.accentColor.opacity(0.34) : .clear)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
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
        .foregroundStyle(.white.opacity(0.6))
        .padding(.top, 6)
        .frame(maxWidth: .infinity)
        .overlay(Divider().overlay(.white.opacity(0.12)), alignment: .top)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).foregroundStyle(.white.opacity(0.9))
            Text(label)
        }
    }

    @ViewBuilder private var statsFooter: some View {
        if let s = model.system {
            HStack(spacing: 14) {
                stat("cpu", String(format: "%.0f%%", s.cpuPercent))
                stat("memorychip", String(format: "%.1f / %.0f GB", s.memUsedGB, s.memTotalGB))
                if let b = s.batteryPercent {
                    stat(batterySymbol(b), "\(b)%")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity)
        }
    }

    private func stat(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11))
            Text(value).monospacedDigit()
        }
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

/// Signal-strength style bars showing how strongly Peek has learned to favor an app.
private struct AffinityMeter: View {
    let level: Double            // 0...1
    private let heights: [CGFloat] = [6, 9, 12, 15]

    var body: some View {
        let filled = max(1, Int((level * 4).rounded(.up)))
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i < filled ? Color.accentColor : Color.white.opacity(0.18))
                    .frame(width: 3, height: heights[i])
            }
        }
        .frame(height: 15)
        .accessibilityLabel("Affinity \(Int((level * 100).rounded())) percent")
    }
}
