import Foundation
import VaqueroKit

/// Everything about Claude Code's transcripts and prompts. With `deploy/vaquero-agent`, this is
/// the only code tied to Claude Code; another agent tool needs only new versions of the two.
enum Transcript {
    /// What the launcher types into an idle session when mail is waiting.
    /// `deploy/vaquero-agent` types the same text.
    static let doorbellPrompt = "New mail is waiting. Read your inbox."

    /// Claude Code names a project's transcript folder after its working directory, with every
    /// character other than a letter or digit replaced by "-". `deploy/vaquero-agent` applies the same rule.
    static func folder(for workdir: String, in projects: URL) -> URL {
        projects.appending(path: String(workdir.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }))
    }

    /// The last entries of the newest session in a transcript folder. Files named `agent-*`
    /// belong to sub-agents, so they are skipped.
    static func recent(in folder: URL, limit: Int = 200) -> [TranscriptEntry] {
        let sessions = Files.list(folder, ext: "jsonl").filter { !$0.lastPathComponent.hasPrefix("agent-") }
        let newest = sessions.max { (Files.modified($0) ?? .distantPast) < (Files.modified($1) ?? .distantPast) }
        guard let newest, let data = Files.tail(newest, maxBytes: 4 << 20) else { return [] }
        let all = data.split(separator: UInt8(ascii: "\n")).flatMap { Self.entries(fromLine: Data($0)) }
        return Array(all.suffix(limit))
    }

    /// The text and tool calls in one transcript line. Tool results, doorbell prompts
    /// and bookkeeping lines yield nothing; the bus messages already show what the doorbell announced.
    static func entries(fromLine line: Data) -> [TranscriptEntry] {
        guard let line = try? JSONDecoder().decode(Line.self, from: line),
              let message = line.message,
              let id = line.uuid
        else { return [] }
        let at = line.timestamp.flatMap(Self.date)
        let speaker: Speaker = line.type == "assistant" ? .assistant : .user
        switch message.content {
        case let .text(text):
            if speaker == .user && text == doorbellPrompt { return [] }
            return [TranscriptEntry(id: id, at: at, speaker: speaker, text: text)]
        case let .blocks(blocks):
            return blocks.enumerated().compactMap { index, block in
                let id = "\(id)-\(index)"
                switch block.type {
                case "text":
                    guard let text = block.text, !(speaker == .user && text == doorbellPrompt) else { return nil }
                    return TranscriptEntry(id: id, at: at, speaker: speaker, text: text)
                case "tool_use": return TranscriptEntry(id: id, at: at, speaker: .tool, text: block.name ?? "tool")
                default: return nil
                }
            }
        }
    }

    private static func date(_ text: String) -> Date? {
        (try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: .iso8601))
    }

    private struct Line: Decodable {
        let type: String?
        let uuid: String?
        let timestamp: String?
        let message: Message?
    }

    private struct Message: Decodable {
        let content: Content
    }

    private enum Content: Decodable {
        case text(String)
        case blocks([Block])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else {
                self = .blocks(try container.decode([Block].self))
            }
        }
    }

    private struct Block: Decodable {
        let type: String
        let text: String?
        let name: String?
    }
}
