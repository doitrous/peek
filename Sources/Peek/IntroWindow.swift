import AppKit
import SwiftUI

/// First-run onboarding: two steps (pinning, then the opt-in sticky-apps learning),
/// each with a real visual. Sticky apps stays OFF unless the user clicks "Enable".
final class IntroWindowController: NSWindowController, NSWindowDelegate {
    private let onEnable: () -> Void
    private let onNotNow: () -> Void
    private var decided = false

    init(onEnable: @escaping () -> Void, onNotNow: @escaping () -> Void) {
        self.onEnable = onEnable
        self.onNotNow = onNotNow
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Welcome to Peek"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let root = IntroView(
            onEnable: { [weak self] in self?.finish(enable: true) },
            onNotNow: { [weak self] in self?.finish(enable: false) }
        ).frame(width: 640, height: 500)   // fixed → hosting controller sizes the window to this
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(NSSize(width: 640, height: 500))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func finish(enable: Bool) {
        guard !decided else { return }
        decided = true
        enable ? onEnable() : onNotNow()
        close()
    }

    // Closing the window (red button) counts as "not now".
    func windowWillClose(_ notification: Notification) {
        if !decided { decided = true; onNotNow() }
    }
}

private struct IntroView: View {
    let onEnable: () -> Void
    let onNotNow: () -> Void
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if step == 0 { PinningStep() } else { StickyStep() }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer.padding(.horizontal, 20).padding(.vertical, 14)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(step == 0 ? Color.accentColor : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
                Circle().fill(step == 1 ? Color.accentColor : Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
            }
            Spacer()
            if step == 0 {
                Button("Next") { step = 1 }
                    .controlSize(.large).keyboardShortcut(.defaultAction)
            } else {
                Button("Back") { step = 0 }.controlSize(.large)
                Button("Not now", action: onNotNow).controlSize(.large)
                Button("Enable sticky apps", action: onEnable)
                    .controlSize(.large).keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Step 1: pinning

private struct PinRow: Identifiable {
    let id = Int.random(in: .min ... .max)
    let name: String; let symbol: String; let color: Color
    var pinned = false; var current = false; var nextHop = false
}

private struct PinningStep: View {
    private let rows: [PinRow] = [
        PinRow(name: "Terminal", symbol: "terminal.fill",   color: .gray,   current: true),
        PinRow(name: "Slack",    symbol: "message.fill",     color: .purple, pinned: true, nextHop: true),
        PinRow(name: "Notes",    symbol: "note.text",        color: .yellow, pinned: true),
        PinRow(name: "Safari",   symbol: "safari",           color: .blue),
        PinRow(name: "Xcode",    symbol: "hammer.fill",      color: .indigo),
    ]

    var body: some View {
        HStack(spacing: 22) {
            miniColumn.frame(width: 250)
            VStack(alignment: .leading, spacing: 14) {
                Text("Pinning").font(.title.bold())
                Text("Pin the apps you always want first. Pinned apps float to the top of the switcher — always on, whether or not you use sticky apps.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Label("From a non-pinned app, your next ⌘-Tab jumps straight to your pinned apps — before the rest of the list.",
                      systemImage: "arrow.turn.down.right")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Label("Toggle a pin anytime with the 📌 button on any row.", systemImage: "pin")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var miniColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PEEK").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).tracking(2)
            ForEach(rows) { r in
                HStack(spacing: 10) {
                    Image(systemName: r.symbol)
                        .frame(width: 22, height: 22)
                        .background(r.color.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.white)
                    Text(r.name).font(.system(size: 13))
                    if r.current {
                        Text("current").font(.system(size: 10)).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                    Spacer(minLength: 0)
                    if r.nextHop {
                        Text("next ⌘-Tab").font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    if r.pinned {
                        Image(systemName: "pin.fill").rotationEffect(.degrees(45))
                            .font(.system(size: 10)).foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(r.nextHop ? Color.accentColor.opacity(0.22)
                              : (r.current ? Color.primary.opacity(0.10) : Color.primary.opacity(0.05)))
                )
                .overlay(alignment: .leading) {
                    if r.nextHop {
                        RoundedRectangle(cornerRadius: 2).fill(Color.accentColor)
                            .frame(width: 3, height: 22).padding(.leading, 2)
                    }
                }
            }
        }
    }
}

// MARK: - Step 2: sticky apps (animated learning demo)

private struct DemoApp: Identifiable, Equatable {
    let id: Int
    let name: String; let symbol: String; let color: Color
    var uses: Double; var pinned: Bool
}

private struct StickyStep: View {
    @State private var apps: [DemoApp] = [
        DemoApp(id: 0, name: "Safari",   symbol: "safari",             color: .blue,   uses: 3, pinned: false),
        DemoApp(id: 1, name: "Xcode",    symbol: "hammer.fill",        color: .indigo, uses: 2, pinned: false),
        DemoApp(id: 2, name: "Messages", symbol: "message.fill",       color: .green,  uses: 5, pinned: true),
        DemoApp(id: 3, name: "Figma",    symbol: "pencil.and.outline", color: .orange, uses: 1, pinned: false),
        DemoApp(id: 4, name: "Terminal", symbol: "terminal.fill",      color: .gray,   uses: 2, pinned: false),
    ]
    @State private var justUsed: Int? = nil
    @State private var timer: Timer?

    private var ordered: [DemoApp] {
        apps.sorted {
            $0.pinned != $1.pinned ? ($0.pinned && !$1.pinned)
            : ($0.uses != $1.uses ? $0.uses > $1.uses : $0.id < $1.id)
        }
    }
    private var maxUses: Double { max(apps.map(\.uses).max() ?? 1, 1) }

    var body: some View {
        HStack(spacing: 22) {
            demo.frame(width: 250)
            VStack(alignment: .leading, spacing: 14) {
                Text("Sticky apps").font(.title.bold())
                Text("A learning layer: the more you switch to an app, the higher Peek floats it — automatically. Your busiest apps drift to the top so they're always the first keystroke away.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Label("Watch the list reorder as apps get used — bars show how favored each one is.", systemImage: "sparkles")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Label("Off by default — you stay in classic ⌘-Tab order until you turn it on.", systemImage: "power")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: start)
        .onDisappear { timer?.invalidate() }
    }

    private var demo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PEEK").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).tracking(2)
            ForEach(ordered) { app in
                HStack(spacing: 10) {
                    Image(systemName: app.symbol)
                        .frame(width: 22, height: 22)
                        .background(app.color.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.white)
                    Text(app.name).font(.system(size: 13))
                    Spacer(minLength: 0)
                    strengthBars(for: app.uses / maxUses)
                    if app.pinned {
                        Image(systemName: "pin.fill").rotationEffect(.degrees(45))
                            .font(.system(size: 10)).foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(app.id == justUsed ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.05))
                )
            }
        }
    }

    private func strengthBars(for level: Double) -> some View {
        let filled = max(1, Int((level * 4).rounded(.up)))
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i < filled ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 3, height: [5, 8, 11, 14][i])
            }
        }.frame(height: 14)
    }

    private func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: true) { _ in
            let weights = apps.map { $0.uses + 0.5 }
            let total = weights.reduce(0, +)
            var r = Double.random(in: 0..<total)
            var pick = 0
            for (i, w) in weights.enumerated() { if r < w { pick = i; break }; r -= w }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if let idx = apps.firstIndex(where: { $0.id == pick }) { apps[idx].uses += 1 }
                justUsed = pick
            }
        }
    }
}
