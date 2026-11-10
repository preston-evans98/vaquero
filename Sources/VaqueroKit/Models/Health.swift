import Foundation

/// What a component writes to `health/<component>.json`. The file's change time is the heartbeat.
public struct HeartbeatInfo: Codable, Sendable, Hashable {
    public var machine: String
    /// Seconds without a heartbeat before the component counts as stale.
    public var staleAfter: TimeInterval
    public var note: String?

    public init(machine: String, staleAfter: TimeInterval, note: String? = nil) {
        self.machine = machine
        self.staleAfter = staleAfter
        self.note = note
    }
}

public struct Heartbeat: Codable, Sendable, Hashable, Identifiable {
    public var component: String
    public var at: Date
    public var info: HeartbeatInfo

    public var id: String { component }

    public init(component: String, at: Date, info: HeartbeatInfo) {
        self.component = component
        self.at = at
        self.info = info
    }

    public func isStale(now: Date = .now) -> Bool {
        now.timeIntervalSince(at) > info.staleAfter
    }
}

/// Background model use for one day, stored as `usage/<date>.json`.
public struct UsageDay: Codable, Sendable, Hashable, Identifiable {
    /// The day, as yyyy-MM-dd.
    public var date: String
    public var tokens: Int
    /// The hard cap for the day.
    public var cap: Int

    public var id: String { date }

    public init(date: String, tokens: Int, cap: Int) {
        self.date = date
        self.tokens = tokens
        self.cap = cap
    }
}

public struct HealthReport: Codable, Sendable, Hashable {
    public var heartbeats: [Heartbeat]
    /// The most recent days, oldest first.
    public var usage: [UsageDay]

    public init(heartbeats: [Heartbeat], usage: [UsageDay]) {
        self.heartbeats = heartbeats
        self.usage = usage
    }
}
