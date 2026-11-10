import Foundation
import VaqueroKit
#if canImport(Glibc)
import Glibc
#endif

/// Who may write into a folder the service creates. The service sets each mode itself,
/// so the result never depends on the process's umask.
enum Access {
    /// Only the service writes here: 0755.
    case service
    /// The service and the agents both write here, through the shared group: 02775.
    case shared

    var mode: Int { self == .service ? 0o755 : 0o2775 }
}

/// Plain-file helpers. Every write is atomic, so readers never see half a file.
/// Files are 0644: only their owner changes them.
enum Files {
    static func read(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    static func write(_ data: Data, to url: URL, folder access: Access = .service) throws {
        try makeFolder(url.deletingLastPathComponent(), access)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }

    /// Creates a folder and any missing parents with the given access.
    static func makeFolder(_ folder: URL, _ access: Access) throws {
        let manager = FileManager.default
        var missing: [URL] = []
        var next = folder
        while !manager.fileExists(atPath: next.path) {
            missing.append(next)
            next = next.deletingLastPathComponent()
        }
        for created in missing.reversed() {
            try manager.createDirectory(at: created, withIntermediateDirectories: false)
            try manager.setAttributes([.posixPermissions: access.mode], ofItemAtPath: created.path)
        }
    }

    /// Writes a file only if nothing has that name yet, and returns false if something does.
    /// Readers see either no file or the whole file. When two writers race, exactly one wins.
    static func create(_ data: Data, at url: URL) throws -> Bool {
        let folder = url.deletingLastPathComponent()
        try makeFolder(folder, .service)
        let temp = folder.appending(path: ".\(UUID().uuidString).tmp")
        try data.write(to: temp)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: temp.path)
        defer { try? FileManager.default.removeItem(at: temp) }
        if link(temp.path, url.path) == 0 { return true }
        if errno == EEXIST { return false }
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
    }

    static func readJSON<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        try JSONDecoder.vaquero.decode(type, from: Data(contentsOf: url))
    }

    static func writeJSON(_ value: some Encodable, to url: URL) throws {
        try write(JSONEncoder.vaquero.encode(value), to: url)
    }

    static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// The visible files in a folder, sorted by name, optionally only those with one extension.
    static func list(_ folder: URL, ext: String? = nil) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .filter { !$0.hasPrefix(".") && (ext == nil || $0.hasSuffix(".\(ext!)")) }
            .sorted()
            .map { folder.appending(path: $0) }
    }

    /// A short hash of a file's content. A missing file has the empty tag.
    static func etag(_ data: Data?) -> String {
        guard let data else { return "" }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// A hash of the name, size and change time of each file, or of each file in each folder.
    static func fingerprint(_ urls: [URL]) -> Int {
        var hasher = Hasher()
        let manager = FileManager.default
        for url in urls {
            let children = (try? manager.contentsOfDirectory(atPath: url.path))?.sorted()
            for path in children.map({ $0.map { url.appending(path: $0) } }) ?? [url] {
                let attributes = try? manager.attributesOfItem(atPath: path.path)
                hasher.combine(path.path)
                hasher.combine(attributes?[.size] as? Int)
                hasher.combine(attributes?[.modificationDate] as? Date)
            }
        }
        return hasher.finalize()
    }

    /// Every line of a JSONL file that decodes. Bad lines are skipped.
    static func readLines<T: Decodable>(_ type: T.Type, at url: URL) -> [T] {
        guard let data = read(url) else { return [] }
        let decoder = JSONDecoder.vaquero
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(type, from: Data($0)) }
    }

    /// The last `maxBytes` of a file, starting at a line break.
    static func tail(_ url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard var data = try? handle.readToEnd() else { return nil }
        if start > 0, let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
            data = data[data.index(after: newline)...]
        }
        return Data(data)
    }
}
