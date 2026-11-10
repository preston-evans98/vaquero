import Foundation
import Hummingbird
import ServiceLifecycle
import VaqueroKit

/// Everything the routes need.
struct Services: Sendable {
    let agents: AgentStore
    let queue: QueueStore
    let config: ConfigStore
    let records: Records
    let archive: any Archive
    let feed: ChangeFeed

    init(paths: Paths, supervisor: any Supervisor, archive: any Archive) {
        let config = ConfigStore(paths: paths)
        let agents = AgentStore(paths: paths, supervisor: supervisor, bus: Bus(paths: paths), config: config)
        self.agents = agents
        self.queue = QueueStore(paths: paths, config: config)
        self.config = config
        self.records = Records(paths: paths)
        self.archive = archive
        self.feed = ChangeFeed {
            let specs = agents.specs()
            var prints = paths.watches(for: specs).mapValues(Files.fingerprint)
            // A crash changes no file, so the agents topic also covers each session's state.
            let states = await supervisor.states(of: specs.map(\.name))
            var hasher = Hasher()
            hasher.combine(prints[Change(.agents)])
            for name in states.keys.sorted() {
                hasher.combine(name)
                hasher.combine(states[name]?.state)
                hasher.combine(states[name]?.since)
            }
            prints[Change(.agents)] = hasher.finalize()
            return prints
        }
    }

    /// The services a configuration calls for: fakes in demo mode, the real ones otherwise.
    init(config: ServerConfig) {
        let archive: any Archive =
            if config.demo { FixtureArchive(file: config.paths.root.appending(path: "search.json")) }
            else if let url = config.searchURL { RemoteArchive(url: url) }
            else { MissingArchive() }
        self.init(paths: config.paths, supervisor: config.demo ? FakeSupervisor() : SystemdSupervisor(), archive: archive)
    }
}

func buildRouter(_ services: Services, tokens: Tokens) -> Router<VaqueroContext> {
    let router = Router(context: VaqueroContext.self)
    router.middlewares.add(BearerAuth(tokens: tokens))
    let s = services

    router.register(API.agents) { _, _ in await s.agents.agents() }
    router.register(API.newSession) { session, _ in try await s.agents.open(session) }
    router.register(API.control) { body, call in try await s.agents.control(call[0], body.action) }
    router.register(API.status) { _, call in try s.agents.status(call[0]) }
    router.register(API.conversation) { _, call in try s.agents.conversation(call[0]) }
    router.register(API.message) { body, call in try await s.agents.message(call[0], body.text) }

    router.register(API.queue) { _, _ in s.queue.pending() }
    router.register(API.resolve) { answer, call in try await s.queue.resolve(call[0], answer, by: call.caller.answersAs) }

    router.register(API.log) { _, _ in s.records.log() }
    router.register(API.decisions) { _, _ in s.records.decisions() }
    router.register(API.health) { _, _ in s.records.health() }
    router.register(API.search) { query, _ in try await s.archive.search(query) }

    for file in ConfigFile.allCases {
        router.registerConfig(file.documentType, s.config)
    }

    router.get(RouterPath(API.events)) { _, _ in
        // The stream never ends on its own, so it ends when the server shuts down.
        let frames = await s.feed.subscribe().cancelOnGracefulShutdown().map { event -> ByteBuffer in
            switch event {
            case let .change(change):
                let data = (try? JSONEncoder.compact.encode(change)) ?? Data()
                return ByteBuffer(string: "data: \(String(decoding: data, as: UTF8.self))\n\n")
            case .ping:
                return ByteBuffer(string: ": ping\n\n")
            }
        }
        return Response(
            status: .ok,
            headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
            body: ResponseBody(asyncSequence: frames)
        )
    }
    return router
}

/// The decoded path parameters of a request, in the order the path names them, and its caller.
struct Call: Sendable {
    let parameters: [String]
    let caller: Caller

    subscript(_ index: Int) -> String { parameters[index] }
}

extension Router<VaqueroContext> {
    /// Serves one endpoint from the API table.
    func register<Request, Response: Encodable>(
        _ endpoint: Endpoint<Request, Response>,
        _ handle: @escaping @Sendable (Request, Call) async throws -> Response
    ) {
        let names = endpoint.path.split(separator: "/").filter { $0.hasPrefix(":") }.map { String($0.dropFirst()) }
        on(RouterPath(endpoint.path), method: .init(rawValue: endpoint.verb.rawValue)!) { request, context in
            let body: Request
            if let empty = Empty() as? Request {
                body = empty
            } else {
                let buffer = try await request.body.collect(upTo: 4 << 20)
                do {
                    body = try JSONDecoder.vaquero.decode(Request.self, from: Data(buffer.readableBytesView))
                } catch {
                    throw HTTPError(.badRequest, message: "The request body does not parse: \(error)")
                }
            }
            let parameters = try names.map { name in
                let raw = try context.parameters.require(name)
                let value = raw.removingPercentEncoding ?? raw
                // Each parameter becomes part of a file name, so it must not leave its folder.
                guard !value.isEmpty, !value.hasPrefix("."), !value.contains("/"), !value.contains("\0") else {
                    throw HTTPError(.badRequest, message: "That \(name) is not allowed.")
                }
                return value
            }
            let data = try JSONEncoder.compact.encode(try await handle(body, Call(parameters: parameters, caller: context.caller)))
            return HummingbirdCore.Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(bytes: data))
            )
        }
    }

    func registerConfig<D: ConfigDocument>(_: D.Type, _ store: ConfigStore) {
        register(API.readConfig(D.self)) { _, _ in try await store.read(D.self) }
        register(API.writeConfig(D.self)) { update, _ in try await store.write(update) }
    }
}

/// Who made a request, by the token it carried.
enum Caller: Sendable {
    /// The owner's apps. They may do anything.
    case owner
    /// An agent. It may only open sessions.
    case agent
    /// The Telegram bot. It may only read and answer the queue.
    case bot

    /// How a resolved item records where the owner answered.
    var answersAs: String {
        switch self {
        case .owner: "app"
        case .bot: "telegram"
        case .agent: "agent"
        }
    }

    func may(_ method: HTTPRequest.Method, _ path: String) -> Bool {
        let parts = path.split(separator: "/")
        switch self {
        case .owner:
            return true
        case .agent:
            return method == .post && path == "/" + API.newSession.path
        case .bot:
            return (method == .get && (path == "/" + API.queue.path || path == "/" + API.events))
                || (method == .post && parts.count == 3 && parts[0] == "queue" && parts[2] == "resolve")
        }
    }
}

struct VaqueroContext: RequestContext {
    var coreContext: CoreRequestContextStorage
    var caller = Caller.owner

    init(source: ApplicationRequestContextSource) {
        coreContext = .init(source: source)
    }
}

/// The three tokens the service accepts.
struct Tokens: Sendable {
    let owner: String
    let agent: String
    let bot: String
}

/// Rejects every request without a valid token, and every request its token does not allow.
/// Tailscale is the first gate; this is the second.
struct BearerAuth: RouterMiddleware {
    let tokens: Tokens

    func handle(_ request: Request, context: VaqueroContext, next: (Request, VaqueroContext) async throws -> Response) async throws -> Response {
        let caller: Caller
        switch request.headers[.authorization] {
        case "Bearer \(tokens.owner)": caller = .owner
        case "Bearer \(tokens.agent)": caller = .agent
        case "Bearer \(tokens.bot)": caller = .bot
        default: throw HTTPError(.unauthorized)
        }
        guard caller.may(request.method, request.uri.path) else {
            throw HTTPError(.forbidden, message: "This token cannot do that.")
        }
        var context = context
        context.caller = caller
        return try await next(request, context)
    }
}

extension JSONEncoder {
    /// One-line JSON, for responses and event data.
    static var compact: JSONEncoder {
        let encoder = JSONEncoder.vaquero
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
