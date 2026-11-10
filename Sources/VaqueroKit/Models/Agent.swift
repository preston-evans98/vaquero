import Foundation

/// The kind of session an agent runs.
public enum AgentRole: String, Codable, Sendable, CaseIterable {
    case chiefOfStaff
    case lead
    case project
}

/// One agent's definition, stored as `agents/<name>.json` on the server.
public struct AgentSpec: Codable, Sendable, Hashable {
    public var name: String
    public var role: AgentRole
    public var area: String?
    /// The agent that started this one. The chief of staff has none.
    public var parent: String?
    public var model: String
    /// The session's working directory on the server.
    public var workdir: String
    /// The agent's status file, relative to the Drive folder.
    public var statusFile: String
    /// The agent whose session this one copied when it started.
    public var forkOf: String?
    /// True when the owner turned the agent off. It then stays off after a reboot.
    public var off: Bool?

    /// The models a session may run.
    public static let models = ["opus", "sonnet"]

    /// Agent names use lowercase letters, digits and dashes, so they are safe in paths and unit names.
    /// The polkit rule in `deploy/vaquero.rules` checks the same pattern.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 64 && name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
    }

    public init(
        name: String, role: AgentRole, area: String? = nil, parent: String? = nil,
        model: String, workdir: String, statusFile: String, forkOf: String? = nil, off: Bool? = nil
    ) {
        self.name = name
        self.role = role
        self.area = area
        self.parent = parent
        self.model = model
        self.workdir = workdir
        self.statusFile = statusFile
        self.forkOf = forkOf
        self.off = off
    }
}

/// What the supervisor reports about a session.
public enum RunState: String, Codable, Sendable {
    case running
    case starting
    case stopped
    case failed
    case unknown
}

/// An agent with its live state.
public struct Agent: Codable, Sendable, Hashable, Identifiable {
    public var spec: AgentSpec
    public var state: RunState
    /// When the session entered its current state.
    public var since: Date?
    /// When the agent last changed its status file.
    public var statusUpdated: Date?
    /// True when a running lead or project has not changed its status file for the stall limit.
    public var stalled: Bool
    /// Messages waiting in the agent's inbox.
    public var unread: Int

    public var id: String { spec.name }

    public init(
        spec: AgentSpec, state: RunState, since: Date? = nil, statusUpdated: Date? = nil,
        stalled: Bool = false, unread: Int = 0
    ) {
        self.spec = spec
        self.state = state
        self.since = since
        self.statusUpdated = statusUpdated
        self.stalled = stalled
        self.unread = unread
    }
}

public enum AgentAction: String, Codable, Sendable {
    case start
    case stop
    case restart
}

public struct AgentControl: Codable, Sendable {
    public var action: AgentAction
    public init(action: AgentAction) { self.action = action }
}

/// A request to open a session: a lead under the chief of staff, or a project session under a lead.
public struct NewSession: Codable, Sendable {
    public var name: String
    public var parent: String
    public var model: String
    /// The first message the new session reads.
    public var brief: String
    /// When true, the session starts as a copy of its parent's session.
    public var fork: Bool

    public init(name: String, parent: String, model: String, brief: String, fork: Bool) {
        self.name = name
        self.parent = parent
        self.model = model
        self.brief = brief
        self.fork = fork
    }
}

/// A markdown file and the time it last changed.
public struct StatusFile: Codable, Sendable, Hashable {
    public var text: String
    public var updated: Date?

    public init(text: String, updated: Date?) {
        self.text = text
        self.updated = updated
    }
}
