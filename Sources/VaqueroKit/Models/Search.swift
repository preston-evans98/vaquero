import Foundation

/// A question for the message archive.
public struct SearchQuery: Codable, Sendable, Hashable {
    public var text: String
    public var contact: String?
    public var from: Date?
    public var to: Date?

    public init(text: String, contact: String? = nil, from: Date? = nil, to: Date? = nil) {
        self.text = text
        self.contact = contact
        self.from = from
        self.to = to
    }
}

public struct SearchHit: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var channel: Channel
    public var chat: String
    public var sender: String
    public var at: Date
    public var text: String
    public var score: Double

    public init(id: String, channel: Channel, chat: String, sender: String, at: Date, text: String, score: Double) {
        self.id = id
        self.channel = channel
        self.chat = chat
        self.sender = sender
        self.at = at
        self.text = text
        self.score = score
    }
}
