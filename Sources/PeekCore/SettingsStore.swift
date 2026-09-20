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
    case peek, stack, cards, grid, arrows
    /// Picker/menu-bar SF Symbol. `.peek` renders the real app icon instead
    /// (see AppController.applyMenuBarIcon); this is just its Picker glyph.
    public var symbol: String {
        ["peek": "square.stack.3d.up.fill", "stack": "square.stack.3d.up.fill",
         "cards": "rectangle.stack.fill", "grid": "squares.below.rectangle",
         "arrows": "arrow.left.arrow.right"][rawValue]!
    }
    /// True when this style shows Peek's full-color app mark (tint doesn't apply).
    public var isAppMark: Bool { self == .peek }
    public var label: String { self == .peek ? "Peek mark" : rawValue.capitalized }
}

public enum MenuBarIconTint: String, Codable, CaseIterable {
    case monochrome, accent
    public var label: String { self == .monochrome ? "Monochrome" : "Accent color" }
}

public enum AppLanguage: String, Codable, CaseIterable {
    case system, english, spanish, chinese, arabic, french
    /// Picker label — each language shown as its own endonym (not translated).
    public var label: String {
        switch self {
        case .system:  return "System"
        case .english: return "English"
        case .spanish: return "Español"
        case .chinese: return "中文"
        case .arabic:  return "العربية"
        case .french:  return "Français"
        }
    }
    /// BCP-47 code of the matching `.lproj`, or nil to follow the system.
    public var localeCode: String? {
        switch self {
        case .system:  return nil
        case .english: return "en"
        case .spanish: return "es"
        case .chinese: return "zh-Hans"
        case .arabic:  return "ar"
        case .french:  return "fr"
        }
    }
    public var isRTL: Bool { self == .arabic }
}

public enum SwitcherPosition: String, Codable, CaseIterable {
    case leftEdge, center
    public var label: String { self == .leftEdge ? "Left edge" : "Centered" }
}

/// All user settings, persisted as JSON. ObservableObject so the Settings window
/// binds directly; `onChange` lets the app re-apply live (theme, login item, icon).
public final class SettingsStore: ObservableObject {
    // General
    @Published public var startAtLogin = false { didSet { persist() } }
    @Published public var showMenuBarIcon = true { didSet { persist() } }
    @Published public var iconStyle: MenuBarIconStyle = .peek { didSet { persist() } }
    @Published public var iconTint: MenuBarIconTint = .monochrome { didSet { persist() } }
    @Published public var language: AppLanguage = .system { didSet { persist() } }

    // Appearance
    @Published public var theme: PeekTheme = .system { didSet { persist() } }
    @Published public var showPreview = true { didSet { persist() } }
    @Published public var showUsageChips = true { didSet { persist() } }
    @Published public var showSystemFooter = true { didSet { persist() } }
    @Published public var animationsEnabled = true { didSet { persist() } }
    @Published public var fadeInOut = true { didSet { persist() } }
    @Published public var appearDelayMs: Double = 0 { didSet { persist() } }

    // Behavior
    @Published public var releaseAction: ReleaseAction = .switchToSelected { didSet { persist() } }
    @Published public var arrowKeys = true { didSet { persist() } }
    @Published public var wrapCycle = true { didSet { persist() } }
    @Published public var display: DisplayChoice = .pointerDisplay { didSet { persist() } }
    @Published public var position: SwitcherPosition = .leftEdge { didSet { persist() } }
    @Published public var spaces: SpacesMode = .activeSpace { didSet { persist() } }
    @Published public var maxVisibleRows: Int = 9 { didSet { persist() } }

    // Shortcuts
    @Published public var activation: ActivationShortcut = .commandTab { didSet { persist() } }
    @Published public var numberKeyJump = true { didSet { persist() } }
    @Published public var rowActionKeys = true { didSet { persist() } }

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
            showUsageChips = p.showUsageChips
            showSystemFooter = p.showSystemFooter
            animationsEnabled = p.animationsEnabled
            fadeInOut = p.fadeInOut
            appearDelayMs = p.appearDelayMs
            releaseAction = p.releaseAction
            arrowKeys = p.arrowKeys
            wrapCycle = p.wrapCycle
            display = p.display
            position = p.position
            spaces = p.spaces
            maxVisibleRows = p.maxVisibleRows
            activation = p.activation
            numberKeyJump = p.numberKeyJump
            rowActionKeys = p.rowActionKeys
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
        var p = Payload()
        p.startAtLogin = startAtLogin; p.showMenuBarIcon = showMenuBarIcon; p.iconStyle = iconStyle
        p.iconTint = iconTint; p.language = language; p.theme = theme; p.showPreview = showPreview
        p.showUsageChips = showUsageChips; p.showSystemFooter = showSystemFooter
        p.animationsEnabled = animationsEnabled; p.fadeInOut = fadeInOut; p.appearDelayMs = appearDelayMs
        p.releaseAction = releaseAction; p.arrowKeys = arrowKeys; p.wrapCycle = wrapCycle
        p.display = display; p.position = position; p.spaces = spaces; p.maxVisibleRows = maxVisibleRows
        p.activation = activation; p.numberKeyJump = numberKeyJump; p.rowActionKeys = rowActionKeys
        p.hiddenApps = hiddenApps; p.stickyApps = stickyApps; p.hasSeenIntro = hasSeenIntro
        if let data = try? JSONEncoder().encode(p) { try? data.write(to: url, options: .atomic) }
        onChange?()
    }

    private struct Payload: Codable {
        var startAtLogin = false
        var showMenuBarIcon = true
        var iconStyle: MenuBarIconStyle = .peek
        var iconTint: MenuBarIconTint = .monochrome
        var language: AppLanguage = .system
        var theme: PeekTheme = .system
        var showPreview = true
        var animationsEnabled = true
        var fadeInOut = true
        var showUsageChips = true
        var showSystemFooter = true
        var appearDelayMs: Double = 0
        var releaseAction: ReleaseAction = .switchToSelected
        var arrowKeys = true
        var wrapCycle = true
        var display: DisplayChoice = .pointerDisplay
        var position: SwitcherPosition = .leftEdge
        var spaces: SpacesMode = .activeSpace
        var maxVisibleRows: Int = 9
        var activation: ActivationShortcut = .commandTab
        var numberKeyJump = true
        var rowActionKeys = true
        var hiddenApps: [String] = []
        var stickyApps = false
        var hasSeenIntro = false

        init() {}   // build with defaults, then assign in persist()

        // Defaulted decoding for forward-compatible settings files.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func g<T: Decodable>(_ k: CodingKeys, _ d: T) -> T { (try? c.decode(T.self, forKey: k)) ?? d }
            startAtLogin = g(.startAtLogin, false)
            showMenuBarIcon = g(.showMenuBarIcon, true)
            iconStyle = g(.iconStyle, .peek)
            iconTint = g(.iconTint, .monochrome)
            language = g(.language, .system)
            theme = g(.theme, .system)
            showPreview = g(.showPreview, true)
            showUsageChips = g(.showUsageChips, true)
            showSystemFooter = g(.showSystemFooter, true)
            animationsEnabled = g(.animationsEnabled, true)
            fadeInOut = g(.fadeInOut, true)
            appearDelayMs = g(.appearDelayMs, 0)
            releaseAction = g(.releaseAction, .switchToSelected)
            arrowKeys = g(.arrowKeys, true)
            wrapCycle = g(.wrapCycle, true)
            display = g(.display, .pointerDisplay)
            position = g(.position, .leftEdge)
            spaces = g(.spaces, .activeSpace)
            maxVisibleRows = g(.maxVisibleRows, 9)
            activation = g(.activation, .commandTab)
            numberKeyJump = g(.numberKeyJump, true)
            rowActionKeys = g(.rowActionKeys, true)
            hiddenApps = g(.hiddenApps, [])
            stickyApps = g(.stickyApps, false)
            hasSeenIntro = g(.hasSeenIntro, false)
        }
    }
}
