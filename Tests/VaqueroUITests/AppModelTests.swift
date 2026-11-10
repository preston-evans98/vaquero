import Foundation
import Hummingbird
import HummingbirdTesting
import Testing
import VaqueroKit
@testable import VaqueroServer
@testable import VaqueroUI

/// Runs a demo server on a free port, with its change feed, and hands the test its address.
private func withDemoServer(_ test: @MainActor @Sendable (String) async throws -> Void) async throws {
    let fixtures = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Fixtures/demo").standardized
    let config = try ServerConfig.load(arguments: ["--demo", fixtures.path], environment: [:])
    defer { try? FileManager.default.removeItem(at: config.demoFolder!) }
    let services = Services(config: config)
    let feed = Task { await services.feed.run() }
    defer { feed.cancel() }
    let app = Application(router: buildRouter(services, tokens: config.tokens))
    try await app.test(.live) { client in
        try await test("http://localhost:\(try #require(client.port))")
    }
}

/// Waits up to five seconds for a condition.
@MainActor
private func eventually(_ condition: () -> Bool) async throws {
    for _ in 0..<50 where !condition() {
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(condition())
}

@MainActor @Test func modelLoadsEverythingAndAnswersTheQueue() async throws {
    try await withDemoServer { url in
        let model = AppModel(settings: ServerSettings(url: url, token: "demo"))
        model.connect()
        try await eventually { model.queue.count == 5 && model.agents.count == 6 && model.health != nil && model.decisions.count == 3 }
        #expect(model.connection == .live)
        #expect(model.loadErrors.isEmpty)

        let kemal = try #require(model.queue.first { $0.id == "q-1110-kemal" })
        await model.resolve(kemal, .approve, text: "Confirmed.")
        #expect(model.failure == nil)
        try await eventually { model.decisions.first?.id == "q-1110-kemal" && model.queue.count == 4 }
    }
}

@MainActor @Test func modelReportsAnAnswerToAChangedItem() async throws {
    try await withDemoServer { url in
        let model = AppModel(settings: ServerSettings(url: url, token: "demo"))
        model.connect()
        try await eventually { !model.queue.isEmpty }
        var item = try #require(model.queue.first)
        item.version = "old"
        await model.resolve(item, .approve)
        #expect(model.failure == "This item changed since you saw it.")
        try await eventually { model.queue.contains { $0.id == item.id } }
    }
}

@MainActor @Test func modelGoesOfflineWithAWrongToken() async throws {
    try await withDemoServer { url in
        let model = AppModel(settings: ServerSettings(url: url, token: "wrong"))
        model.connect()
        try await eventually {
            if case .offline = model.connection { true } else { false }
        }
        #expect(model.queue.isEmpty)
    }
}
