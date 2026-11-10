import Foundation

public enum HTTPVerb: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
}

/// The body of a request or response that carries nothing.
public struct Empty: Codable, Sendable, Hashable {
    public init() {}
}

/// One route of the control service, with its request and response types.
/// A path segment that starts with ":" is a parameter.
public struct Endpoint<Request: Codable & Sendable, Response: Codable & Sendable>: Sendable {
    public let verb: HTTPVerb
    public let path: String

    public init(_ verb: HTTPVerb, _ path: String) {
        self.verb = verb
        self.path = path
    }

    /// The path with each parameter replaced by the next value, in order.
    public func path(_ values: [String]) -> String {
        var remaining = values[...]
        return path.split(separator: "/").map { segment in
            guard segment.hasPrefix(":"), let value = remaining.popFirst() else { return String(segment) }
            return value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? value
        }.joined(separator: "/")
    }
}

/// Every route of the control service. The server and the apps both use this table.
public enum API {
    public static let agents = Endpoint<Empty, [Agent]>(.get, "agents")
    public static let newSession = Endpoint<NewSession, Agent>(.post, "agents")
    public static let control = Endpoint<AgentControl, Agent>(.post, "agents/:name/control")
    public static let status = Endpoint<Empty, StatusFile>(.get, "agents/:name/status")
    public static let conversation = Endpoint<Empty, Conversation>(.get, "agents/:name/conversation")
    public static let message = Endpoint<OwnerMessage, BusMessage>(.post, "agents/:name/messages")

    public static let queue = Endpoint<Empty, [QueueItem]>(.get, "queue")
    public static let resolve = Endpoint<Answer, QueueItem>(.post, "queue/:id/resolve")

    public static let log = Endpoint<Empty, [LogEntry]>(.get, "log")
    /// Resolved queue items, newest first.
    public static let decisions = Endpoint<Empty, [QueueItem]>(.get, "decisions")
    public static let search = Endpoint<SearchQuery, [SearchHit]>(.post, "search")
    public static let health = Endpoint<Empty, HealthReport>(.get, "health")

    public static func readConfig<D: ConfigDocument>(_: D.Type) -> Endpoint<Empty, Versioned<D>> {
        Endpoint(.get, "config/\(D.file.rawValue)")
    }

    /// Fails with 409 Conflict when the file changed since the version in the request.
    public static func writeConfig<D: ConfigDocument>(_: D.Type) -> Endpoint<Versioned<D>, Versioned<D>> {
        Endpoint(.put, "config/\(D.file.rawValue)")
    }

    /// A stream of server-sent events. Each event's data is one `Change` as JSON.
    public static let events = "events"
}

/// What changed on the server. The apps reload the topic when they hear it.
public enum Topic: String, Codable, Sendable, CaseIterable {
    case agents
    case queue
    case log
    case decisions
    case health
    case config
    /// An agent's transcript or inbox. The key names the agent.
    case conversation
}

public struct Change: Codable, Sendable, Hashable {
    public var topic: Topic
    public var key: String?

    public init(_ topic: Topic, key: String? = nil) {
        self.topic = topic
        self.key = key
    }
}

extension JSONEncoder {
    /// The encoder for every Vaquero file and request.
    public static var vaquero: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    /// The decoder for every Vaquero file and request.
    public static var vaquero: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
