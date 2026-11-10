import MarkdownUI
import SwiftUI
import VaqueroKit

/// One agent: its state and controls, then its chat, status file and decisions.
struct AgentDetail: View {
    @Environment(AppModel.self) private var model
    let agent: Agent
    @State private var tab = Tab.chat
    @State private var opening = false

    enum Tab: String, CaseIterable {
        case chat = "Chat"
        case status = "Status"
        case decisions = "Decisions"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            Divider()
            switch tab {
            case .chat: ChatView(agent: agent.id)
            case .status: StatusView(agent: agent)
            case .decisions: DecisionList(decisions: model.decisions.filter { $0.lead == agent.id })
            }
        }
        .navigationTitle(agent.id)
        .toolbar { controls }
        .sheet(isPresented: $opening) { NewSessionSheet(parent: agent) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: agent.spec.role.symbol).foregroundStyle(.secondary)
                    Text(agent.id).font(.title2.weight(.semibold))
                    RunStateTag(agent: agent)
                }
                Text(facts)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var facts: String {
        var facts = [agent.spec.role.label, agent.spec.model]
        if let area = agent.spec.area, agent.spec.role != .lead || area != agent.id { facts.append(area) }
        if let since = agent.since, agent.state == .running { facts.append("up since \(since.short)") }
        if let updated = agent.statusUpdated { facts.append("status changed \(updated.formatted(.relative(presentation: .named)))") }
        if let fork = agent.spec.forkOf { facts.append("forked from \(fork)") }
        return facts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var controls: some ToolbarContent {
        ToolbarItemGroup {
            if agent.spec.role != .project {
                Button(agent.spec.role == .chiefOfStaff ? "New lead" : "New project session", systemImage: "plus.square.on.square") { opening = true }
            }
            Menu("Session", systemImage: "power") {
                Button("Start", systemImage: "play") { act(.start) }
                    .disabled(agent.state == .running)
                Button("Restart", systemImage: "arrow.clockwise") { act(.restart) }
                Button("Stop", systemImage: "stop", role: .destructive) { act(.stop) }
                    .disabled(agent.state == .stopped)
            }
        }
    }

    private func act(_ action: AgentAction) {
        Task { await model.control(agent, action) }
    }
}

/// The agent's status file, rendered.
struct StatusView: View {
    @Environment(AppModel.self) private var model
    let agent: Agent
    @State private var file: StatusFile?
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let file {
                VStack(alignment: .leading, spacing: 12) {
                    Text(agent.spec.statusFile)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if file.text.isEmpty {
                        Text("The status file is empty.").foregroundStyle(.secondary)
                    } else {
                        Markdown(file.text)
                            .markdownTheme(.basic)
                            .textSelection(.enabled)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error {
                Placeholder(title: "Couldn't load the status", symbol: "exclamationmark.triangle", detail: error)
            } else {
                ProgressView().padding(40)
            }
        }
        .task(id: agent.statusUpdated) {
            do {
                file = try await model.status(of: agent.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
