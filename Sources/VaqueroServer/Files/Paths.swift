import Foundation
import VaqueroKit

/// Where every file lives. This is the only place in the server that knows the layout.
/// Callers check names before they build paths: `AgentSpec.isValidName` for agents, and the
/// router's check of every path parameter for the rest.
struct Paths: Sendable {
    /// Server-only state, including the owner's config.
    let root: URL
    /// The lasting record, synced with Google Drive. The service only reads it.
    let drive: URL
    /// Where Claude Code keeps the agents' session transcripts.
    let claudeProjects: URL
    /// Working directories for new sessions.
    let sessions: URL

    var agents: URL { root.appending(path: "agents") }
    func agent(_ name: String) -> URL { agents.appending(path: "\(name).json") }

    func inbox(_ name: String) -> URL { root.appending(path: "bus/\(name)/inbox") }
    func done(_ name: String) -> URL { root.appending(path: "bus/\(name)/done") }

    var pending: URL { root.appending(path: "queue/pending") }
    func pending(_ id: String) -> URL { pending.appending(path: "\(id).json") }

    /// Resolved items sit in one folder per month of their creation, so a decision's path
    /// depends only on the item and two answers to the same item race for the same name.
    var resolved: URL { root.appending(path: "queue/resolved") }
    func resolved(_ item: QueueItem) -> URL {
        let month = item.created.formatted(.iso8601.year().month().dateSeparator(.dash))
        return resolved.appending(path: "\(month)/\(item.id).json")
    }

    var log: URL { root.appending(path: "log") }
    var health: URL { root.appending(path: "health") }
    var usage: URL { root.appending(path: "usage") }

    /// The owner's config sits on the server, where agents cannot change it, even through a Drive
    /// connector. Agents may read `config/`. Only the service reads `private/`, which holds the chat lists.
    func config(_ file: ConfigFile) -> URL {
        switch file {
        case .lists: root.appending(path: "private/lists.json")
        case .routing: root.appending(path: "config/routing.json")
        case .nudges: root.appending(path: "config/nudges.json")
        case .priorities: root.appending(path: "config/priorities.md")
        case .tools: root.appending(path: "config/tools.json")
        }
    }

    func status(_ spec: AgentSpec) -> URL { drive.appending(path: spec.statusFile) }

    func transcripts(_ spec: AgentSpec) -> URL { Transcript.folder(for: spec.workdir, in: claudeProjects) }

    /// The files each topic depends on. A change to any of them announces the topic.
    func watches(for specs: [AgentSpec]) -> [Change: [URL]] {
        var watches: [Change: [URL]] = [
            Change(.agents): [agents] + specs.flatMap { [status($0), inbox($0.name)] },
            // Config changes alter how a proposed change reads, so they touch the queue too.
            Change(.queue): [pending] + ConfigFile.allCases.map(config),
            Change(.log): [log],
            Change(.decisions): [resolved],
            Change(.health): [health, usage],
            Change(.config): ConfigFile.allCases.map(config),
        ]
        for spec in specs {
            watches[Change(.conversation, key: spec.name)] = [transcripts(spec), inbox(spec.name), done(spec.name)]
        }
        return watches
    }
}
