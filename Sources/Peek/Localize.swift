import Foundation
import PeekCore

/// Looks up UI strings. English text is used as the key, so anything without a
/// translation falls back to readable English. `L("Start Peek at login")` returns
/// the string for the user's chosen language (or the system language when set to
/// `.system`).
enum Localize {
    // ponytail: one global for the whole (single-user) app, set from SettingsStore
    // via AppController on launch and whenever the language setting changes.
    static var languageCode: String? = nil   // nil = follow the system

    static func string(_ key: String) -> String {
        (lprojBundle ?? Bundle.module).localizedString(forKey: key, value: key, table: nil)
    }

    /// Whether the active language is right-to-left (Arabic, or a RTL system
    /// language when following the system).
    static var isRTL: Bool {
        if let code = languageCode { return code.hasPrefix("ar") }
        let sys = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale.characterDirection(forLanguage: sys) == .rightToLeft
    }

    private static var lprojBundle: Bundle? {
        guard let code = languageCode else { return nil }
        // SwiftPM lowercases region-qualified .lproj names (zh-Hans -> zh-hans),
        // so try the canonical code then a lowercased fallback.
        let path = Bundle.module.path(forResource: code, ofType: "lproj")
            ?? Bundle.module.path(forResource: code.lowercased(), ofType: "lproj")
        return path.flatMap(Bundle.init(path:))
    }
}

/// Shorthand for `Localize.string`.
func L(_ key: String) -> String { Localize.string(key) }
