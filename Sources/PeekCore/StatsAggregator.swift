import Foundation

/// Pure aggregation over recorded switches. No I/O, no AppKit — the tested core.
public struct StatsAggregator {
    public let events: [SwitchEvent]
    private let calendar: Calendar

    public init(events: [SwitchEvent], calendar: Calendar = .current) {
        self.events = events
        self.calendar = calendar
    }

    public var totalSwitches: Int { events.count }

    /// Switches grouped by day (start-of-day), ascending.
    public func switchesPerDay() -> [(day: Date, count: Int)] {
        var buckets: [Date: Int] = [:]
        for e in events {
            buckets[calendar.startOfDay(for: e.timestamp), default: 0] += 1
        }
        return buckets.sorted { $0.key < $1.key }.map { (day: $0.key, count: $0.value) }
    }

    /// Apps switched TO, most frequent first (ties broken alphabetically).
    public func topApps(limit: Int = 10) -> [(app: String, count: Int)] {
        var buckets: [String: Int] = [:]
        for e in events { buckets[e.toApp, default: 0] += 1 }
        return rank(buckets, limit: limit).map { (app: $0.key, count: $0.value) }
    }

    /// Count of switches per hour-of-day, indices 0...23.
    public func hourlyHistogram() -> [Int] {
        var hours = [Int](repeating: 0, count: 24)
        for e in events {
            let h = calendar.component(.hour, from: e.timestamp)
            if (0..<24).contains(h) { hours[h] += 1 }
        }
        return hours
    }

    /// Most common from→to transitions.
    public func topTransitions(limit: Int = 8) -> [(from: String, to: String, count: Int)] {
        let sep = "\u{1}"
        var buckets: [String: Int] = [:]
        for e in events {
            guard let from = e.fromApp else { continue }
            buckets["\(from)\(sep)\(e.toApp)", default: 0] += 1
        }
        return rank(buckets, limit: limit).compactMap { pair in
            let parts = pair.key.components(separatedBy: sep)
            guard parts.count == 2 else { return nil }
            return (from: parts[0], to: parts[1], count: pair.value)
        }
    }

    private func rank(_ buckets: [String: Int], limit: Int) -> [(key: String, value: Int)] {
        buckets.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }
}
