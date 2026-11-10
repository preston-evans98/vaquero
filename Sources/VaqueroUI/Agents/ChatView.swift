import SwiftUI
import VaqueroKit

/// A live conversation with one agent. The owner's messages go through the agent's inbox.
struct ChatView: View {
    @Environment(AppModel.self) private var model
    let agent: String
    @State private var draft = ""
    @FocusState private var composing: Bool

    private var timeline: [TimelineItem] { model.conversations[agent]?.timeline ?? [] }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(timeline) { item in
                        TimelineRow(item: item).id(item.id)
                    }
                }
                .padding(16)
            }
            .defaultScrollAnchor(.bottom)
            .overlay {
                if model.conversations[agent] == nil {
                    ProgressView()
                } else if timeline.isEmpty {
                    Placeholder(title: "No conversation yet", symbol: "bubble.left.and.bubble.right")
                }
            }
            .onChange(of: timeline.last?.id) { _, last in
                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .task(id: agent) { await model.watch(agent) }
        .onDisappear { model.unwatch(agent) }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message \(agent)", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .focused($composing)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Send")
        }
        .padding(12)
        .background(.bar)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task {
            if await !model.send(text, to: agent), draft.isEmpty { draft = text }
        }
    }
}

private struct TimelineRow: View {
    let item: TimelineItem

    var body: some View {
        switch item {
        case let .entry(entry):
            switch entry.speaker {
            case .assistant:
                Bubble(text: entry.text, caption: entry.at?.short, outgoing: false)
            case .user:
                Bubble(text: entry.text, caption: ["Prompt", entry.at?.short].compactMap(\.self).joined(separator: " · "), outgoing: true, muted: true)
            case .tool:
                Label(entry.text, systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            }
        case let .message(message, read):
            let caption = [message.from == "owner" ? nil : "From \(message.from)", message.at.short, read ? nil : "Unread"]
            Bubble(
                text: message.text,
                caption: caption.compactMap(\.self).joined(separator: " · "),
                outgoing: message.from == "owner",
                muted: message.from != "owner"
            )
        }
    }
}

private struct Bubble: View {
    let text: String
    let caption: String?
    let outgoing: Bool
    var muted = false

    var body: some View {
        VStack(alignment: outgoing ? .trailing : .leading, spacing: 3) {
            Text(LocalizedStringKey(text))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(outgoing && !muted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(background, in: RoundedRectangle(cornerRadius: 14))
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 560, alignment: outgoing ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: outgoing ? .trailing : .leading)
    }

    private var background: AnyShapeStyle {
        if outgoing && !muted { return AnyShapeStyle(.tint) }
        return outgoing ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.background.secondary)
    }
}
