import Foundation
import Testing
@testable import VaqueroKit

@Test func endpointFillsParametersInOrder() {
    #expect(API.control.path(["main-business"]) == "agents/main-business/control")
    #expect(API.resolve.path(["a b/c"]) == "queue/a%20b%2Fc/resolve")
    #expect(API.queue.path([]) == "queue")
}

@Test func configEndpointsNameTheirFile() {
    #expect(API.readConfig(ChatLists.self).path == "config/lists")
    #expect(API.writeConfig(Priorities.self).verb == .put)
}

@Test func queueItemRoundTrips() throws {
    let item = QueueItem(
        id: "q1", kind: .draft, created: Date(timeIntervalSince1970: 1_800_000_000), urgency: .urgent,
        lead: "main-business", channel: .whatsapp, chat: "Supplier", sender: "Ana", gist: "Price check",
        draft: "Yes, confirmed.",
        resolution: Resolution(Answer(verdict: .approve, text: "Yes.", version: "v1"), by: "app", at: Date(timeIntervalSince1970: 1_800_000_100))
    )
    let data = try JSONEncoder.vaquero.encode(item)
    #expect(try JSONDecoder.vaquero.decode(QueueItem.self, from: data) == item)
}

@Test func queueOrdersUrgentFirstThenOldest() {
    func item(_ id: String, _ urgency: Urgency, _ seconds: TimeInterval) -> QueueItem {
        QueueItem(id: id, kind: .advice, created: Date(timeIntervalSince1970: seconds), urgency: urgency, lead: "x", gist: "")
    }
    let sorted = [item("low", .low, 0), item("new", .urgent, 20), item("old", .urgent, 10), item("normal", .normal, 0)]
        .sorted(by: QueueItem.ordered)
    #expect(sorted.map(\.id) == ["old", "new", "normal", "low"])
}

@Test func anItemKnowsWhenTheOwnerEdited() {
    var item = QueueItem(id: "q", kind: .draft, created: .now, urgency: .normal, lead: "x", gist: "", draft: "Hi")
    #expect(!item.edited)
    item.resolution = Resolution(Answer(verdict: .approve, text: "Hi", version: "v"), by: "app", at: .now)
    #expect(!item.edited)
    item.resolution?.text = "Hello"
    #expect(item.edited)
}

@Test func prioritiesAreStoredAsPlainMarkdown() throws {
    let rules = Priorities(text: "# Urgent\n- Buyers waiting on a price\n")
    #expect(String(decoding: try rules.fileData(), as: UTF8.self) == rules.text)
    #expect(try Priorities(fileData: rules.fileData()) == rules)
}

@Test func routesAndNudgesKeepNoIdsInTheirFiles() throws {
    let file = #"{"routes": [{"area": "Personal", "lead": "personal", "match": "Family"}]}"#
    let map = try RoutingMap(fileData: Data(file.utf8))
    #expect(map.routes.first?.area == "Personal")
    #expect(ConfigFile.routing.canonical(file) == ConfigFile.routing.canonical(file))
    #expect(ConfigFile.routing.canonical(file)?.contains("\"id\"") == false)
    let plan = try NudgePlan(fileData: Data(#"{"stallDays": 3, "nudges": [{"lead": "x", "goal": "y", "everyHours": 24}]}"#.utf8))
    #expect(plan.nudges.first?.tellOwnerAfterDays == nil)
}

@Test func heartbeatGoesStaleAfterItsLimit() {
    let beat = Heartbeat(component: "watcher", at: Date(timeIntervalSince1970: 0), info: HeartbeatInfo(machine: "server", staleAfter: 120))
    #expect(!beat.isStale(now: Date(timeIntervalSince1970: 100)))
    #expect(beat.isStale(now: Date(timeIntervalSince1970: 121)))
}

@Test func diffShowsRemovedLinesBeforeTheirReplacements() {
    let lines = DiffLine.lines(from: "a\nb\nc", to: "a\nB\nc\nd")
    #expect(lines == [.same("a"), .removed("b"), .added("B"), .same("c"), .added("d")])
    #expect(DiffLine.lines(from: "", to: "x") == [.removed(""), .added("x")])
}

@Test func timelineInterleavesTranscriptAndMail() {
    let entry = TranscriptEntry(id: "e", at: Date(timeIntervalSince1970: 20), speaker: .assistant, text: "Done.")
    let mail = BusMessage(id: "m", from: "owner", to: "x", at: Date(timeIntervalSince1970: 10), text: "Do it.")
    let later = BusMessage(id: "n", from: "owner", to: "x", at: Date(timeIntervalSince1970: 30), text: "Thanks.")
    let timeline = Conversation(entries: [entry], read: [mail], unread: [later]).timeline
    #expect(timeline.map(\.id) == ["message-m", "entry-e", "message-n"])
}

@Test func canonicalFormMakesFormattingInvisible() {
    let compact = #"{"stallDays":3,"nudges":[{"id":"a","lead":"x","goal":"y","everyHours":24}]}"#
    let spaced = "{\n  \"nudges\" : [ { \"everyHours\" : 24, \"goal\" : \"y\", \"id\" : \"a\", \"lead\" : \"x\" } ],\n  \"stallDays\" : 3\n}"
    #expect(ConfigFile.nudges.canonical(compact) == ConfigFile.nudges.canonical(spaced))
    #expect(ConfigFile.nudges.canonical("{") == nil)
    #expect(ConfigFile.priorities.canonical("# Rules") == "# Rules")
}

@Test func chatListsRejectAChatOnTwoLists() {
    let rule = ChatRule(channel: .telegram, chat: "mom", title: "Mom", list: .continuous, strictness: .strict)
    var twin = rule
    twin.list = .blocked
    #expect(ChatLists(chats: [rule]).problem == nil)
    #expect(ChatLists(chats: [rule, twin]).problem != nil)
}

@Test func onlySomeFilesAcceptProposals() {
    #expect(ConfigFile.allCases.filter(\.acceptsProposals) == [.routing, .nudges, .priorities])
}

@Test func agentNamesStayInsideTheirFolder() {
    #expect(AgentSpec.isValidName("main-business"))
    #expect(!AgentSpec.isValidName("../queue"))
    #expect(!AgentSpec.isValidName("Main"))
    #expect(!AgentSpec.isValidName(""))
}
