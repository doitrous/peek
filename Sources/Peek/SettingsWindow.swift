import AppKit
import SwiftUI
import PeekCore

/// Where the "Support Peek" buttons (menu bar + Settings) send people.
let peekDonateURL = URL(string: "https://paypal.me/Omary98")!
/// The project's GitHub repo (Contribute button).
let peekRepoURL = URL(string: "https://github.com/doitrous/peek")!

final class SettingsWindowController: NSWindowController {
    init(settings: SettingsStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "Peek Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let host = NSHostingController(rootView: SettingsView(settings: settings))
        host.sizingOptions = [.preferredContentSize]
        window.contentViewController = host
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("not supported") }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, behavior, shortcuts, apps
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .behavior: return "slider.horizontal.3"
        case .shortcuts: return "command"
        case .apps: return "app.badge"
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @State private var section: SettingsSection? = .general

    var body: some View {
        // NavigationSplitView gives a native sidebar (correct material + title-bar
        // blending), so there's no manual background/title-bar band to fight.
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { s in
                Label(s.title, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(188)
            .toolbar(removing: .sidebarToggle)   // no collapse button — sidebar is always shown
        } detail: {
            ScrollView(.vertical, showsIndicators: false) { detail.padding(.vertical, 4) }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.peekAccent)                       // crimson selection highlight
        .frame(width: 640, height: 480)
    }

    @ViewBuilder private var detail: some View {
        switch section ?? .general {
        case .general: general
        case .appearance: appearance
        case .behavior: behavior
        case .shortcuts: shortcuts
        case .apps: apps
        }
    }

    // MARK: General

    private var general: some View {
        Form {
            Section {
                Toggle("Start Peek at login", isOn: $settings.startAtLogin)
            }
            Section("Menu-bar icon") {
                Toggle("Show menu-bar icon", isOn: $settings.showMenuBarIcon)
                Picker("Icon shape", selection: $settings.iconStyle) {
                    ForEach(MenuBarIconStyle.allCases, id: \.self) { s in
                        Label(s.label, systemImage: s.symbol).tag(s)
                    }
                }
                .disabled(!settings.showMenuBarIcon)
                Picker("Icon tint", selection: $settings.iconTint) {
                    ForEach(MenuBarIconTint.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .disabled(!settings.showMenuBarIcon)
            }
            Section("Language") {
                Picker("Language", selection: $settings.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text("English for now — more languages coming.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Support") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Peek is free and open source.")
                        Text("If it saves you time, you can chip in.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(peekDonateURL)
                    } label: {
                        Label("Support Peek", systemImage: "heart.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.peekAccent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Contribute to the project")
                        Text("Peek is open source — issues and PRs welcome.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(peekRepoURL)
                    } label: {
                        Label("Contribute", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.peekAccent)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .overlay(Capsule().strokeBorder(Color.peekAccent, lineWidth: 1.2))
                    }
                    .buttonStyle(.plain)
                }
                Link("github.com/doitrous/peek", destination: peekRepoURL)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Appearance

    private var appearance: some View {
        Form {
            Section {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(PeekTheme.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Show a preview of the selected window", isOn: $settings.showPreview)
            }
            Section("Animations") {
                Toggle("Enable animations", isOn: $settings.animationsEnabled)
                Toggle("Fade in and out", isOn: $settings.fadeInOut)
                    .disabled(!settings.animationsEnabled)
                HStack {
                    Text("Appear delay")
                    Slider(value: $settings.appearDelayMs, in: 0...400, step: 25)
                    Text("\(Int(settings.appearDelayMs)) ms").monospacedDigit()
                        .foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Behavior

    private var behavior: some View {
        Form {
            Section {
                Picker("On key release", selection: $settings.releaseAction) {
                    ForEach(ReleaseAction.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Navigate with arrow keys", isOn: $settings.arrowKeys)
            }
            Section("Screens") {
                Picker("Show on", selection: $settings.display) {
                    ForEach(DisplayChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Spaces", selection: $settings.spaces) {
                    ForEach(SpacesMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text("Active Space keeps the switcher on the desktop you're using.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        Form {
            Section("Activation") {
                Picker("Open the switcher with", selection: $settings.activation) {
                    ForEach(ActivationShortcut.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text("Hold the modifier and tap Tab to cycle; release to act.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("While the switcher is open") {
                shortcutRow("Tab", "Next window")
                shortcutRow("⇧ Tab", "Previous window")
                shortcutRow("↑ ↓", "Navigate (if arrow keys are on)")
                shortcutRow("Esc", "Cancel")
                shortcutRow("Click", "Switch to that window")
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ keys: String, _ desc: String) -> some View {
        HStack {
            Text(keys).font(.system(.body, design: .rounded)).bold()
                .frame(width: 70, alignment: .leading)
            Text(desc).foregroundStyle(.secondary)
        }
    }

    // MARK: Apps

    private var apps: some View {
        Form {
            Section("Hidden apps") {
                Text("Apps listed here are excluded from the switcher.")
                    .font(.caption).foregroundStyle(.secondary)
                if settings.hiddenApps.isEmpty {
                    Text("No hidden apps.").foregroundStyle(.secondary)
                } else {
                    ForEach(settings.hiddenApps, id: \.self) { app in
                        HStack {
                            Text(app)
                            Spacer()
                            Button {
                                settings.toggleHidden(app)
                            } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Menu("Add app…") {
                    ForEach(runningApps(), id: \.self) { app in
                        Button(app) { if !settings.isHidden(app) { settings.toggleHidden(app) } }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func runningApps() -> [String] {
        let names = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
        return Array(Set(names)).sorted()
    }
}
