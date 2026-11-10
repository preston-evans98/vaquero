import Foundation
import Observation
import VaqueroKit

public enum Connection: Equatable, Sendable {
    case notConfigured
    case connecting
    case live
    case offline(String)
}

/// The apps' view of the server. It listens to the server's stream of changes and reloads each
/// topic the stream names. On connecting, the stream names every topic, so everything loads.
@MainActor @Observable
public final class AppModel {
    public private(set) var settings: ServerSettings
    public private(set) var connection = Connection.notConfigured
    /// Topics that failed to load while the connection itself works, with the reason.
    public private(set) var loadErrors: [Topic: String] = [:]
    public private(set) var agents: [Agent] = []
    public private(set) var queue: [QueueItem] = []
    public private(set) var log: [LogEntry] = []
    /// Resolved queue items, newest answer first.
    public private(set) var decisions: [QueueItem] = []
    public private(set) var health: HealthReport?
    public private(set) var conversations: [String: Conversation] = [:]
    /// Goes up by one each time a config file changes on the server.
    public private(set) var configRevision = 0
    /// The current time, updated every 15 seconds, so stale heartbeats show even when nothing changes.
    public private(set) var now = Date()
    /// The last failed action, for an alert.
    public var failure: String?

    private var watched: [String: Int] = [:]
    private var following: Task<Void, Never>?
    private var clock: Task<Void, Never>?

    public init(settings: ServerSettings = .load()) {
        self.settings = settings
    }

    public func connect(_ settings: ServerSettings? = nil) {
        if let settings {
            settings.save()
            self.settings = settings
        }
        following?.cancel()
        following = Task { await follow() }
        clock = clock ?? Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                now = .now
            }
        }
    }

    // MARK: Lookups

    public func agent(_ name: String) -> Agent? {
        agents.first { $0.id == name }
    }

    public func children(of name: String?) -> [Agent] {
        agents.filter { $0.spec.parent == name }.sorted { $0.id < $1.id }
    }

    public var leads: [Agent] {
        agents.filter { $0.spec.role == .lead }.sorted { $0.id < $1.id }
    }

    /// Agents that need the owner's eye: stalled or failed.
    public var troubled: [Agent] {
        agents.filter { $0.stalled || $0.state == .failed }
    }

    public var staleHeartbeats: [Heartbeat] {
        health?.heartbeats.filter { $0.isStale(now: now) } ?? []
    }

    // MARK: Actions

    /// Answers a queue item. The item leaves the list at once and comes back if the answer fails.
    public func resolve(_ item: QueueItem, _ verdict: Verdict, text: String? = nil) async {
        queue.removeAll { $0.id == item.id }
        let answer = Answer(verdict: verdict, text: text, version: item.version ?? "")
        do {
            _ = try await client().send(API.resolve, item.id, body: answer)
        } catch {
            failure = error.localizedDescription
            try? await refresh(Change(.queue))
        }
    }

    public func control(_ agent: Agent, _ action: AgentAction) async {
        await attempt {
            let updated = try await client().send(API.control, agent.id, body: AgentControl(action: action))
            replace(updated)
        }
    }

    public func open(_ session: NewSession) async throws -> Agent {
        let agent = try await client().send(API.newSession, body: session)
        replace(agent)
        return agent
    }

    /// Sends a message to an agent, and returns false if it could not.
    public func send(_ text: String, to agent: String) async -> Bool {
        do {
            _ = try await client().send(API.message, agent, body: OwnerMessage(text: text))
        } catch {
            failure = error.localizedDescription
            return false
        }
        try? await refresh(Change(.conversation, key: agent))
        return true
    }

    public func status(of agent: String) async throws -> StatusFile {
        try await client().get(API.status, agent)
    }

    public func search(_ query: SearchQuery) async throws -> [SearchHit] {
        try await client().send(API.search, body: query)
    }

    public func readConfig<D: ConfigDocument>(_: D.Type) async throws -> Versioned<D> {
        try await client().get(API.readConfig(D.self))
    }

    public func writeConfig<D: ConfigDocument>(_ update: Versioned<D>) async throws -> Versioned<D> {
        try await client().send(API.writeConfig(D.self), body: update)
    }

    /// Keeps an agent's conversation loaded while a view shows it. Pair with `unwatch`.
    public func watch(_ agent: String) async {
        watched[agent, default: 0] += 1
        try? await refresh(Change(.conversation, key: agent))
    }

    public func unwatch(_ agent: String) {
        watched[agent, default: 1] -= 1
        if watched[agent] == 0 { watched[agent] = nil }
    }

    // MARK: Loading

    private func follow() async {
        while !Task.isCancelled {
            guard let client = settings.client else {
                connection = .notConfigured
                return
            }
            connection = .connecting
            do {
                for try await change in client.changes() {
                    connection = .live
                    try await refresh(change)
                }
                connection = .offline("The server closed the connection.")
            } catch is CancellationError {
                return
            } catch {
                connection = .offline(error.localizedDescription)
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    /// Reloads one topic. A server error marks only that topic; a network error ends the connection.
    private func refresh(_ change: Change) async throws {
        do {
            try await load(change)
            loadErrors[change.topic] = nil
        } catch let error as URLError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            loadErrors[change.topic] = error.localizedDescription
        }
    }

    private func load(_ change: Change) async throws {
        let client = try client()
        switch change.topic {
        case .agents: agents = try await client.get(API.agents)
        case .queue: queue = try await client.get(API.queue)
        case .log: log = try await client.get(API.log)
        case .decisions: decisions = try await client.get(API.decisions)
        case .health: health = try await client.get(API.health)
        case .config: configRevision += 1
        case .conversation:
            guard let agent = change.key, watched[agent] != nil else { return }
            conversations[agent] = try await client.get(API.conversation, agent)
        }
    }

    private func replace(_ agent: Agent) {
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }
    }

    private func attempt(_ action: () async throws -> Void) async {
        do {
            try await action()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func client() throws -> Client {
        guard let client = settings.client else { throw ClientError.status(0, "Set the server address and token in Settings.") }
        return client
    }
}
