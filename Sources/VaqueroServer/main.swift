import Foundation
import Hummingbird
import VaqueroKit

let config = try ServerConfig.load(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
let services = Services(config: config)

if let folder = config.demoFolder {
    print("Demo data: \(folder.path)")
    print("Tokens: \(config.tokens.owner) (owner), \(config.tokens.agent) (agents), \(config.tokens.bot) (Telegram bot)")
    fflush(stdout)
}

// The agent launcher reads the tool rules directly, so they must exist before any agent starts.
try await services.config.writeDefault(ToolRules.self)
// After a reboot, bring back every agent the owner has not turned off.
await services.agents.startAll()

let feed = Task { await services.feed.run() }
let app = Application(
    router: buildRouter(services, tokens: config.tokens),
    configuration: .init(address: .hostname("127.0.0.1", port: config.port), serverName: "vaquero")
)
try await app.runService()
feed.cancel()
