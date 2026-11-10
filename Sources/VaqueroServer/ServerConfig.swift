import Foundation

/// How the server runs, from the command line and the environment.
///
/// Normal use reads these variables:
/// - `VAQUERO_ROOT`, `VAQUERO_DRIVE`: the server's folder and the Drive folder
/// - `VAQUERO_TOKEN`, `VAQUERO_AGENT_TOKEN`, `VAQUERO_BOT_TOKEN`: the tokens of the owner, the agents and the Telegram bot
/// - `VAQUERO_TRANSCRIPTS`: the agents' Claude Code transcript folder
/// - optionally `VAQUERO_PORT` and `VAQUERO_SEARCH_URL`
///
/// The server listens on 127.0.0.1 only; `tailscale serve` publishes it to the owner's devices.
///
/// `--demo <folder>` copies a fixture folder to a temporary folder and serves the copy with a
/// fake supervisor, under the tokens "demo", "demo-agent" and "demo-bot".
struct ServerConfig {
    var paths: Paths
    var port = 8080
    var tokens: Tokens
    var demo: Bool
    var searchURL: URL?

    static func load(arguments: [String], environment: [String: String]) throws -> ServerConfig {
        var config: ServerConfig
        if let index = arguments.firstIndex(of: "--demo"), index + 1 < arguments.count {
            config = try demo(fixtures: URL(filePath: arguments[index + 1]))
        } else {
            let required = ["VAQUERO_ROOT", "VAQUERO_DRIVE", "VAQUERO_TOKEN", "VAQUERO_AGENT_TOKEN", "VAQUERO_BOT_TOKEN", "VAQUERO_TRANSCRIPTS"]
            let values = required.compactMap { environment[$0] }
            guard values.count == required.count else {
                throw ConfigError("Set \(required.joined(separator: ", ")), or pass --demo <fixtures>.")
            }
            let root = URL(filePath: values[0])
            config = ServerConfig(
                paths: Paths(
                    root: root,
                    drive: URL(filePath: values[1]),
                    claudeProjects: URL(filePath: values[5]),
                    sessions: root.appending(path: "sessions")
                ),
                tokens: Tokens(owner: values[2], agent: values[3], bot: values[4]),
                demo: false,
                searchURL: environment["VAQUERO_SEARCH_URL"].flatMap(URL.init(string:))
            )
            guard Set([config.tokens.owner, config.tokens.agent, config.tokens.bot]).count == 3 else {
                throw ConfigError("The three tokens must differ.")
            }
        }
        if let port = environment["VAQUERO_PORT"].flatMap(Int.init) { config.port = port }
        return config
    }

    /// Copies the fixtures and marks every file as changed just now, so heartbeats look fresh.
    private static func demo(fixtures: URL) throws -> ServerConfig {
        let manager = FileManager.default
        let copy = manager.temporaryDirectory.appending(path: "vaquero-demo-\(UUID().uuidString.prefix(8))")
        try manager.copyItem(at: fixtures, to: copy)
        let now = Date()
        for case let url as URL in manager.enumerator(at: copy, includingPropertiesForKeys: nil) ?? .init() {
            try? manager.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        }
        return ServerConfig(
            paths: Paths(
                root: copy.appending(path: "root"),
                drive: copy.appending(path: "drive"),
                claudeProjects: copy.appending(path: "claude-projects"),
                sessions: copy.appending(path: "sessions")
            ),
            tokens: Tokens(owner: "demo", agent: "demo-agent", bot: "demo-bot"),
            demo: true
        )
    }

    /// The temporary copy that demo mode serves.
    var demoFolder: URL? { demo ? paths.root.deletingLastPathComponent() : nil }
}

struct ConfigError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
