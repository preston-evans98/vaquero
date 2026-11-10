import SwiftUI
import VaqueroKit

// MARK: Chat lists

/// Which chats agents read live, which they may search, and which they never touch.
struct ChatListsEditor: View {
    @State private var filter = ""
    @State private var adding = false
    @State private var removing: ChatRule?

    var body: some View {
        ConfigScreen { (lists: Binding<ChatLists>) in
            List {
                ForEach(ChatListKind.allCases, id: \.self) { kind in
                    SwiftUI.Section {
                        ForEach(lists.chats) { $rule in
                            if rule.list == kind && matches(rule) {
                                ChatRuleRow(rule: $rule)
                                    .contextMenu {
                                        Button("Remove from lists", role: .destructive) { removing = rule }
                                    }
                            }
                        }
                    } header: {
                        Text(kind.label)
                    } footer: {
                        Text(kind.explanation)
                    }
                }
            }
            .searchable(text: $filter, prompt: "Filter chats")
            .toolbar {
                ToolbarItem { Button("Add chat", systemImage: "plus") { adding = true } }
            }
            .sheet(isPresented: $adding) {
                AddChatSheet(taken: Set(lists.wrappedValue.chats.map(\.id))) { lists.wrappedValue.chats.append($0) }
            }
            .confirmationDialog(
                "Remove \(removing?.title ?? "this chat") from the lists?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                presenting: removing
            ) { rule in
                Button("Remove", role: .destructive) { lists.wrappedValue.chats.removeAll { $0.id == rule.id } }
            } message: { rule in
                Text(rule.list == .blocked
                    ? "The chat will no longer be blocked. Agents could then search it at the source when you name it."
                    : "The server will stop storing new messages from this chat.")
            }
        }
    }

    private func matches(_ rule: ChatRule) -> Bool {
        filter.isEmpty || rule.title.localizedCaseInsensitiveContains(filter) || rule.chat.localizedCaseInsensitiveContains(filter)
    }
}

private struct ChatRuleRow: View {
    @Binding var rule: ChatRule

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: rule.channel.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityLabel(rule.channel.label)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title)
                Text("\(rule.channel.label) · \(rule.chat)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("List", selection: $rule.list) {
                ForEach(ChatListKind.allCases, id: \.self) { Text($0.label) }
            }
            .labelsHidden()
            .fixedSize()
            Picker("Filter", selection: $rule.strictness) {
                ForEach(Strictness.allCases, id: \.self) { Text($0.label) }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(rule.list != .continuous)
        }
    }
}

private struct AddChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// The chats already on a list. A chat may be on only one.
    let taken: Set<String>
    let add: (ChatRule) -> Void
    @State private var rule = ChatRule(channel: .whatsapp, chat: "", title: "", list: .continuous, strictness: .normal)

    var body: some View {
        NavigationStack {
            Form {
                Picker("Channel", selection: $rule.channel) {
                    ForEach(Channel.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol) }
                }
                TextField("Chat id", text: $rule.chat, prompt: Text("+351910000000"))
                TextField("Name", text: $rule.title)
                Picker("List", selection: $rule.list) {
                    ForEach(ChatListKind.allCases, id: \.self) { Text($0.label) }
                }
                Picker("Filter strictness", selection: $rule.strictness) {
                    ForEach(Strictness.allCases, id: \.self) { Text($0.label) }
                }
                if taken.contains(rule.id) {
                    Text("This chat is already on a list. Change its list there.").foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add chat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        add(rule)
                        dismiss()
                    }
                    .disabled(rule.chat.isEmpty || rule.title.isEmpty || taken.contains(rule.id))
                }
            }
        }
        .frame(minWidth: 380, minHeight: 300)
    }
}

extension ChatListKind {
    var label: String { rawValue.capitalized }

    var explanation: String {
        switch self {
        case .continuous: "Read as messages arrive. Leads act on them."
        case .searchable: "Stored and searchable. Read only when a task needs them."
        case .blocked: "Never searched, even on request."
        }
    }
}

extension Strictness {
    var label: String {
        switch self {
        case .strict: "Strict filter"
        case .normal: "Normal filter"
        case .light: "Light filter"
        }
    }
}

// MARK: Routing map

/// Which lead gets each area's messages.
struct RoutingEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ConfigScreen { (map: Binding<RoutingMap>) in
            Form {
                ForEach(map.routes) { $route in
                    SwiftUI.Section {
                        TextField("Area", text: $route.area)
                        LeadPicker(selection: $route.lead)
                        TextField("Contacts and topics", text: $route.match, axis: .vertical)
                            .lineLimit(2...5)
                        Button("Remove area", role: .destructive) { map.wrappedValue.routes.removeAll { $0.id == route.id } }
                    }
                }
                Button("Add area", systemImage: "plus") {
                    map.wrappedValue.routes.append(Route(area: "New area", lead: model.leads.first?.id ?? "", match: ""))
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: Nudges

/// Regular nudges from the chief of staff to the leads.
struct NudgesEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ConfigScreen { (plan: Binding<NudgePlan>) in
            Form {
                SwiftUI.Section {
                    Stepper("Nudge a lead after \(plan.wrappedValue.stallDays) quiet days", value: plan.stallDays, in: 1...30)
                } footer: {
                    Text("A lead is quiet when its status file has not changed.")
                }
                ForEach(plan.nudges) { $nudge in
                    SwiftUI.Section {
                        LeadPicker(selection: $nudge.lead)
                        TextField("Goal", text: $nudge.goal, axis: .vertical)
                        Picker("Every", selection: $nudge.everyHours) {
                            Text("Hour").tag(1)
                            Text("6 hours").tag(6)
                            Text("Day").tag(24)
                            Text("Week").tag(168)
                        }
                        Toggle("Tell me if nothing passes review", isOn: Binding(
                            get: { nudge.tellOwnerAfterDays != nil },
                            set: { nudge.tellOwnerAfterDays = $0 ? 7 : nil }
                        ))
                        if let days = nudge.tellOwnerAfterDays {
                            Stepper("…within \(days) days", value: Binding(get: { days }, set: { nudge.tellOwnerAfterDays = $0 }), in: 1...60)
                        }
                        Button("Remove nudge", role: .destructive) { plan.wrappedValue.nudges.removeAll { $0.id == nudge.id } }
                    }
                }
                Button("Add nudge", systemImage: "plus") {
                    plan.wrappedValue.nudges.append(Nudge(lead: model.leads.first?.id ?? "", goal: "", everyHours: 24))
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: Priority rules

/// What counts as urgent. Every lead follows this one file.
struct PrioritiesEditor: View {
    var body: some View {
        ConfigScreen { (rules: Binding<Priorities>) in
            TextEditor(text: rules.text)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(16)
        }
    }
}

// MARK: Tool rules

/// The tools agent sessions may use. Sessions run unattended, so they refuse any tool on neither list.
struct ToolRulesEditor: View {
    var body: some View {
        ConfigScreen { (rules: Binding<ToolRules>) in
            Form {
                SwiftUI.Section {
                    RuleList(rules: rules.allow)
                } header: {
                    Text("Allowed")
                } footer: {
                    Text("One Claude Code permission rule per line, such as Read, Bash(git log:*) or mcp__search__query. Sessions use new rules after they restart.")
                }
                SwiftUI.Section("Denied") {
                    RuleList(rules: rules.deny)
                }
            }
            .formStyle(.grouped)
        }
    }
}

/// Edits a list of rules as lines of text. Blank lines stay while typing and drop out of the rules.
private struct RuleList: View {
    @Binding var rules: [String]
    @State private var text = ""

    var body: some View {
        TextEditor(text: $text)
            .font(.body.monospaced())
            .frame(minHeight: 120)
            .onAppear { text = rules.joined(separator: "\n") }
            .onChange(of: text) { rules = Self.parse(text) }
            .onChange(of: rules) { if Self.parse(text) != rules { text = rules.joined(separator: "\n") } }
    }

    private static func parse(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// Picks one of the leads.
private struct LeadPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String

    var body: some View {
        Picker("Lead", selection: $selection) {
            ForEach(model.leads) { Text($0.id).tag($0.id) }
            if !model.leads.contains(where: { $0.id == selection }) {
                Text(selection.isEmpty ? "None" : selection).tag(selection)
            }
        }
    }
}
