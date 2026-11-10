import SwiftUI
import VaqueroKit

/// Every screen in the apps.
enum Destination: String, Hashable, CaseIterable, Identifiable {
    case queue, agents, log, decisions, search
    case lists, routing, priorities, nudges, tools
    case health

    var id: String { rawValue }

    static let work: [Destination] = [.queue, .agents, .log, .decisions, .search]
    static let config: [Destination] = [.lists, .routing, .priorities, .nudges, .tools]

    var title: String {
        switch self {
        case .queue: "Queue"
        case .agents: "Agents"
        case .log: "Log"
        case .decisions: "Decisions"
        case .search: "Search"
        case .lists: ConfigFile.lists.label
        case .routing: ConfigFile.routing.label
        case .priorities: ConfigFile.priorities.label
        case .nudges: ConfigFile.nudges.label
        case .tools: ConfigFile.tools.label
        case .health: "Health"
        }
    }

    var symbol: String {
        switch self {
        case .queue: "tray.full"
        case .agents: "person.3"
        case .log: "list.bullet.rectangle"
        case .decisions: "checkmark.seal"
        case .search: "magnifyingglass"
        case .lists: "eye.slash"
        case .routing: "arrow.triangle.branch"
        case .priorities: "flag"
        case .nudges: "bell.badge"
        case .tools: "wrench.and.screwdriver"
        case .health: "heart.text.square"
        }
    }

    @MainActor @ViewBuilder
    var screen: some View {
        switch self {
        case .queue: QueueScreen()
        case .agents: AgentsScreen()
        case .log: LogScreen()
        case .decisions: DecisionsScreen()
        case .search: SearchScreen()
        case .lists: ChatListsEditor()
        case .routing: RoutingEditor()
        case .priorities: PrioritiesEditor()
        case .nudges: NudgesEditor()
        case .tools: ToolRulesEditor()
        case .health: HealthScreen()
        }
    }

    /// The count to show beside the screen's name, or zero.
    @MainActor
    func badge(_ model: AppModel) -> Int {
        switch self {
        case .queue: model.queue.count
        case .agents: model.troubled.count
        case .health: model.staleHeartbeats.count
        default: 0
        }
    }
}

/// A line about the connection to the server.
struct ConnectionStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.connection {
        case .live where !model.loadErrors.isEmpty:
            Label("Live, but some data failed to load", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .help(model.loadErrors.map { "\($0.key.rawValue): \($0.value)" }.sorted().joined(separator: "\n"))
        case .live: Label("Live", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.green)
        case .connecting: Label("Connecting…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        case .notConfigured: Label("Set up the server in Settings", systemImage: "gearshape").foregroundStyle(.orange)
        case let .offline(reason): Label("Offline", systemImage: "wifi.slash").foregroundStyle(.red).help(reason)
        }
    }
}

/// The server address and token.
public struct SettingsForm: View {
    @Environment(AppModel.self) private var model
    @State private var url = ""
    @State private var token = ""

    public init() {}

    public var body: some View {
        Form {
            SwiftUI.Section {
                TextField("Server", text: $url, prompt: Text("https://vaquero.tailnet.ts.net"))
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                SecureField("Token", text: $token)
            } footer: {
                Text("The token is kept in the Keychain.")
            }
            SwiftUI.Section {
                Button("Connect") { model.connect(ServerSettings(url: url, token: token)) }
                    .disabled(url.isEmpty || token.isEmpty)
                ConnectionStatus()
                if case let .offline(reason) = model.connection {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.loadErrors.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { topic in
                    Text("\(topic.rawValue): \(model.loadErrors[topic] ?? "")").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            url = model.settings.url
            token = model.settings.token
        }
    }
}

extension View {
    /// Shows the model's last failed action as an alert.
    func failureAlert(_ model: AppModel) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.failure ?? "")
        }
    }
}
