import Foundation

/// Ranks windows by learned habits: recency-weighted switch frequency ("affinity"),
/// with user-pinned apps forced to the front. Pure — no AppKit — so it's testable.
public struct WindowRanker {
    public struct Item: Equatable {
        public let app: String
        public let originalIndex: Int
        public init(app: String, originalIndex: Int) {
            self.app = app
            self.originalIndex = originalIndex
        }
    }

    /// Recency-weighted count of switches TO each app. Recent switches weigh more
    /// (exponential decay with the given half-life).
    public static func affinity(events: [SwitchEvent], now: Date = Date(),
                                halfLifeDays: Double = 7) -> [String: Double] {
        let lambda = log(2) / (halfLifeDays * 86_400)
        var scores: [String: Double] = [:]
        for e in events {
            let age = max(0, now.timeIntervalSince(e.timestamp))
            scores[e.toApp, default: 0] += exp(-lambda * age)
        }
        return scores
    }

    /// Display order (as original indices). Pinned apps first in pin order, then the
    /// rest by affinity desc, z-order as tiebreak. `keepFirst` keeps the frontmost
    /// window at index 0 so a quick ⌘-Tab still flips to your top *other* window.
    public static func order(items: [Item], events: [SwitchEvent], pinned: [String],
                             now: Date = Date(), halfLifeDays: Double = 7,
                             keepFirst: Bool = true) -> [Int] {
        let aff = affinity(events: events, now: now, halfLifeDays: halfLifeDays)
        var pinRank: [String: Int] = [:]
        for (i, app) in pinned.enumerated() { pinRank[app] = i }

        // Lower tuple sorts earlier: pinned-group, pin-order, -affinity, z-order.
        func key(_ it: Item) -> (Int, Int, Double, Int) {
            let p = pinRank[it.app]
            return (p == nil ? 1 : 0, p ?? 0, -(aff[it.app] ?? 0), it.originalIndex)
        }

        guard keepFirst, let first = items.first else {
            return items.sorted { key($0) < key($1) }.map(\.originalIndex)
        }
        let rest = items.dropFirst().sorted { key($0) < key($1) }
        return [first.originalIndex] + rest.map(\.originalIndex)
    }
}
