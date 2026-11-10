import SwiftUI
import VaqueroKit

/// One queue item, with the owner's two answers. The approving answer stays off until the
/// owner has seen the end of the current version of the item.
struct QueueDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: QueueItem
    /// Called after the owner answers.
    let onResolved: () -> Void

    @State private var reply: String
    /// True while the end of the item is on screen.
    @State private var endVisible = false
    /// The latest version whose end the owner has seen.
    @State private var seenVersion: String?
    /// True when the lead changed the draft while the owner was editing it.
    @State private var changedWhileEditing = false

    init(item: QueueItem, onResolved: @escaping () -> Void) {
        self.item = item
        self.onResolved = onResolved
        _reply = State(initialValue: item.draft ?? "")
    }

    private var edited: Bool { item.draft != nil && reply != item.draft }
    private var seenAll: Bool { seenVersion != nil && seenVersion == item.version }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if changedWhileEditing { changedBanner }
                content
                if let context = item.context {
                    Block("Context") {
                        Text(context)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Color.clear
                    .frame(height: 1)
                    .onScrollVisibilityChange(threshold: 0.5) { visible in
                        endVisible = visible
                        if visible { seenVersion = item.version }
                    }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { actions }
        .navigationTitle(item.chat ?? item.kind.label)
        .onChange(of: item.version) {
            seenVersion = endVisible ? item.version : nil
        }
        .onChange(of: item.draft) { old, new in
            if reply == (old ?? "") {
                reply = new ?? ""
            } else {
                changedWhileEditing = true
            }
        }
    }

    private var changedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(item.lead) changed the draft while you were editing it. Your edit is kept below.", systemImage: "exclamationmark.triangle")
            HStack {
                Button("Use the new draft") {
                    reply = item.draft ?? ""
                    changedWhileEditing = false
                }
                Button("Keep my edit") { changedWhileEditing = false }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Tag(text: item.kind.label, color: .accentColor, symbol: item.kind.symbol)
                UrgencyTag(urgency: item.urgency)
            }
            Text(item.gist)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 4) {
                if let channel = item.channel {
                    Label(channel.label, systemImage: channel.symbol)
                    Text("·")
                }
                if let sender = item.sender, sender != item.chat {
                    Text(sender)
                    Text("·")
                }
                Text("from \(item.lead), \(item.created.short)")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .draft:
            Block(edited ? "Reply (edited)" : "Reply") {
                TextEditor(text: $reply)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                if edited {
                    Button("Revert to the lead's draft") { reply = item.draft ?? "" }
                        .buttonStyle(.borderless)
                }
            }
        case .advice:
            if let advice = item.advice {
                Block("Advice") { Text(advice).textSelection(.enabled) }
            }
        case .heldBack:
            Label {
                Text("The local filter kept this message away from every model. Release it to pass it to \(item.lead), or keep it private.")
            } icon: {
                Image(systemName: "lock.shield")
            }
            .foregroundStyle(.secondary)
        case .configChange:
            if let advice = item.advice {
                Text(advice).textSelection(.enabled)
            }
            if let change = item.change {
                Block("Changes to the \(change.file.label.lowercased())") {
                    ChangeView(change: change)
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            Button(role: .cancel) {
                answer(.ignore)
            } label: {
                Text(item.kind.ignoreLabel).frame(minWidth: 90)
            }
            // ⌘⌫ deletes text in the reply editor, so Ignore uses ⌘⇧⌫.
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            Spacer()
            if !seenAll {
                Text("Scroll to the end to \(item.kind.approveLabel.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                answer(.approve)
            } label: {
                Text(edited ? "Send edited" : item.kind.approveLabel).frame(minWidth: 90)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!seenAll || changedWhileEditing || (item.kind == .draft && reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func answer(_ verdict: Verdict) {
        let text = verdict == .approve && edited ? reply : nil
        onResolved()
        Task { await model.resolve(item, verdict, text: text) }
        #if os(iOS)
        dismiss()
        #endif
    }
}

/// A titled block in a detail screen.
struct Block<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// A proposed config file, line by line against the current one.
private struct ChangeView: View {
    let change: ConfigChange

    private var lines: [DiffLine] {
        let current = change.current.map { change.file.canonical($0) ?? $0 } ?? ""
        return DiffLine.lines(from: current, to: change.file.canonical(change.content) ?? change.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
        .font(.callout.monospaced())
        .textSelection(.enabled)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func row(_ line: DiffLine) -> some View {
        switch line {
        case let .same(text):
            Text("  " + text).foregroundStyle(.secondary)
        case let .removed(text):
            Text("− " + text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.14))
                .accessibilityLabel("Removed: \(text)")
        case let .added(text):
            Text("+ " + text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.16))
                .accessibilityLabel("Added: \(text)")
        }
    }
}
