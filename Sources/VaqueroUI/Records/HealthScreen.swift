import Charts
import SwiftUI
import VaqueroKit

/// Heartbeats from each machine and component, and background model use against the cap.
struct HealthScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let health = model.health {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                        ForEach(health.heartbeats) { HeartbeatCard(beat: $0, now: model.now) }
                    }
                    if let today = health.usage.last {
                        UsagePanel(days: health.usage, today: today)
                    }
                } else {
                    Placeholder(title: "No health data", symbol: "heart.text.square")
                }
            }
            .padding(20)
        }
        .navigationTitle("Health")
    }
}

private struct HeartbeatCard: View {
    let beat: Heartbeat
    let now: Date

    var body: some View {
        let stale = beat.isStale(now: now)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(beat.component).font(.headline)
                Spacer()
                if stale {
                    Tag(text: "Stale", color: .red, symbol: "exclamationmark.triangle")
                } else {
                    Tag(text: "OK", color: .green, symbol: "checkmark")
                }
            }
            Text(beat.info.machine)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            if let note = beat.info.note {
                Text(note).font(.callout)
            }
            Text("Last heartbeat \(beat.at.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if stale { RoundedRectangle(cornerRadius: 12).strokeBorder(.red.opacity(0.6)) }
        }
    }
}

private struct UsagePanel: View {
    let days: [UsageDay]
    let today: UsageDay
    @State private var selected: String?

    private var share: Double { Double(today.tokens) / Double(max(today.cap, 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background model use").font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(tokens(today.tokens))
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                Text("of \(tokens(today.cap)) \(dayLabel) · \(share.formatted(.percent.precision(.fractionLength(0))))")
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(days) { day in
                    BarMark(x: .value("Day", label(day)), y: .value("Tokens", day.tokens), width: .ratio(0.55))
                        .foregroundStyle(Color.accentColor.opacity(selected == nil || selected == label(day) ? 1 : 0.4))
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                }
                RuleMark(y: .value("Cap", today.cap))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Cap \(tokens(today.cap))").font(.caption).foregroundStyle(.secondary)
                    }
                if let selected, let day = days.first(where: { label($0) == selected }) {
                    RuleMark(x: .value("Day", selected))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            Text("\(tokens(day.tokens)) tokens")
                                .font(.caption.weight(.medium))
                                .padding(6)
                                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                                .shadow(radius: 2)
                        }
                }
            }
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { Text(tokens(value.as(Int.self) ?? 0)) }
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    /// "today", or the day of the newest figures when none came in today.
    private var dayLabel: String {
        let today = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return today == self.today.date ? "today" : "on \(label(self.today))"
    }

    private func label(_ day: UsageDay) -> String {
        guard let date = try? Date(day.date + "T12:00:00Z", strategy: .iso8601) else { return day.date }
        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func tokens(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }
}
