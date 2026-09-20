import Foundation

/// Persists switch events as JSON in Application Support (or a custom URL for tests).
public final class StatsStore {
    private let url: URL
    public private(set) var events: [SwitchEvent]

    public init(url customURL: URL? = nil) {
        self.url = customURL ?? AppSupport.url("stats.json")
        self.events = StatsStore.load(from: url)
    }

    private static func load(from url: URL) -> [SwitchEvent] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SwitchEvent].self, from: data)) ?? []
    }

    public func record(_ event: SwitchEvent) {
        events.append(event)
        // ponytail: rewrites the whole file each switch; fine to thousands of events, switch to an append-log if it ever matters.
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
