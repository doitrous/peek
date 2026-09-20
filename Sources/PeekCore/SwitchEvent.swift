import Foundation

/// One recorded window switch.
public struct SwitchEvent: Codable, Equatable {
    public let timestamp: Date
    public let fromApp: String?
    public let toApp: String

    public init(timestamp: Date = Date(), fromApp: String?, toApp: String) {
        self.timestamp = timestamp
        self.fromApp = fromApp
        self.toApp = toApp
    }
}
