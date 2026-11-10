import Foundation
import Hummingbird
import VaqueroKit

/// Reads and writes the owner's config files. A write must name the version it replaces.
actor ConfigStore {
    let paths: Paths

    init(paths: Paths) { self.paths = paths }

    func read<D: ConfigDocument>(_: D.Type) throws -> Versioned<D> {
        let url = paths.config(D.file)
        let data = Files.read(url)
        do {
            return Versioned(etag: Files.etag(data), value: try data.map(D.init(fileData:)) ?? D.empty)
        } catch {
            throw HTTPError(.unprocessableContent, message: "\(url.path) does not parse, so fix it by hand: \(error)")
        }
    }

    /// Writes the default file when there is none, for files that other programs read directly.
    func writeDefault<D: ConfigDocument>(_: D.Type) throws {
        let url = paths.config(D.file)
        if Files.read(url) == nil { try Files.write(D.empty.fileData(), to: url) }
    }

    func write<D: ConfigDocument>(_ update: Versioned<D>) throws -> Versioned<D> {
        if let problem = update.value.problem {
            throw HTTPError(.unprocessableContent, message: problem)
        }
        let url = paths.config(D.file)
        guard Files.etag(Files.read(url)) == update.etag else {
            throw HTTPError(.conflict, message: "\(D.file.rawValue) changed since it was read.")
        }
        try Files.write(update.value.fileData(), to: url)
        return try read(D.self)
    }

    /// Writes a change the chief of staff proposed and the owner approved. `commit` claims the
    /// queue item; it runs only after every check passes, and the file changes only if it succeeds.
    func apply(_ change: ConfigChange, commit: @Sendable () throws -> Void) throws {
        guard change.file.acceptsProposals else {
            throw HTTPError(.forbidden, message: "Only the owner changes the \(change.file.rawValue) file.")
        }
        guard let document = try? change.file.documentType.init(fileData: Data(change.content.utf8)),
              let content = change.file.canonical(change.content)
        else {
            throw HTTPError(.unprocessableContent, message: "The proposed \(change.file.rawValue) file does not parse.")
        }
        if let problem = document.problem {
            throw HTTPError(.unprocessableContent, message: problem)
        }
        let url = paths.config(change.file)
        guard Files.read(url).map({ String(decoding: $0, as: UTF8.self) }) == change.current else {
            throw HTTPError(.conflict, message: "\(change.file.rawValue) changed since the proposal was shown.")
        }
        try commit()
        try Files.write(Data(content.utf8), to: url)
    }
}

/// The agent roster, with live state from the supervisor.
struct AgentStore: Sendable {
    let paths: Paths
    let supervisor: any Supervisor
    let bus: Bus
    let config: ConfigStore

    func specs() -> [AgentSpec] {
        Files.list(paths.agents, ext: "json").compactMap { try? Files.readJSON(AgentSpec.self, at: $0) }
    }

    func spec(_ name: String) throws -> AgentSpec {
        guard AgentSpec.isValidName(name), let spec = try? Files.readJSON(AgentSpec.self, at: paths.agent(name)) else {
            throw HTTPError(.notFound, message: "No agent named \(name).")
        }
        return spec
    }

    func agents() async -> [Agent] {
        let specs = specs()
        let states = await supervisor.states(of: specs.map(\.name))
        let stallDays = await stallDays()
        return specs.map { agent($0, states[$0.name], stallDays: stallDays) }
    }

    func agent(_ name: String) async throws -> Agent {
        let spec = try spec(name)
        return agent(spec, await supervisor.states(of: [name])[name], stallDays: await stallDays())
    }

    /// Starts, stops or restarts a session. Starting and stopping also record the owner's wish,
    /// so the agent comes back, or stays off, after a reboot.
    func control(_ name: String, _ action: AgentAction) async throws -> Agent {
        var spec = try spec(name)
        if action != .restart {
            spec.off = action == .stop ? true : nil
            try Files.writeJSON(spec, to: paths.agent(name))
        }
        try await supervisor.perform(action, on: name)
        return try await agent(name)
    }

    /// Starts every agent the owner has not turned off. The server does this when it starts.
    func startAll() async {
        let specs = specs().filter { $0.off != true }
        let states = await supervisor.states(of: specs.map(\.name))
        for spec in specs where ![.running, .starting].contains(states[spec.name]?.state) {
            try? await supervisor.perform(.start, on: spec.name)
        }
    }

    /// Writes the new session's definition and brief, then starts it. The chief of staff opens leads;
    /// a lead opens project sessions. The brief arrives as mail from the parent.
    func open(_ session: NewSession) async throws -> Agent {
        let parent = try spec(session.parent)
        guard AgentSpec.isValidName(session.name) else {
            throw HTTPError(.badRequest, message: "Use only lowercase letters, digits and dashes in a session name, at most 64 of them.")
        }
        guard AgentSpec.models.contains(session.model) else {
            throw HTTPError(.badRequest, message: "Pick one of these models: \(AgentSpec.models.joined(separator: ", ")).")
        }
        guard (try? spec(session.name)) == nil else {
            throw HTTPError(.conflict, message: "An agent named \(session.name) already exists.")
        }
        let spec: AgentSpec
        switch parent.role {
        case .chiefOfStaff:
            spec = AgentSpec(
                name: session.name, role: .lead, area: session.name, parent: parent.name, model: session.model,
                workdir: paths.sessions.appending(path: session.name).path,
                statusFile: "areas/\(session.name)/status.md",
                forkOf: session.fork ? parent.name : nil
            )
        case .lead:
            let area = parent.area ?? parent.name
            spec = AgentSpec(
                name: session.name, role: .project, area: area, parent: parent.name, model: session.model,
                workdir: paths.sessions.appending(path: session.name).path,
                statusFile: "areas/\(area)/projects/\(session.name).md",
                forkOf: session.fork ? parent.name : nil
            )
        case .project:
            throw HTTPError(.badRequest, message: "A project session cannot open sessions.")
        }
        try Files.makeFolder(URL(filePath: spec.workdir), .shared)
        try Files.writeJSON(spec, to: paths.agent(spec.name))
        let now = Date()
        let brief = BusMessage(id: Bus.newID(at: now), from: parent.name, to: spec.name, at: now, text: session.brief)
        do {
            try bus.post(brief)
            try await supervisor.perform(.start, on: spec.name)
        } catch {
            // Undo, so the owner can try again under the same name.
            try? FileManager.default.removeItem(at: paths.agent(spec.name))
            try? FileManager.default.removeItem(at: paths.inbox(spec.name).appending(path: "\(brief.id).md"))
            throw error
        }
        return try await agent(spec.name)
    }

    func status(_ name: String) throws -> StatusFile {
        let url = paths.status(try spec(name))
        return StatusFile(text: Files.read(url).map { String(decoding: $0, as: UTF8.self) } ?? "", updated: Files.modified(url))
    }

    func conversation(_ name: String) throws -> Conversation {
        Conversation(entries: Transcript.recent(in: paths.transcripts(try spec(name))), read: bus.read(name), unread: bus.unread(name))
    }

    /// Posts the owner's message, and starts the agent if it is not running.
    func message(_ name: String, _ text: String) async throws -> BusMessage {
        let current = try await agent(name)
        let now = Date()
        let message = BusMessage(id: Bus.newID(at: now), from: "owner", to: name, at: now, text: text)
        try bus.post(message)
        if ![.running, .starting].contains(current.state) {
            _ = try await control(name, .start)
        }
        return message
    }

    /// The stall limit, or the default when the nudges file does not parse.
    private func stallDays() async -> Int {
        (try? await config.read(NudgePlan.self))?.value.stallDays ?? NudgePlan.empty.stallDays
    }

    private func agent(_ spec: AgentSpec, _ session: SessionState?, stallDays: Int) -> Agent {
        let state = session?.state ?? .unknown
        let updated = Files.modified(paths.status(spec))
        let stallLimit = Date().addingTimeInterval(-Double(stallDays) * 86_400)
        let stalled = spec.role != .chiefOfStaff && state == .running && (updated ?? .distantPast) < stallLimit
        return Agent(spec: spec, state: state, since: session?.since, statusUpdated: updated, stalled: stalled, unread: bus.unread(spec.name).count)
    }
}

/// The owner's queue. To resolve an item, the server writes the answered item into `resolved/`
/// under a name that only one writer can create, then removes the pending file. So when the app
/// and the Telegram bot answer at once, only the first answer counts, and a reader of `resolved/`
/// never sees an item without its answer.
struct QueueStore: Sendable {
    let paths: Paths
    let config: ConfigStore

    func pending() -> [QueueItem] {
        Files.list(paths.pending, ext: "json")
            .compactMap(load)
            // A crash between the two steps of `resolve` can leave a pending copy of a resolved item.
            .filter { !FileManager.default.fileExists(atPath: paths.resolved($0).path) }
            .sorted(by: QueueItem.ordered)
    }

    /// Records an answer. The server, not the caller, says when and where the owner answered.
    func resolve(_ id: String, _ answer: Answer, by: String) async throws -> QueueItem {
        let resolution = Resolution(answer, by: by, at: .now)
        guard let item = load(paths.pending(id)) else {
            throw isResolved(id)
                ? HTTPError(.conflict, message: "This item is already resolved.")
                : HTTPError(.notFound, message: "No queue item \(id).")
        }
        guard resolution.version == item.version else {
            throw HTTPError(.conflict, message: "This item changed since you saw it.")
        }
        var answered = item
        answered.resolution = resolution
        let data = try JSONEncoder.vaquero.encode(answered)
        let target = paths.resolved(item)
        let claim: @Sendable () throws -> Void = {
            guard try Files.create(data, at: target) else {
                throw HTTPError(.conflict, message: "This item is already resolved.")
            }
        }
        if let change = item.change, resolution.verdict == .approve {
            try await config.apply(change, commit: claim)
        } else {
            try claim()
        }
        try? FileManager.default.removeItem(at: paths.pending(id))
        return answered
    }

    /// A pending item, with its version: a hash of the file and, for a proposed config change,
    /// of the file it would replace. So the version changes whenever what the owner sees changes.
    private func load(_ url: URL) -> QueueItem? {
        guard let data = Files.read(url), var item = try? JSONDecoder.vaquero.decode(QueueItem.self, from: data) else { return nil }
        var seen = data
        if var change = item.change {
            let current = Files.read(paths.config(change.file))
            change.current = current.map { String(decoding: $0, as: UTF8.self) }
            item.change = change
            seen += current ?? Data()
        }
        item.version = Files.etag(seen)
        item.resolution = nil
        return item
    }

    private func isResolved(_ id: String) -> Bool {
        let months = (try? FileManager.default.contentsOfDirectory(atPath: paths.resolved.path)) ?? []
        return months.contains { FileManager.default.fileExists(atPath: paths.resolved.appending(path: "\($0)/\(id).json").path) }
    }
}

/// Logs, decisions and heartbeats.
struct Records: Sendable {
    let paths: Paths

    /// The newest log entries, newest first.
    func log(limit: Int = 500) -> [LogEntry] {
        var entries: [LogEntry] = []
        for day in Files.list(paths.log, ext: "jsonl").reversed() where entries.count < limit {
            entries += Files.readLines(LogEntry.self, at: day).reversed()
        }
        return Array(entries.prefix(limit))
    }

    /// The newest resolved items, newest answer first.
    func decisions(limit: Int = 500) -> [QueueItem] {
        let months = ((try? FileManager.default.contentsOfDirectory(atPath: paths.resolved.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted(by: >)
        var items: [QueueItem] = []
        for month in months where items.count < limit {
            items += Files.list(paths.resolved.appending(path: month), ext: "json").compactMap { try? Files.readJSON(QueueItem.self, at: $0) }
        }
        let newest = items.sorted { ($0.resolution?.at ?? $0.created) > ($1.resolution?.at ?? $1.created) }
        return Array(newest.prefix(limit))
    }

    func health(days: Int = 7) -> HealthReport {
        let heartbeats = Files.list(paths.health, ext: "json").compactMap { url -> Heartbeat? in
            guard let info = try? Files.readJSON(HeartbeatInfo.self, at: url), let at = Files.modified(url) else { return nil }
            return Heartbeat(component: url.deletingPathExtension().lastPathComponent, at: at, info: info)
        }
        let usage = Files.list(paths.usage, ext: "json").suffix(days).compactMap { url -> UsageDay? in
            guard let day = try? Files.readJSON(UsageFile.self, at: url) else { return nil }
            return UsageDay(date: url.deletingPathExtension().lastPathComponent, tokens: day.tokens, cap: day.cap)
        }
        return HealthReport(heartbeats: heartbeats, usage: usage)
    }

    /// The content of `usage/<date>.json`. The file name gives the date.
    private struct UsageFile: Decodable {
        let tokens: Int
        let cap: Int
    }
}
