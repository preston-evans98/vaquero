import SwiftUI
import VaqueroKit

/// The chief of staff's one-line log of every message, newest first, grouped by day.
struct LogScreen: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""

    private var days: [(day: Date, entries: [LogEntry])] {
        let calendar = Calendar.current
        let entries = model.log.filter { entry in
            filter.isEmpty || [entry.chat, entry.sender, entry.gist, entry.owner].contains { $0.localizedCaseInsensitiveContains(filter) }
        }
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.at) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            ForEach(days, id: \.day) { day in
                SwiftUI.Section(day.day.formatted(date: .complete, time: .omitted)) {
                    ForEach(day.entries, id: \.self) { LogRow(entry: $0) }
                }
            }
        }
        .searchable(text: $filter, prompt: "Filter by chat, sender or owner")
        .overlay {
            if model.log.isEmpty { Placeholder(title: "No messages yet", symbol: "list.bullet.rectangle") }
        }
        .navigationTitle("Log")
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.at.formatted(date: .omitted, time: .shortened))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Image(systemName: entry.channel.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityLabel(entry.channel.label)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.gist)
                Text("\(entry.sender) in \(entry.chat)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.owner)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
