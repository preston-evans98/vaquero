import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Hummingbird
import VaqueroKit

/// The message archive's search tool. The archive applies the rules for each chat list.
protocol Archive: Sendable {
    func search(_ query: SearchQuery) async throws -> [SearchHit]
}

/// Forwards each query to the archive's search service.
struct RemoteArchive: Archive {
    let url: URL

    func search(_ query: SearchQuery) async throws -> [SearchHit] {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.vaquero.encode(query)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw HTTPError(.badGateway, message: "The archive could not answer: \(String(decoding: data, as: UTF8.self))")
        }
        return try JSONDecoder.vaquero.decode([SearchHit].self, from: data)
    }
}

/// Searches a fixed list of messages by keyword. For demo mode.
struct FixtureArchive: Archive {
    let file: URL

    func search(_ query: SearchQuery) async throws -> [SearchHit] {
        let hits = (try? Files.readJSON([SearchHit].self, at: file)) ?? []
        let words = query.text.lowercased().split(separator: " ")
        return hits.filter { hit in words.contains { hit.text.lowercased().contains($0) } }.sorted { $0.score > $1.score }
    }
}

/// Used when no archive is set up yet.
struct MissingArchive: Archive {
    func search(_ query: SearchQuery) async throws -> [SearchHit] {
        throw HTTPError(.serviceUnavailable, message: "The message archive is not set up yet.")
    }
}
