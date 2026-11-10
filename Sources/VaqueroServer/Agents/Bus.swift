import Foundation
import VaqueroKit

/// The message bus: one file per message in the recipient's inbox. The recipient moves each
/// message to `done/` once it has read it. Each agent's launcher, `deploy/vaquero-agent`,
/// watches its inbox and rings the session's doorbell.
///
/// A message file starts with `From:` and `At:` lines and a blank line, then the text.
/// A file without them still counts: the sender shows as unknown and the time is the file's.
struct Bus: Sendable {
    let paths: Paths

    func post(_ message: BusMessage) throws {
        try Files.write(Data(Self.render(message).utf8), to: paths.inbox(message.to).appending(path: "\(message.id).md"), folder: .shared)
    }

    func unread(_ name: String) -> [BusMessage] {
        Files.list(paths.inbox(name)).compactMap { read($0, to: name) }
    }

    /// The newest messages the agent has finished with.
    func read(_ name: String, limit: Int = 50) -> [BusMessage] {
        Files.list(paths.done(name)).suffix(limit).compactMap { read($0, to: name) }
    }

    private func read(_ url: URL, to name: String) -> BusMessage? {
        guard let data = Files.read(url) else { return nil }
        return Self.parse(String(decoding: data, as: UTF8.self), id: url.deletingPathExtension().lastPathComponent, to: name, modified: Files.modified(url) ?? .now)
    }

    /// A new message id. Ids sort in the order the messages were sent.
    static func newID(at date: Date) -> String {
        let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted).dateSeparator(.omitted))
        return "\(stamp)-\(UUID().uuidString.prefix(6).lowercased())"
    }

    static func render(_ message: BusMessage) -> String {
        "From: \(message.from)\nAt: \(message.at.formatted(.iso8601))\n\n\(message.text)\n"
    }

    static func parse(_ file: String, id: String, to: String, modified: Date) -> BusMessage {
        var headers: [Substring: String] = [:]
        var text = Substring(file)
        if file.hasPrefix("From: ") || file.hasPrefix("At: "), let end = file.range(of: "\n\n") {
            for line in file[..<end.lowerBound].split(separator: "\n") {
                let pair = line.split(separator: ": ", maxSplits: 1)
                if pair.count == 2 { headers[pair[0]] = String(pair[1]) }
            }
            text = file[end.upperBound...]
        }
        let at = headers["At"].flatMap { stamp in
            (try? Date(stamp, strategy: .iso8601))
                ?? (try? Date(stamp, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
        }
        return BusMessage(id: id, from: headers["From"] ?? "unknown", to: to, at: at ?? modified, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
