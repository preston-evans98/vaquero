import SwiftUI
import VaqueroKit

/// Every answered queue item, newest answer first.
struct DecisionsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var lead: String?

    var body: some View {
        DecisionList(decisions: model.decisions.filter { lead == nil || $0.lead == lead })
            .navigationTitle("Decisions")
            .toolbar {
                Picker("Agent", selection: $lead) {
                    Text("All agents").tag(String?.none)
                    ForEach(Set(model.decisions.map(\.lead)).sorted(), id: \.self) { Text($0).tag(Optional($0)) }
                }
            }
    }
}

struct DecisionList: View {
    let decisions: [QueueItem]

    var body: some View {
        List(decisions) { DecisionRow(decision: $0) }
            .overlay {
                if decisions.isEmpty { Placeholder(title: "No decisions yet", symbol: "checkmark.seal") }
            }
    }
}

private struct DecisionRow: View {
    let decision: QueueItem

    private var approved: Bool { decision.resolution?.verdict == .approve }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: approved ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(approved ? .green : .secondary)
                .accessibilityLabel(approved ? decision.kind.approveLabel : decision.kind.ignoreLabel)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(decision.gist).font(.body.weight(.medium))
                    Spacer()
                    Text((decision.resolution?.at ?? decision.created).short)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if decision.edited, let text = decision.resolution?.text {
                    Text(text)
                        .font(.callout)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var summary: String {
        let verdict = approved ? decision.kind.approveLabel : decision.kind.ignoreLabel
        let parts = [
            decision.edited ? "\(verdict) (edited)" : verdict,
            decision.chat,
            decision.lead,
            decision.resolution.map { "via \($0.by)" },
        ]
        return parts.compactMap(\.self).joined(separator: " · ")
    }
}
