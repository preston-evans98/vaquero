import Foundation

/// The config files that only the owner writes.
public enum ConfigFile: String, Codable, Sendable, CaseIterable {
    case lists
    case routing
    case nudges
    case priorities
    case tools

    /// The chief of staff may propose changes to the routing map, the nudges and the priority rules.
    /// The chat lists name private chats, so no model reads them. The tool rules limit the agents,
    /// so no agent proposes them.
    public var acceptsProposals: Bool {
        switch self {
        case .routing, .nudges, .priorities: true
        case .lists, .tools: false
        }
    }
}

/// A config file's content type. Each type knows its file and its on-disk format.
public protocol ConfigDocument: Codable, Sendable, Hashable {
    static var file: ConfigFile { get }
    /// The value of a file that does not exist yet.
    static var empty: Self { get }
    init(fileData: Data) throws
    func fileData() throws -> Data
    /// Why the value cannot be saved, or nil when it can.
    var problem: String? { get }
}

extension ConfigDocument {
    public init(fileData: Data) throws {
        self = try JSONDecoder.vaquero.decode(Self.self, from: fileData)
    }

    public func fileData() throws -> Data {
        try JSONEncoder.vaquero.encode(self)
    }

    public var problem: String? { nil }
}

/// A config value with the version it came from. A write must carry the version it replaces.
public struct Versioned<Value: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    public var etag: String
    public var value: Value

    public init(etag: String, value: Value) {
        self.etag = etag
        self.value = value
    }
}

// MARK: Chat lists

public enum ChatListKind: String, Codable, Sendable, CaseIterable {
    /// Read live; leads act on new messages.
    case continuous
    /// Stored and searchable; read only when a task needs it.
    case searchable
    /// Never searched, even on request.
    case blocked
}

/// How strictly the local filter holds back sensitive messages from a chat.
public enum Strictness: String, Codable, Sendable, CaseIterable {
    case strict
    case normal
    case light
}

public struct ChatRule: Codable, Sendable, Hashable, Identifiable {
    public var channel: Channel
    /// The chat's id on its channel.
    public var chat: String
    public var title: String
    public var list: ChatListKind
    public var strictness: Strictness

    public var id: String { "\(channel.rawValue):\(chat)" }

    public init(channel: Channel, chat: String, title: String, list: ChatListKind, strictness: Strictness) {
        self.channel = channel
        self.chat = chat
        self.title = title
        self.list = list
        self.strictness = strictness
    }
}

/// Every chat on a list. A chat on no list does not appear, and no chat appears twice.
public struct ChatLists: ConfigDocument {
    public static let file = ConfigFile.lists
    public static let empty = ChatLists(chats: [])
    public var chats: [ChatRule]
    public init(chats: [ChatRule]) { self.chats = chats }

    public var problem: String? {
        let twice = Dictionary(grouping: chats, by: \.id).filter { $0.value.count > 1 }.keys.sorted()
        return twice.isEmpty ? nil : "These chats are on the lists more than once: \(twice.joined(separator: ", "))."
    }
}

// MARK: Routing map

public struct Route: Codable, Sendable, Hashable, Identifiable {
    /// Tells routes apart in the apps. The file does not store it.
    public var id = UUID()
    public var area: String
    /// The lead that gets this area's messages.
    public var lead: String
    /// The contacts and topics that belong to the area, in plain words.
    public var match: String

    private enum CodingKeys: String, CodingKey { case area, lead, match }

    public init(area: String, lead: String, match: String) {
        self.area = area
        self.lead = lead
        self.match = match
    }
}

public struct RoutingMap: ConfigDocument {
    public static let file = ConfigFile.routing
    public static let empty = RoutingMap(routes: [])
    public var routes: [Route]
    public init(routes: [Route]) { self.routes = routes }
}

// MARK: Nudges

public struct Nudge: Codable, Sendable, Hashable, Identifiable {
    /// Tells nudges apart in the apps. The file does not store it.
    public var id = UUID()
    public var lead: String
    public var goal: String
    public var everyHours: Int
    /// Tell the owner if nothing passes review for this many days.
    public var tellOwnerAfterDays: Int?

    private enum CodingKeys: String, CodingKey { case lead, goal, everyHours, tellOwnerAfterDays }

    public init(lead: String, goal: String, everyHours: Int, tellOwnerAfterDays: Int? = nil) {
        self.lead = lead
        self.goal = goal
        self.everyHours = everyHours
        self.tellOwnerAfterDays = tellOwnerAfterDays
    }
}

public struct NudgePlan: ConfigDocument {
    public static let file = ConfigFile.nudges
    public static let empty = NudgePlan(stallDays: 3, nudges: [])
    /// The chief of staff nudges a lead whose status has not changed for this many days.
    public var stallDays: Int
    public var nudges: [Nudge]

    public init(stallDays: Int, nudges: [Nudge]) {
        self.stallDays = stallDays
        self.nudges = nudges
    }
}

// MARK: Priority rules

/// The rules for what counts as urgent, as markdown.
public struct Priorities: ConfigDocument {
    public static let file = ConfigFile.priorities
    public static let empty = Priorities(text: "")
    public var text: String

    public init(text: String) { self.text = text }

    public init(fileData: Data) throws {
        text = String(decoding: fileData, as: UTF8.self)
    }

    public func fileData() throws -> Data { Data(text.utf8) }
}

// MARK: Tool rules

/// The tools agent sessions may use, as Claude Code permission rules such as `Read` or `Bash(git log:*)`.
/// Sessions run unattended, so a tool on neither list is refused rather than asked about.
public struct ToolRules: ConfigDocument {
    public static let file = ConfigFile.tools
    public static let empty = ToolRules(allow: ["Read", "Glob", "Grep", "Edit", "Write", "TodoWrite"], deny: [])
    public var allow: [String]
    public var deny: [String]

    public init(allow: [String], deny: [String]) {
        self.allow = allow
        self.deny = deny
    }
}

extension ConfigFile {
    /// The document type stored in this file.
    public var documentType: any ConfigDocument.Type {
        switch self {
        case .lists: ChatLists.self
        case .routing: RoutingMap.self
        case .nudges: NudgePlan.self
        case .priorities: Priorities.self
        case .tools: ToolRules.self
        }
    }

    /// The file's content in the form the apps write, or nil if it does not parse.
    /// Two versions of a file compare cleanly only in this form.
    public func canonical(_ content: String) -> String? {
        guard let document = try? documentType.init(fileData: Data(content.utf8)), let data = try? document.fileData() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
