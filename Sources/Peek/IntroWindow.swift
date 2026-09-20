import AppKit
import SwiftUI

/// First-run window: explains sticky apps with a LIVE animated demo and lets the
/// user opt in. Sticky apps stays OFF unless they click "Enable".
final class IntroWindowController: NSWindowController {
    init(onEnable: @escaping () -> Void, onNotNow: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Welcome to Peek"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let root = IntroView(
            onEnable: { [weak self] in onEnable(); self?.close() },
            onNotNow: { [weak self] in onNotNow(); self?.close() }
        )
        window.contentView = NSHostingView(rootView: root)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }
}

private struct DemoApp: Identifiable, Equatable {
    let id: Int
    let name: String
    let symbol: String
    let color: Color
    var uses: Double
    var pinned: Bool
}

private struct IntroView: View {
    let onEnable: () -> Void
    let onNotNow: () -> Void

    @State private var apps: [DemoApp] = [
        DemoApp(id: 0, name: "Safari",   symbol: "safari",              color: .blue,   uses: 3, pinned: false),
        DemoApp(id: 1, name: "Xcode",    symbol: "hammer.fill",         color: .indigo, uses: 2, pinned: false),
        DemoApp(id: 2, name: "Messages", symbol: "message.fill",        color: .green,  uses: 5, pinned: true),
        DemoApp(id: 3, name: "Figma",    symbol: "pencil.and.outline",  color: .orange, uses: 1, pinned: false),
        DemoApp(id: 4, name: "Terminal", symbol: "terminal.fill",       color: .gray,   uses: 2, pinned: false),
    ]
    @State private var justUsed: Int? = nil
    @State private var timer: Timer?

    private var ordered: [DemoApp] {
        apps.sorted {
            $0.pinned != $1.pinned ? ($0.pinned && !$1.pinned)
            : ($0.uses != $1.uses ? $0.uses > $1.uses : $0.id < $1.id)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            demo
                .frame(width: 250)
                .padding(20)
                .background(Color(nsColor: .underPageBackgroundColor))

            VStack(alignment: .leading, spacing: 14) {
                Text("Sticky apps").font(.title.bold())
                Text("A learning layer for your switcher: the more you switch to an app, the higher Peek floats it — automatically. Your busiest apps drift to the top so they're always the first keystroke away.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Label("Watch the list reorder as apps get used — the bars show how favored each one is.", systemImage: "sparkles")
                    .font(.callout).foregroundStyle(.secondary)
                Label("Pinning is always on. Sticky apps just adds the automatic favoring.", systemImage: "pin")
                    .font(.callout).foregroundStyle(.secondary)
                Label("Off by default — you stay in classic ⌘-Tab order until you turn it on.", systemImage: "power")
                    .font(.callout).foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 10) {
                    Button("Not now", action: onNotNow)
                        .controlSize(.large)
                    Button("Enable sticky apps", action: onEnable)
                        .controlSize(.large).keyboardShortcut(.defaultAction)
                }
                Text("You can toggle this anytime from the menu-bar icon.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: start)
        .onDisappear { timer?.invalidate() }
    }

    private var demo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PEEK").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).tracking(2)
            VStack(spacing: 6) {
                ForEach(ordered) { app in
                    HStack(spacing: 10) {
                        Image(systemName: app.symbol)
                            .frame(width: 22, height: 22)
                            .background(app.color.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.white)
                        Text(app.name).font(.system(size: 13))
                        Spacer(minLength: 0)
                        if app.pinned {
                            Image(systemName: "pin.fill").rotationEffect(.degrees(45))
                                .font(.system(size: 10)).foregroundStyle(.tint)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(app.id == justUsed ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.06))
                    )
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: true) { _ in
            // Weight by current uses so popular apps climb — exactly how affinity behaves.
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
