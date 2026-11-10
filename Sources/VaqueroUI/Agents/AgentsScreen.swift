import SwiftUI
import VaqueroKit

/// The agent tree: the chief of staff, its leads, and each lead's project sessions.
struct AgentsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Agent.ID?

    var body: some View {
        #if os(macOS)
        HSplitView {
            list
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 380)
            Group {
                if let agent = selection.flatMap(model.agent) {
                    AgentDetail(agent: agent).id(agent.id)
                } else {
                    Placeholder(title: "Pick an agent", symbol: "person.3")
                }
            }
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { selection = selection ?? model.agents.first { $0.spec.role == .chiefOfStaff }?.id }
        #else
        list
            .navigationDestination(for: Agent.ID.self) { id in
                if let agent = model.agent(id) { AgentDetail(agent: agent) }
            }
        #endif
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(rows, id: \.agent.id) { row in
                #if os(macOS)
                AgentRow(agent: row.agent)
                    .padding(.leading, CGFloat(row.depth) * 18)
                    .tag(row.agent.id)
                #else
                NavigationLink(value: row.agent.id) { AgentRow(agent: row.agent) }
                    .padding(.leading, CGFloat(row.depth) * 18)
                #endif
            }
        }
        .overlay {
            if model.agents.isEmpty { Placeholder(title: "No agents", symbol: "person.3") }
        }
        .navigationTitle("Agents")
    }

    /// Each agent after its parent, with its depth in the tree.
    private var rows: [(agent: Agent, depth: Int)] {
        func rows(_ agent: Agent, _ depth: Int) -> [(agent: Agent, depth: Int)] {
            [(agent, depth)] + model.children(of: agent.id).flatMap { rows($0, depth + 1) }
        }
        let roots = model.agents.filter { $0.spec.parent.flatMap(model.agent) == nil }
        return roots.sorted { $0.id < $1.id }.flatMap { rows($0, 0) }
    }
}

struct AgentRow: View {
    let agent: Agent

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(agent.stalled ? .orange : agent.state.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.id).font(.body.weight(.medium))
                Text(agent.stalled ? "Stalled" : "\(agent.spec.role.label) · \(agent.state.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if agent.unread > 0 {
                Text("\(agent.unread)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel("\(agent.unread) unread")
            }
        }
        .padding(.vertical, 2)
    }
}
