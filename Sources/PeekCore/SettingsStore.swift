import Foundation
import Combine

public enum PeekTheme: String, Codable, CaseIterable {
    case system, light, dark
    public var label: String { ["system": "System", "light": "Light", "dark": "Dark"][rawValue]! }
}

public enum ReleaseAction: String, Codable, CaseIterable {
    case switchToSelected, cancel
    public var label: String {
        self == .switchToSelected ? "Switch to the selected window" : "Cancel — don't switch"
    }
}

public enum DisplayChoice: String, Codable, CaseIterable {
    case mainDisplay, pointerDisplay
    public var label: String {
        self == .mainDisplay ? "Main display" : "Display with the pointer"
    }
}

public enum SpacesMode: String, Codable, CaseIterable {
    case allSpaces, activeSpace
    public var label: String { self == .allSpaces ? "All Spaces" : "Active Space only" }
}

public enum ActivationShortcut: String, Codable, CaseIterable {
    case commandTab, optionTab, controlTab
    public var label: String { ["commandTab": "⌘ Tab", "optionTab": "⌥ Tab", "controlTab": "⌃ Tab"][rawValue]! }
}

public enum MenuBarIconStyle: String, Codable, CaseIterable {
    case stack, cards, grid, arrows
    public var symbol: String {
        ["stack": "square.stack.3d.up.fill", "cards": "rectangle.stack.fill",
         "grid": "squares.below.rectangle", "arrows": "arrow.left.arrow.right"][rawValue]!
    }
    public var label: String { rawValue.capitalized }
}

public enum MenuBarIconTint: String, Codable, CaseIterable {
    case monochrome, accent
    public var label: String { self == .monochrome ? "Monochrome" : "Accent color" }
}

public enum AppLanguage: String, Codable, CaseIterable {
    case system, english
    public var label: String { self == .system ? "System" : "English" }
}

/// All user settings, persisted as JSON. ObservableObject so the Settings window
/// binds directly; `onChange` lets the app re-apply live (theme, login item, icon).
public final class SettingsStore: ObservableObject {
    // General
    @Published public var startAtLogin = false { didSet { persist() } }
    @Published public var showMenuBarIcon = true { didSet { persist() } }
    @Published public var iconStyle: MenuBarIconStyle = .stack { didSet { persist() } }
    @Published public var iconTint: MenuBarIconTint = .monochrome { didSet { persist() } }
    @Published public var language: AppLanguage = .system { didSet { persist() } }

    // Appearance
    @Published public var theme: PeekTheme = .system { didSet { persist() } }
    @Published public var showPreview = true { didSet { persist() } }
    @Published public var animationsEnabled = true { didSet { persist() } }
    @Published public var fadeInOut = true { didSet { persist() } }
    @Published public var appearDelayMs: Double = 0 { didSet { persist() } }

    // Behavior
    @Published public var releaseAction: ReleaseAction = .switchToSelected { didSet { persist() } }
    @Published public var arrowKeys = true { didSet { persist() } }
    @Published public var display: DisplayChoice = .pointerDisplay { didSet { persist() } }
    @Published public var spaces: SpacesMode = .activeSpace { didSet { persist() } }

    // Shortcuts
    @Published public var activation: ActivationShortcut = .commandTab { didSet { persist() } }

    // Apps
    @Published public var hiddenApps: [String] = [] { didSet { persist() } }

    // Learning (existing)
    @Published public var stickyApps = false { didSet { persist() } }
    @Published public var hasSeenIntro = false { didSet { persist() } }

    /// Fired after any change is persisted so the app can re-apply live.
    public var onChange: (() -> Void)?

    private let url: URL
    private var loaded = false

    public init(url customURL: URL? = nil) {
        self.url = customURL ?? AppSupport.url("settings.json")
        if let data = try? Data(contentsOf: url),
           let p = try? JSONDecoder().decode(Payload.self, from: data) {
            startAtLogin = p.startAtLogin
            showMenuBarIcon = p.showMenuBarIcon
            iconStyle = p.iconStyle
            iconTint = p.iconTint
            language = p.language
            theme = p.theme
            showPreview = p.showPreview
            animationsEnabled = p.animationsEnabled
            fadeInOut = p.fadeInOut
            appearDelayMs = p.appearDelayMs
            releaseAction = p.releaseAction
            arrowKeys = p.arrowKeys
            display = p.display
            spaces = p.spaces
            activation = p.activation
            hiddenApps = p.hiddenApps
            stickyApps = p.stickyApps
            hasSeenIntro = p.hasSeenIntro
        }
        loaded = true
    }

    public func isHidden(_ app: String) -> Bool { hiddenApps.contains(app) }

    public func toggleHidden(_ app: String) {
        if let i = hiddenApps.firstIndex(of: app) { hiddenApps.remove(at: i) } else { hiddenApps.append(app) }
    }

    private func persist() {
        guard loaded else { return }
        let p = Payload(
            startAtLogin: startAtLogin, showMenuBarIcon: showMenuBarIcon, iconStyle: iconStyle,
            iconTint: iconTint, language: language, theme: theme, showPreview: showPreview,
            animationsEnabled: animationsEnabled, fadeInOut: fadeInOut, appearDelayMs: appearDelayMs,
            releaseAction: releaseAction, arrowKeys: arrowKeys, display: display, spaces: spaces,
            activation: activation, hiddenApps: hiddenApps, stickyApps: stickyApps, hasSeenIntro: hasSeenIntro
        )
        if let data = try? JSONEncoder().encode(p) { try? data.write(to: url, options: .atomic) }
        onChange?()
    }

    private struct Payload: Codable {
        var startAtLogin = false
        var showMenuBarIcon = true
        var iconStyle: MenuBarIconStyle = .stack
        var iconTint: MenuBarIconTint = .monochrome
        var language: AppLanguage = .system
        var theme: PeekTheme = .system
        var showPreview = true
        var animationsEnabled = true
        var fadeInOut = true
        var appearDelayMs: Double = 0
        var releaseAction: ReleaseAction = .switchToSelected
        var arrowKeys = true
        var display: DisplayChoice = .pointerDisplay
        var spaces: SpacesMode = .activeSpace
        var activation: ActivationShortcut = .commandTab
        var hiddenApps: [String] = []
        var stickyApps = false
        var hasSeenIntro = false

        init(startAtLogin: Bool, showMenuBarIcon: Bool, iconStyle: MenuBarIconStyle, iconTint: MenuBarIconTint,
             language: AppLanguage, theme: PeekTheme, showPreview: Bool, animationsEnabled: Bool, fadeInOut: Bool,
             appearDelayMs: Double, releaseAction: ReleaseAction, arrowKeys: Bool, display: DisplayChoice,
             spaces: SpacesMode, activation: ActivationShortcut, hiddenApps: [String], stickyApps: Bool, hasSeenIntro: Bool) {
            self.startAtLogin = startAtLogin; self.showMenuBarIcon = showMenuBarIcon; self.iconStyle = iconStyle
            self.iconTint = iconTint; self.language = language; self.theme = theme; self.showPreview = showPreview
            self.animationsEnabled = animationsEnabled; self.fadeInOut = fadeInOut; self.appearDelayMs = appearDelayMs
            self.releaseAction = releaseAction; self.arrowKeys = arrowKeys; self.display = display; self.spaces = spaces
            self.activation = activation; self.hiddenApps = hiddenApps; self.stickyApps = stickyApps; self.hasSeenIntro = hasSeenIntro
        }

        // Defaulted decoding for forward-compatible settings files.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func g<T: Decodable>(_ k: CodingKeys, _ d: T) -> T { (try? c.decode(T.self, forKey: k)) ?? d }
            startAtLogin = g(.startAtLogin, false)
            showMenuBarIcon = g(.showMenuBarIcon, true)
            iconStyle = g(.iconStyle, .stack)
            iconTint = g(.iconTint, .monochrome)
            language = g(.language, .system)
            theme = g(.theme, .system)
            showPreview = g(.showPreview, true)
            animationsEnabled = g(.animationsEnabled, true)
            fadeInOut = g(.fadeInOut, true)
            appearDelayMs = g(.appearDelayMs, 0)
            releaseAction = g(.releaseAction, .switchToSelected)
            arrowKeys = g(.arrowKeys, true)
            display = g(.display, .pointerDisplay)
            spaces = g(.spaces, .activeSpace)
            activation = g(.activation, .commandTab)
            hiddenApps = g(.hiddenApps, [])
            stickyApps = g(.stickyApps, false)
            hasSeenIntro = g(.hasSeenIntro, false)
        }
    }
}
