import Foundation

/// Small persisted settings. Sticky-apps ordering is OPT-IN (off by default).
public final class SettingsStore {
    private struct Payload: Codable {
        var stickyApps = false
        var hasSeenIntro = false
    }

    private let url: URL
    private var data: Payload

    public init(url customURL: URL? = nil) {
        self.url = customURL ?? AppSupport.url("settings.json")
        if let d = try? Data(contentsOf: url),
           let parsed = try? JSONDecoder().decode(Payload.self, from: d) {
            self.data = parsed
        } else {
            self.data = Payload()
        }
    }

    public var stickyApps: Bool {
        get { data.stickyApps }
        set { data.stickyApps = newValue; save() }
    }

    public var hasSeenIntro: Bool {
        get { data.hasSeenIntro }
        set { data.hasSeenIntro = newValue; save() }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(data) { try? d.write(to: url, options: .atomic) }
    }
}
