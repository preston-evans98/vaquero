import SwiftUI
import VaqueroKit

/// The owner's queue: a list of items and the selected item's detail.
struct QueueScreen: View {
    @Environment(AppModel.self) private var model
    @State private var selection: QueueItem.ID?

    var body: some View {
        #if os(macOS)
        HSplitView {
            list
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
            Group {
                if let item = model.queue.first(where: { $0.id == selection }) {
                    // After an answer, nothing is selected, so a second ⌘↩ cannot send an unseen item.
                    QueueDetail(item: item) { selection = nil }
                        .id(item.id)
                } else {
                    Placeholder(title: model.queue.isEmpty ? "Queue is clear" : "Pick an item", symbol: "tray")
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { selection = selection ?? model.queue.first?.id }
        #else
        list
            .navigationDestination(for: QueueItem.ID.self) { id in
                if let item = model.queue.first(where: { $0.id == id }) {
                    QueueDetail(item: item) {}
                        .id(item.id)
                }
            }
        #endif
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(model.queue) { item in
                #if os(macOS)
                QueueRow(item: item).tag(item.id)
                #else
                // Approving needs the full item in view, so the row offers only the safe answer.
                NavigationLink(value: item.id) { QueueRow(item: item) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(item.kind.ignoreLabel) { Task { await model.resolve(item, .ignore) } }
                    }
                #endif
            }
        }
        .overlay {
            if model.queue.isEmpty { Placeholder(title: "Queue is clear", symbol: "checkmark.circle", detail: "New drafts and advice from the leads appear here.") }
        }
        .navigationTitle("Queue")
    }
}

struct QueueRow: View {
    let item: QueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: item.channel?.symbol ?? item.kind.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(item.chat ?? item.kind.label)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(item.created.short)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.gist)
                .lineLimit(2)
                .foregroundStyle(.primary.opacity(0.85))
            HStack(spacing: 6) {
                Text("\(item.kind.label) · \(item.lead)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                UrgencyTag(urgency: item.urgency)
            }
        }
        .padding(.vertical, 4)
    }
}
