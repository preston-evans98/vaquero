import Foundation

/// One message on the bus, stored as `bus/<to>/inbox/<id>.md`.
public struct BusMessage: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var from: String
    public var to: String
    public var at: Date
    public var text: String

    public init(id: String, from: String, to: String, at: Date, text: String) {
        self.id = id
        self.from = from
        self.to = to
        self.at = at
        self.text = text
    }
}

/// Text the owner sends to an agent.
public struct OwnerMessage: Codable, Sendable {
    public var text: String
    public init(text: String) { self.text = text }
}

public enum Speaker: String, Codable, Sendable {
    case user
    case assistant
    case tool
}

/// One turn from an agent's session transcript.
public struct TranscriptEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var at: Date?
    public var speaker: Speaker
    public var text: String

    public init(id: String, at: Date?, speaker: Speaker, text: String) {
        self.id = id
        self.at = at
        self.speaker = speaker
        self.text = text
    }
}

/// An agent's recent transcript and the bus messages sent to it.
public struct Conversation: Codable, Sendable, Hashable {
    public var entries: [TranscriptEntry]
    /// Messages the agent has finished with.
    public var read: [BusMessage]
    /// Messages still waiting in the agent's inbox.
    public var unread: [BusMessage]

    public init(entries: [TranscriptEntry], read: [BusMessage], unread: [BusMessage]) {
        self.entries = entries
        self.read = read
        self.unread = unread
    }

    /// The transcript and the messages, oldest first.
    public var timeline: [TimelineItem] {
        let items = entries.map(TimelineItem.entry)
            + read.map { TimelineItem.message($0, read: true) }
            + unread.map { TimelineItem.message($0, read: false) }
        return items.sorted { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }
    }
}

public enum TimelineItem: Sendable, Hashable, Identifiable {
    case entry(TranscriptEntry)
    case message(BusMessage, read: Bool)

    public var id: String {
        switch self {
        case let .entry(entry): "entry-\(entry.id)"
        case let .message(message, _): "message-\(message.id)"
        }
    }

    public var at: Date? {
        switch self {
        case let .entry(entry): entry.at
        case let .message(message, _): message.at
        }
    }
}
