import Foundation

/// Persists the user's pinned apps (ordered) as JSON.
public final class PinStore {
    private let url: URL
    public private(set) var pinned: [String]

    public init(url customURL: URL? = nil) {
        self.url = customURL ?? AppSupport.url("pins.json")
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            self.pinned = list
        } else {
            self.pinned = []
        }
    }

    public func isPinned(_ app: String) -> Bool { pinned.contains(app) }

    public func toggle(_ app: String) {
        if let i = pinned.firstIndex(of: app) { pinned.remove(at: i) } else { pinned.append(app) }
        if let data = try? JSONEncoder().encode(pinned) { try? data.write(to: url, options: .atomic) }
    }
}
