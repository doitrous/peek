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
                Label(L(s.title), systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(188)
            .toolbar(removing: .sidebarToggle)   // no collapse button — sidebar is always shown
        } detail: {
            ScrollView(.vertical, showsIndicators: false) { detail.padding(.vertical, 4) }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.peekAccent)                       // crimson selection highlight
        .environment(\.layoutDirection, Localize.isRTL ? .rightToLeft : .leftToRight)
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
                Toggle(L("Start Peek at login"), isOn: $settings.startAtLogin)
            }
            Section(L("Menu-bar icon")) {
                Toggle(L("Show menu-bar icon"), isOn: $settings.showMenuBarIcon)
                Picker(L("Icon shape"), selection: $settings.iconStyle) {
                    ForEach(MenuBarIconStyle.allCases, id: \.self) { s in
                        Label(L(s.label), systemImage: s.symbol).tag(s)
                    }
                }
                .disabled(!settings.showMenuBarIcon)
                Picker(L("Icon tint"), selection: $settings.iconTint) {
                    ForEach(MenuBarIconTint.allCases, id: \.self) { Text(L($0.label)).tag($0) }
                }
                .disabled(!settings.showMenuBarIcon)
            }
            Section(L("Language")) {
                Picker(L("Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text(L($0.label)).tag($0) }
                }
                Text(L("The switcher and settings use this language."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Support")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Peek is free and open source."))
                        Text(L("If it saves you time, you can chip in."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(peekDonateURL)
                    } label: {
                        Label(L("Support Peek"), systemImage: "heart.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.peekAccent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Contribute to the project"))
                        Text(L("Peek is open source — issues and PRs welcome."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(peekRepoURL)
                    } label: {
                        Label(L("Contribute"), systemImage: "chevron.left.forwardslash.chevron.right")
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
                Picker(L("Theme"), selection: $settings.theme) {
                    ForEach(PeekTheme.allCases, id: \.self) { Text(L($0.label)).tag($0) }
                }
                Toggle(L("Show a preview of the selected window"), isOn: $settings.showPreview)
            }
            Section(L("Animations")) {
                Toggle(L("Enable animations"), isOn: $settings.animationsEnabled)
                Toggle(L("Fade in and out"), isOn: $settings.fadeInOut)
                    .disabled(!settings.animationsEnabled)
                HStack {
                    Text(L("Appear delay"))
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
                Picker(L("On key release"), selection: $settings.releaseAction) {
                    ForEach(ReleaseAction.allCases, id: \.self) { Text(L($0.label)).tag($0) }
                }
                Toggle(L("Navigate with arrow keys"), isOn: $settings.arrowKeys)
            }
            Section(L("Screens")) {
                Picker(L("Show on"), selection: $settings.display) {
                    ForEach(DisplayChoice.allCases, id: \.self) { Text(L($0.label)).tag($0) }
                }
                Picker(L("Spaces"), selection: $settings.spaces) {
                    ForEach(SpacesMode.allCases, id: \.self) { Text(L($0.label)).tag($0) }
                }
                Text(L("Active Space keeps the switcher on the desktop you're using."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        Form {
            Section(L("Activation")) {
                Picker(L("Open the switcher with"), selection: $settings.activation) {
                    ForEach(ActivationShortcut.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text(L("Hold the modifier and tap Tab to cycle; release to act."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("While the switcher is open")) {
                shortcutRow("Tab", L("Next window"))
                shortcutRow("⇧ Tab", L("Previous window"))
                shortcutRow("↑ ↓", L("Navigate (if arrow keys are on)"))
                shortcutRow("Esc", L("Cancel"))
                shortcutRow("Click", L("Switch to that window"))
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
            Section(L("Hidden apps")) {
                Text(L("Apps listed here are excluded from the switcher."))
                    .font(.caption).foregroundStyle(.secondary)
                if settings.hiddenApps.isEmpty {
                    Text(L("No hidden apps.")).foregroundStyle(.secondary)
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
                Menu(L("Add app…")) {
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
