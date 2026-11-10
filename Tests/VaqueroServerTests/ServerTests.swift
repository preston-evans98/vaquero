import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
import VaqueroKit
@testable import VaqueroServer

/// A server on a fresh copy of the demo fixtures. The copy goes away with the harness.
final class Harness: Sendable {
    let config: ServerConfig
    let supervisor: FakeSupervisor
    let services: Services

    init(stopped: [String] = [], failing: Set<String> = []) throws {
        let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Fixtures/demo").standardized
        config = try ServerConfig.load(arguments: ["--demo", fixtures.path], environment: [:])
        supervisor = FakeSupervisor(stopped: stopped, failing: failing)
        services = Services(
            paths: config.paths, supervisor: supervisor,
            archive: FixtureArchive(file: config.paths.root.appending(path: "search.json"))
        )
    }

    deinit {
        if let folder = config.demoFolder { try? FileManager.default.removeItem(at: folder) }
    }

    var paths: Paths { config.paths }

    func run(_ test: @Sendable (Caller) async throws -> Void) async throws {
        let app = Application(router: buildRouter(services, tokens: config.tokens))
        try await app.test(.router) { client in try await test(Caller(client: client, token: config.tokens.owner)) }
    }

    /// Runs a real server on a free port, for tests that go through `Client` and URLSession.
    func live(_ test: @Sendable (Client) async throws -> Void) async throws {
        let app = Application(router: buildRouter(services, tokens: config.tokens))
        try await app.test(.live) { client in
            let port = try #require(client.port)
            try await test(Client(baseURL: URL(string: "http://localhost:\(port)")!, token: config.tokens.owner))
        }
    }

    /// Adds a pending item, as the chief of staff or the sorter would.
    func addPending(_ item: QueueItem) throws {
        try Files.writeJSON(item, to: paths.pending(item.id))
    }
}

/// Calls endpoints from the API table, as the apps do.
struct Caller {
    let client: any TestClientProtocol
    let token: String

    func call<Response>(
        _ endpoint: Endpoint<Empty, Response>, _ parameters: String..., token: String? = nil
    ) async throws -> (HTTPResponse.Status, Response?) {
        try await call(endpoint, parameters, body: Empty(), token: token)
    }

    func call<Request, Response>(
        _ endpoint: Endpoint<Request, Response>, _ parameters: String..., body: Request, token: String? = nil
    ) async throws -> (HTTPResponse.Status, Response?) {
        try await call(endpoint, parameters, body: body, token: token)
    }

    /// Answers a pending item at the version the queue shows now.
    func answer(_ id: String, _ verdict: Verdict, text: String? = nil) async throws -> (HTTPResponse.Status, QueueItem?) {
        let item = try await pending(id)
        return try await call(API.resolve, id, body: Answer(verdict: verdict, text: text, version: item.version ?? ""))
    }

    func pending(_ id: String) async throws -> QueueItem {
        let (_, queue) = try await call(API.queue)
        return try #require(queue?.first { $0.id == id })
    }

    private func call<Request, Response>(
        _ endpoint: Endpoint<Request, Response>, _ parameters: [String], body: Request, token: String?
    ) async throws -> (HTTPResponse.Status, Response?) {
        let payload = Request.self == Empty.self ? nil : ByteBuffer(bytes: try JSONEncoder.vaquero.encode(body))
        return try await client.execute(
            uri: "/" + endpoint.path(parameters),
            method: .init(rawValue: endpoint.verb.rawValue)!,
            headers: [.authorization: "Bearer \(token ?? self.token)"],
            body: payload
        ) { response in
            let value = response.status == .ok ? try JSONDecoder.vaquero.decode(Response.self, from: Data(response.body.readableBytesView)) : nil
            return (response.status, value)
        }
    }
}

// MARK: Tokens

@Test func requestsNeedAToken() async throws {
    try await Harness().run { caller in
        let (denied, _) = try await caller.call(API.agents, token: "wrong")
        #expect(denied == .unauthorized)
        let (status, agents) = try await caller.call(API.agents)
        #expect(status == .ok)
        #expect(agents?.count == 6)
        #expect(agents?.first { $0.id == "main-business" }?.unread == 1)
    }
}

@Test func theAgentTokenOnlyOpensSessions() async throws {
    try await Harness().run { caller in
        let (queue, _) = try await caller.call(API.queue, token: "demo-agent")
        #expect(queue == .forbidden)
        let (resolve, _) = try await caller.call(API.resolve, "q-1110-kemal", body: Answer(verdict: .approve, version: ""), token: "demo-agent")
        #expect(resolve == .forbidden)
        let session = NewSession(name: "freight", parent: "main-business", model: "opus", brief: "Find a slot.", fork: false)
        let (opened, _) = try await caller.call(API.newSession, body: session, token: "demo-agent")
        #expect(opened == .ok)
    }
}

@Test func theBotTokenOnlyAnswersTheQueue() async throws {
    try await Harness().run { caller in
        let (queue, _) = try await caller.call(API.queue, token: "demo-bot")
        #expect(queue == .ok)
        let (agents, _) = try await caller.call(API.agents, token: "demo-bot")
        #expect(agents == .forbidden)
        let (config, _) = try await caller.call(API.readConfig(ChatLists.self), token: "demo-bot")
        #expect(config == .forbidden)
        let item = try await caller.pending("q-1110-dentist")
        let (status, answered) = try await caller.call(API.resolve, "q-1110-dentist", body: Answer(verdict: .approve, version: item.version ?? ""), token: "demo-bot")
        #expect(status == .ok)
        #expect(answered?.resolution?.by == "telegram")
    }
}

@Test func namesCannotLeaveTheirFolders() async throws {
    let harness = try Harness()
    try harness.addPending(QueueItem(id: "x", kind: .advice, created: .now, urgency: .low, lead: "personal", gist: "Decoy"))
    try await harness.run { caller in
        let (status, _) = try await caller.call(API.status, "..%2Fqueue%2Fpending%2Fx")
        #expect(status == .badRequest)
        let (dotted, _) = try await caller.call(API.conversation, "..")
        #expect(dotted == .badRequest)
        let session = NewSession(name: "sneaky", parent: "../queue/pending/x", model: "opus", brief: "x", fork: false)
        let (opened, _) = try await caller.call(API.newSession, body: session, token: "demo-agent")
        #expect(opened == .notFound)
        let (resolve, _) = try await caller.call(API.resolve, "..%2Fpending%2Fx", body: Answer(verdict: .ignore, version: ""))
        #expect(resolve == .badRequest)
    }
}

// MARK: Queue

@Test func resolvingWritesTheAnsweredItemOnce() async throws {
    let harness = try Harness()
    try await harness.run { caller in
        let (status, item) = try await caller.answer("q-1110-kemal", .approve, text: "Confirmed, thanks Kemal.")
        #expect(status == .ok)
        #expect(item?.resolution?.text == "Confirmed, thanks Kemal.")
        #expect(!FileManager.default.fileExists(atPath: harness.paths.pending("q-1110-kemal").path))
        let stored = try Files.readJSON(QueueItem.self, at: harness.paths.resolved.appending(path: "2026-11/q-1110-kemal.json"))
        #expect(stored.resolution?.verdict == .approve)

        let (_, decisions) = try await caller.call(API.decisions)
        #expect(decisions?.first?.id == "q-1110-kemal")
        #expect(decisions?.first?.edited == true)
        #expect(decisions?.count == 4)

        #expect(item?.resolution?.by == "app")
        let late = Answer(verdict: .ignore, version: item?.version ?? "")
        let (again, _) = try await caller.call(API.resolve, "q-1110-kemal", body: late)
        #expect(again == .conflict)
        let (missing, _) = try await caller.call(API.resolve, "nope", body: late)
        #expect(missing == .notFound)
    }
}

@Test func anAnswerToAnOlderVersionFails() async throws {
    let harness = try Harness()
    try await harness.run { caller in
        let stale = Answer(verdict: .approve, version: "old")
        let (status, _) = try await caller.call(API.resolve, "q-1110-kemal", body: stale)
        #expect(status == .conflict)
        #expect(FileManager.default.fileExists(atPath: harness.paths.pending("q-1110-kemal").path))
    }
}

@Test func whenTwoAnswersRaceOnlyOneWins() async throws {
    let harness = try Harness()
    let queue = harness.services.queue
    let version = try #require(queue.pending().first { $0.id == "q-1110-dentist" }?.version)
    let outcomes = await withTaskGroup(of: Bool.self) { group in
        for by in ["app", "telegram", "app", "telegram"] {
            group.addTask {
                (try? await queue.resolve("q-1110-dentist", Answer(verdict: .approve, version: version), by: by)) != nil
            }
        }
        return await group.reduce(into: [Bool]()) { $0.append($1) }
    }
    #expect(outcomes.filter { $0 }.count == 1)
}

@Test func aPendingCopyOfAResolvedItemStaysHidden() throws {
    let harness = try Harness()
    let resolved = try Files.readJSON(QueueItem.self, at: harness.paths.resolved.appending(path: "2026-11/q-1108-rhein.json"))
    var copy = resolved
    copy.resolution = nil
    try harness.addPending(copy)
    #expect(!harness.services.queue.pending().contains { $0.id == "q-1108-rhein" })
}

// MARK: Proposed config changes

@Test func approvingAConfigChangeWritesTheFile() async throws {
    try await Harness().run { caller in
        let item = try await caller.pending("q-1110-nudge")
        #expect(item.change?.current?.contains("German market") == true)
        let (status, _) = try await caller.answer("q-1110-nudge", .approve)
        #expect(status == .ok)
        let (_, plan) = try await caller.call(API.readConfig(NudgePlan.self))
        #expect(plan?.value.nudges.map(\.lead) == ["main-business", "investments"])
    }
}

@Test func aConfigChangeNeedsAFreshLookAfterTheFileChanges() async throws {
    let harness = try Harness()
    try await harness.run { caller in
        let seen = try await caller.pending("q-1110-nudge")
        let (_, plan) = try await caller.call(API.readConfig(NudgePlan.self))
        var update = try #require(plan)
        update.value.stallDays = 5
        let (written, _) = try await caller.call(API.writeConfig(NudgePlan.self), body: update)
        #expect(written == .ok)

        let (status, _) = try await caller.call(API.resolve, "q-1110-nudge", body: Answer(verdict: .approve, version: seen.version ?? ""))
        #expect(status == .conflict)
        #expect(try await caller.pending("q-1110-nudge").version != seen.version)
    }
}

@Test func proposalsCannotTouchTheChatListsOrTheToolRules() async throws {
    let harness = try Harness()
    try harness.addPending(QueueItem(
        id: "q-lists", kind: .configChange, created: .now, urgency: .low, lead: "chief-of-staff", gist: "Unblock a chat",
        change: ConfigChange(file: .lists, content: #"{"chats":[]}"#)
    ))
    try harness.addPending(QueueItem(
        id: "q-tools", kind: .configChange, created: .now, urgency: .low, lead: "chief-of-staff", gist: "Allow Bash",
        change: ConfigChange(file: .tools, content: #"{"allow":["Bash"],"deny":[]}"#)
    ))
    try await harness.run { caller in
        for id in ["q-lists", "q-tools"] {
            let (status, _) = try await caller.answer(id, .approve)
            #expect(status == .forbidden)
            #expect(FileManager.default.fileExists(atPath: harness.paths.pending(id).path))
        }
    }
}

@Test func anUnparseableProposalIsRejected() async throws {
    let harness = try Harness()
    try harness.addPending(QueueItem(
        id: "q-broken", kind: .configChange, created: .now, urgency: .low, lead: "chief-of-staff", gist: "Broken",
        change: ConfigChange(file: .nudges, content: "not json")
    ))
    try await harness.run { caller in
        let (status, _) = try await caller.answer("q-broken", .approve)
        #expect(status == .unprocessableContent)
        let (ignored, _) = try await caller.answer("q-broken", .ignore)
        #expect(ignored == .ok)
    }
}

@Test func filesTheServiceWritesAreNotGroupWritable() async throws {
    let harness = try Harness()
    func mode(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }
    // Start from folders the service has to create itself.
    let month = harness.paths.resolved.appending(path: "2026-11")
    let inbox = harness.paths.inbox("personal")
    try FileManager.default.removeItem(at: month)
    try? FileManager.default.removeItem(at: inbox)
    try await harness.run { caller in
        _ = try await caller.answer("q-1110-kemal", .approve)
        _ = try await caller.call(API.message, "personal", body: OwnerMessage(text: "Hello."))
    }
    #expect(try mode(month) == 0o755)
    #expect(try mode(month.appending(path: "q-1110-kemal.json")) == 0o644)
    // Agents move mail out of the inbox and write mail into it, so it is shared.
    #expect(try mode(inbox) == 0o2775)
    #expect(try mode(try #require(Files.list(inbox).first)) == 0o644)
}

// MARK: Config files

@Test func configWritesNeedTheCurrentVersion() async throws {
    try await Harness().run { caller in
        let (_, lists) = try await caller.call(API.readConfig(ChatLists.self))
        var update = try #require(lists)
        update.value.chats.removeLast()
        let (status, saved) = try await caller.call(API.writeConfig(ChatLists.self), body: update)
        #expect(status == .ok)
        #expect(saved?.value.chats.count == update.value.chats.count)
        #expect(saved?.etag != update.etag)

        let (stale, _) = try await caller.call(API.writeConfig(ChatLists.self), body: update)
        #expect(stale == .conflict)
    }
}

@Test func aChatCanSitOnOnlyOneList() async throws {
    try await Harness().run { caller in
        let (_, lists) = try await caller.call(API.readConfig(ChatLists.self))
        var update = try #require(lists)
        var twin = try #require(update.value.chats.first)
        twin.list = .blocked
        update.value.chats.append(twin)
        let (status, _) = try await caller.call(API.writeConfig(ChatLists.self), body: update)
        #expect(status == .unprocessableContent)
    }
}

@Test func theServerWritesDefaultToolRules() async throws {
    let harness = try Harness()
    let url = harness.paths.config(.tools)
    try FileManager.default.removeItem(at: url)
    try await harness.services.config.writeDefault(ToolRules.self)
    #expect(try ToolRules(fileData: Data(contentsOf: url)) == ToolRules.empty)
}

@Test func priorityRulesRoundTripAsMarkdown() async throws {
    let harness = try Harness()
    try await harness.run { caller in
        let (_, rules) = try await caller.call(API.readConfig(Priorities.self))
        var update = try #require(rules)
        update.value.text += "\n- Tax deadlines are always urgent.\n"
        let (status, _) = try await caller.call(API.writeConfig(Priorities.self), body: update)
        #expect(status == .ok)
        let file = String(decoding: try Data(contentsOf: harness.paths.config(.priorities)), as: UTF8.self)
        #expect(file.hasSuffix("- Tax deadlines are always urgent.\n"))
    }
}

@Test func aHandWrittenOrBrokenNudgesFileKeepsAgentsWorking() async throws {
    let harness = try Harness()
    let nudges = harness.paths.config(.nudges)
    try Data(#"{"stallDays": 2, "nudges": [{"lead": "investments", "goal": "Next hypothesis", "everyHours": 24}]}"#.utf8).write(to: nudges)
    try await harness.run { caller in
        let (_, plan) = try await caller.call(API.readConfig(NudgePlan.self))
        #expect(plan?.value.nudges.map(\.lead) == ["investments"])
        try Data("{".utf8).write(to: nudges)
        let (status, _) = try await caller.call(API.agents)
        #expect(status == .ok)
        let (broken, _) = try await caller.call(API.readConfig(NudgePlan.self))
        #expect(broken == .unprocessableContent)
    }
}

// MARK: Agents

@Test func messagesLandInTheInboxAndWakeAStoppedAgent() async throws {
    let harness = try Harness(stopped: ["real-estate"])
    try await harness.run { caller in
        let (status, message) = try await caller.call(API.message, "real-estate", body: OwnerMessage(text: "Hold at €400k."))
        #expect(status == .ok)
        let (_, conversation) = try await caller.call(API.conversation, "real-estate")
        #expect(conversation?.unread.map(\.text) == ["Hold at €400k."])
        #expect(conversation?.unread.first?.id == message?.id)
        let (_, agents) = try await caller.call(API.agents)
        #expect(agents?.first { $0.id == "real-estate" }?.state == .running)
    }
}

@Test func conversationReadsTheTranscriptWithoutDoorbellPrompts() async throws {
    try await Harness().run { caller in
        let (_, conversation) = try await caller.call(API.conversation, "main-business")
        let entries = try #require(conversation?.entries)
        #expect(!entries.contains { $0.text == Transcript.doorbellPrompt })
        #expect(entries.contains { $0.speaker == .tool && $0.text == "Read" })
        #expect(entries.last?.text.hasPrefix("Lena says") == true)
        #expect(entries.allSatisfy { $0.at != nil })
        let (_, chief) = try await caller.call(API.conversation, "chief-of-staff")
        #expect(chief?.read.first?.from == "owner")
    }
}

@Test func leadsStallWhenStatusGoesQuiet() async throws {
    let harness = try Harness()
    let status = harness.paths.drive.appending(path: "areas/investments/status.md")
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -4 * 86_400)], ofItemAtPath: status.path)
    try await harness.run { caller in
        let (_, agents) = try await caller.call(API.agents)
        #expect(agents?.filter(\.stalled).map(\.id) == ["investments"])
    }
}

@Test func stoppedAgentsStayStoppedAfterARestart() async throws {
    let harness = try Harness()
    try await harness.run { caller in
        let (_, stopped) = try await caller.call(API.control, "personal", body: AgentControl(action: .stop))
        #expect(stopped?.state == .stopped)
        #expect(stopped?.spec.off == true)
        let (missing, _) = try await caller.call(API.control, "ghost", body: AgentControl(action: .start))
        #expect(missing == .notFound)
    }
    await harness.services.agents.startAll()
    #expect(await harness.supervisor.states(of: ["personal"])["personal"]?.state == .stopped)
}

@Test func aSessionThatFailsToStartLeavesNothingBehind() async throws {
    let harness = try Harness(failing: ["freight"])
    try await harness.run { caller in
        let session = NewSession(name: "freight", parent: "main-business", model: "opus", brief: "Find a slot.", fork: false)
        let (status, _) = try await caller.call(API.newSession, body: session)
        #expect(status == .internalServerError)
        #expect(!FileManager.default.fileExists(atPath: harness.paths.agent("freight").path))
        #expect(Files.list(harness.paths.inbox("freight")).isEmpty)
    }
}

@Test func startupBringsBackAgentsTheOwnerLeftOn() async throws {
    let harness = try Harness(stopped: ["investments"])
    await harness.services.agents.startAll()
    #expect(await harness.supervisor.states(of: ["investments"])["investments"]?.state == .running)
}

@Test func sessionsOpenUnderTheRightParent() async throws {
    let harness = try Harness()
    try await harness.run { caller in
        let project = NewSession(name: "freight", parent: "main-business", model: "opus", brief: "Find a December slot.", fork: true)
        let (status, agent) = try await caller.call(API.newSession, body: project)
        #expect(status == .ok)
        #expect(agent?.spec.role == .project)
        #expect(agent?.spec.forkOf == "main-business")
        #expect(agent?.spec.statusFile == "areas/main-business/projects/freight.md")
        #expect(agent?.unread == 1)

        let lead = NewSession(name: "ventures", parent: "chief-of-staff", model: "sonnet", brief: "New ventures.", fork: false)
        let (_, opened) = try await caller.call(API.newSession, body: lead)
        #expect(opened?.spec.role == .lead)
        #expect(opened?.spec.statusFile == "areas/ventures/status.md")

        for (session, expected) in [
            (project, HTTPResponse.Status.conflict),
            (NewSession(name: "nested", parent: "export-prices", model: "opus", brief: "x", fork: false), .badRequest),
            (NewSession(name: "evil", parent: "main-business", model: "opus; curl x|sh", brief: "x", fork: false), .badRequest),
            (NewSession(name: "Bad Name", parent: "main-business", model: "opus", brief: "x", fork: false), .badRequest),
        ] {
            let (status, _) = try await caller.call(API.newSession, body: session)
            #expect(status == expected)
        }
    }
}

// MARK: Records

@Test func healthReadsHeartbeatsAndUsage() async throws {
    try await Harness().run { caller in
        let (_, report) = try await caller.call(API.health)
        #expect(report?.heartbeats.count == 5)
        #expect(report?.heartbeats.allSatisfy { !$0.isStale() } == true)
        #expect(report?.usage.map(\.date).last == "2026-11-10")
    }
}

@Test func logIsNewestFirst() async throws {
    try await Harness().run { caller in
        let (_, log) = try await caller.call(API.log)
        #expect(log?.count == 10)
        #expect(log?.first?.sender == "Paulo Reis")
    }
}

@Test func searchFindsKeywordsAndNothingElse() async throws {
    try await Harness().run { caller in
        let (_, hits) = try await caller.call(API.search, body: SearchQuery(text: "visa consulate"))
        #expect(hits?.isEmpty == false)
        let (_, none) = try await caller.call(API.search, body: SearchQuery(text: "zebra"))
        #expect(none?.isEmpty == true)
    }
}

// MARK: Change feed

@Test func feedStartsWithEveryTopicThenAnnouncesChanges() async throws {
    let harness = try Harness()
    let feed = harness.services.feed
    await feed.tick()
    var events = await feed.subscribe().makeAsyncIterator()
    var first: Set<Change> = []
    // Every topic except conversations, plus one conversation per agent.
    for _ in 0..<(Topic.allCases.count - 1 + 6) {
        if case let .change(change)? = await events.next() { first.insert(change) }
    }
    #expect(first.contains(Change(.queue)))
    #expect(first.contains(Change(.conversation, key: "main-business")))

    try Files.write(Data("x".utf8), to: harness.paths.health.appending(path: "new.json"))
    await feed.tick()
    guard case let .change(change)? = await events.next() else {
        Issue.record("No change announced")
        return
    }
    #expect(change == Change(.health))
}

@Test func feedAnnouncesACrashedAgent() async throws {
    let harness = try Harness()
    let feed = harness.services.feed
    await feed.tick()
    var events = await feed.subscribe().makeAsyncIterator()
    for _ in 0..<(Topic.allCases.count - 1 + 6) { _ = await events.next() }
    try await harness.supervisor.perform(.stop, on: "personal")
    await feed.tick()
    guard case let .change(change)? = await events.next() else {
        Issue.record("No change announced")
        return
    }
    #expect(change == Change(.agents))
}

@Test func feedForgetsSubscribersThatLeave() async throws {
    let feed = try Harness().services.feed
    let listener = Task {
        for await _ in await feed.subscribe() {}
    }
    try await Task.sleep(for: .milliseconds(100))
    #expect(await feed.subscriberCount == 1)
    listener.cancel()
    for _ in 0..<50 where await feed.subscriberCount > 0 {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(await feed.subscriberCount == 0)
}

// MARK: Through the real client

@Test func theClientReachesItemsWithAnyId() async throws {
    let harness = try Harness()
    let id = "q 1110 Kölle"
    try harness.addPending(QueueItem(id: id, kind: .advice, created: .now, urgency: .normal, lead: "personal", gist: "Odd id"))
    try await harness.live { client in
        let item = try #require(try await client.get(API.queue).first { $0.id == id })
        let answered = try await client.send(API.resolve, id, body: Answer(verdict: .ignore, version: item.version ?? ""))
        #expect(answered.id == id)
        await #expect(throws: ClientError.self) { try await client.get(API.status, "ghost") }
    }
}

@Test func theClientHearsEveryTopicOnConnecting() async throws {
    let harness = try Harness()
    try await harness.live { client in
        var topics: Set<Topic> = []
        for try await change in client.changes() {
            topics.insert(change.topic)
            if topics.count == Topic.allCases.count { break }
        }
        #expect(topics == Set(Topic.allCases))
        let denied = Client(baseURL: client.baseURL, token: "wrong")
        await #expect(throws: ClientError.self) {
            for try await _ in denied.changes() {}
        }
    }
}

// MARK: Pieces

@Test func busMessagesRoundTrip() {
    let message = BusMessage(id: "id", from: "owner", to: "personal", at: Date(timeIntervalSince1970: 1_800_000_000), text: "Line one.\n\nLine two.")
    #expect(Bus.parse(Bus.render(message), id: "id", to: "personal", modified: .now) == message)
}

@Test func handWrittenMailStillShows() throws {
    let modified = Date(timeIntervalSince1970: 1_800_000_000)
    let bare = Bus.parse("Call the notary.\n", id: "n", to: "real-estate", modified: modified)
    #expect(bare.from == "unknown")
    #expect(bare.at == modified)
    #expect(bare.text == "Call the notary.")
    let precise = Bus.parse("From: personal\nAt: 2026-11-10T09:00:00.250Z\n\nHi.", id: "p", to: "x", modified: modified)
    #expect(precise.from == "personal")
    #expect(precise.at != modified)
}

@Test func transcriptsSkipSubAgentsAndDoorbellBlocks() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "transcripts-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let main = """
    {"type":"user","uuid":"a","timestamp":"2026-11-10T09:00:00.000Z","message":{"role":"user","content":[{"type":"text","text":"\(Transcript.doorbellPrompt)"}]}}
    {"type":"assistant","uuid":"b","timestamp":"2026-11-10T09:00:05.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Reading my inbox."}]}}
    """
    try Data(main.utf8).write(to: folder.appending(path: "s1.jsonl"))
    try Data(#"{"type":"assistant","uuid":"c","message":{"content":"I am a worker."}}"#.utf8).write(to: folder.appending(path: "agent-1.jsonl"))
    #expect(Transcript.recent(in: folder).map(\.text) == ["Reading my inbox."])
}

@Test func systemdOutputParsesPerUnit() throws {
    let output = """
    Id=vaquero-agent@main-business.service
    ActiveState=active
    SubState=running
    StateChangeTimestamp=Tue 2026-11-10 09:12:00 UTC

    Id=vaquero-agent@personal.service
    ActiveState=failed
    SubState=failed
    StateChangeTimestamp=

    Id=vaquero-agent@looping.service
    ActiveState=activating
    SubState=auto-restart
    StateChangeTimestamp=

    Id=vaquero-agent@booting.service
    ActiveState=activating
    SubState=start
    StateChangeTimestamp=

    Id=other.service
    ActiveState=active
    """
    let states = SystemdSupervisor.parse(output)
    #expect(states.keys.sorted() == ["booting", "looping", "main-business", "personal"])
    #expect(states["looping"]?.state == .failed)
    #expect(states["booting"]?.state == .starting)
    #expect(states["main-business"]?.state == .running)
    #expect(states["main-business"]?.since == (try Date("2026-11-10T09:12:00Z", strategy: .iso8601)))
    #expect(states["personal"]?.state == .failed)
    #expect(states["personal"]?.since == nil)
}
