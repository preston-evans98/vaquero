import Foundation

public enum Channel: String, Codable, Sendable, CaseIterable {
    case gmail
    case mail
    case telegram
    case whatsapp
    case imessage
    case slack
    case instagram
    case x
    case phone
}

public enum Urgency: String, Codable, Sendable, Comparable {
    case urgent
    case normal
    case low

    public static func < (a: Urgency, b: Urgency) -> Bool { a.rank < b.rank }

    private var rank: Int {
        switch self {
        case .urgent: 0
        case .normal: 1
        case .low: 2
        }
    }
}

public enum QueueKind: String, Codable, Sendable {
    /// A reply a lead wants to send.
    case draft
    /// Advice from a lead that needs the owner's answer.
    case advice
    /// A message the local filter kept away from every model. The sorter adds these.
    case heldBack
    /// A change to an owner-owned config file that the chief of staff proposes.
    case configChange
}

/// A new version of a config file, as raw file content.
public struct ConfigChange: Codable, Sendable, Hashable {
    public var file: ConfigFile
    public var content: String
    /// The file as it is now. The server fills this in when it serves the item.
    public var current: String?

    public init(file: ConfigFile, content: String, current: String? = nil) {
        self.file = file
        self.content = content
        self.current = current
    }
}

/// The owner's answer to a queue item.
public enum Verdict: String, Codable, Sendable {
    /// Send the draft, accept the advice, release the held-back message, or apply the change.
    case approve
    /// Drop the draft or advice, keep the held-back message private, or reject the change.
    case ignore
}

/// The owner's answer, as the apps or the Telegram bot send it.
public struct Answer: Codable, Sendable, Hashable {
    public var verdict: Verdict
    /// The owner's edited reply, when it differs from the draft.
    public var text: String?
    /// The version of the item the owner saw. The answer fails if the item changed since.
    public var version: String

    public init(verdict: Verdict, text: String? = nil, version: String) {
        self.verdict = verdict
        self.text = text
        self.version = version
    }
}

/// The owner's answer as the server records it.
public struct Resolution: Codable, Sendable, Hashable {
    public var verdict: Verdict
    public var text: String?
    /// Where the owner answered: "app" or "telegram".
    public var by: String
    public var at: Date
    public var version: String

    public init(_ answer: Answer, by: String, at: Date) {
        verdict = answer.verdict
        text = answer.text
        version = answer.version
        self.by = by
        self.at = at
    }
}

/// One item in the owner's queue. It waits in `queue/pending/` and then moves to
/// `queue/resolved/<month>/` with the owner's answer. The resolved items are the decision history.
public struct QueueItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: QueueKind
    public var created: Date
    public var urgency: Urgency
    /// The agent that raised the item.
    public var lead: String
    public var channel: Channel?
    public var chat: String?
    public var sender: String?
    /// One line about the item. For a held-back message, only who sent it.
    public var gist: String
    public var draft: String?
    public var advice: String?
    /// Thread excerpts and notes from other areas.
    public var context: String?
    public var change: ConfigChange?
    public var resolution: Resolution?
    /// A hash of what the owner sees. The server fills this in when it serves the item.
    public var version: String?

    public init(
        id: String, kind: QueueKind, created: Date, urgency: Urgency, lead: String,
        channel: Channel? = nil, chat: String? = nil, sender: String? = nil, gist: String,
        draft: String? = nil, advice: String? = nil, context: String? = nil,
        change: ConfigChange? = nil, resolution: Resolution? = nil, version: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.created = created
        self.urgency = urgency
        self.lead = lead
        self.channel = channel
        self.chat = chat
        self.sender = sender
        self.gist = gist
        self.draft = draft
        self.advice = advice
        self.context = context
        self.change = change
        self.resolution = resolution
        self.version = version
    }

    /// Urgent items first, then oldest first.
    public static func ordered(_ a: QueueItem, _ b: QueueItem) -> Bool {
        a.urgency == b.urgency ? a.created < b.created : a.urgency < b.urgency
    }

    /// True when the owner changed the draft before sending it.
    public var edited: Bool {
        guard let text = resolution?.text else { return false }
        return text != draft
    }
}

/// One line in the chief of staff's message log, stored in `log/<date>.jsonl`.
public struct LogEntry: Codable, Sendable, Hashable {
    public var at: Date
    public var channel: Channel
    public var chat: String
    public var sender: String
    public var gist: String
    /// The agent that owns the message.
    public var owner: String

    public init(at: Date, channel: Channel, chat: String, sender: String, gist: String, owner: String) {
        self.at = at
        self.channel = channel
        self.chat = chat
        self.sender = sender
        self.gist = gist
        self.owner = owner
    }
}
