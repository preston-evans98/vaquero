import SwiftUI
import VaqueroKit

extension Channel {
    var label: String {
        switch self {
        case .gmail: "Gmail"
        case .mail: "Mail"
        case .telegram: "Telegram"
        case .whatsapp: "WhatsApp"
        case .imessage: "iMessage"
        case .slack: "Slack"
        case .instagram: "Instagram"
        case .x: "X"
        case .phone: "Phone"
        }
    }

    var symbol: String {
        switch self {
        case .gmail, .mail: "envelope"
        case .telegram: "paperplane"
        case .whatsapp: "phone.bubble"
        case .imessage: "message"
        case .slack: "number"
        case .instagram: "camera"
        case .x: "at"
        case .phone: "phone"
        }
    }
}

extension QueueKind {
    var label: String {
        switch self {
        case .draft: "Draft reply"
        case .advice: "Advice"
        case .heldBack: "Held back"
        case .configChange: "Config change"
        }
    }

    var symbol: String {
        switch self {
        case .draft: "arrowshape.turn.up.left"
        case .advice: "lightbulb"
        case .heldBack: "lock"
        case .configChange: "slider.horizontal.3"
        }
    }

    var approveLabel: String {
        switch self {
        case .draft: "Send"
        case .advice: "Agree"
        case .heldBack: "Release"
        case .configChange: "Apply"
        }
    }

    var ignoreLabel: String {
        switch self {
        case .draft: "Ignore"
        case .advice: "Dismiss"
        case .heldBack: "Keep private"
        case .configChange: "Reject"
        }
    }
}

extension AgentRole {
    var label: String {
        switch self {
        case .chiefOfStaff: "Chief of staff"
        case .lead: "Lead"
        case .project: "Project session"
        }
    }

    var symbol: String {
        switch self {
        case .chiefOfStaff: "star"
        case .lead: "person"
        case .project: "folder"
        }
    }
}

extension RunState {
    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .running: .green
        case .starting: .orange
        case .failed: .red
        case .stopped, .unknown: .secondary
        }
    }
}

extension ConfigFile {
    var label: String {
        switch self {
        case .lists: "Chat lists"
        case .routing: "Routing map"
        case .nudges: "Nudges"
        case .priorities: "Priority rules"
        case .tools: "Tool rules"
        }
    }
}

/// A small colored capsule with a text label, so state never rests on color alone.
struct Tag: View {
    let text: String
    let color: Color
    var symbol: String?

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let symbol { Image(systemName: symbol) }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption.weight(.medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
    }
}

struct RunStateTag: View {
    let agent: Agent

    var body: some View {
        if agent.stalled {
            Tag(text: "Stalled", color: .orange, symbol: "hourglass")
        } else {
            Tag(text: agent.state.label, color: agent.state.color)
        }
    }
}

struct UrgencyTag: View {
    let urgency: Urgency

    var body: some View {
        switch urgency {
        case .urgent: Tag(text: "Urgent", color: .red, symbol: "exclamationmark")
        case .normal: EmptyView()
        case .low: Tag(text: "Low", color: .secondary)
        }
    }
}

/// A placeholder for an empty screen.
struct Placeholder: View {
    let title: String
    let symbol: String
    var detail: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let detail { Text(detail) }
        }
    }
}

extension Date {
    /// "09:12" today, "Mon 09:12" this week, "3 Nov" before that.
    var short: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if let days = calendar.dateComponents([.day], from: self, to: .now).day, days < 6 {
            return formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return formatted(.dateTime.day().month(.abbreviated))
    }
}
