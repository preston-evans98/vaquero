#if canImport(Darwin)
import Foundation

public enum ClientError: Error, LocalizedError, Equatable {
    /// The resource changed since the client read it.
    case conflict(String)
    case status(Int, String)

    public var errorDescription: String? {
        switch self {
        case let .conflict(message): message.isEmpty ? "Someone changed this since you loaded it." : message
        case let .status(code, message): "The server answered \(code): \(message)"
        }
    }
}

/// Calls the control service.
public struct Client: Sendable {
    public var baseURL: URL
    public var token: String

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    public func send<Request, Response>(
        _ endpoint: Endpoint<Request, Response>, _ parameters: String..., body: Request
    ) async throws -> Response {
        try await call(endpoint, parameters, body: body)
    }

    public func get<Response>(_ endpoint: Endpoint<Empty, Response>, _ parameters: String...) async throws -> Response {
        try await call(endpoint, parameters, body: Empty())
    }

    /// Yields each change the server announces until the connection drops.
    /// On connecting, the server announces every topic once, so the caller loads everything.
    public func changes() -> AsyncThrowingStream<Change, Error> {
        let request = request(API.events)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try check(response, Data())
                    for try await line in bytes.lines where line.hasPrefix("data: ") {
                        let change = try JSONDecoder.vaquero.decode(Change.self, from: Data(line.dropFirst(6).utf8))
                        continuation.yield(change)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func call<Request, Response>(
        _ endpoint: Endpoint<Request, Response>, _ parameters: [String], body: Request
    ) async throws -> Response {
        var request = request(endpoint.path(parameters))
        request.httpMethod = endpoint.verb.rawValue
        if Request.self != Empty.self {
            request.httpBody = try JSONEncoder.vaquero.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        return try JSONDecoder.vaquero.decode(Response.self, from: data)
    }

    /// A request for a path whose parameters `Endpoint.path` already encoded.
    private func request(_ path: String) -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        let base = components.percentEncodedPath.hasSuffix("/") ? String(components.percentEncodedPath.dropLast()) : components.percentEncodedPath
        components.percentEncodedPath = base + "/" + path
        var request = URLRequest(url: components.url ?? baseURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        return request
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message ?? String(decoding: data, as: UTF8.self)
        if http.statusCode == 409 { throw ClientError.conflict(message) }
        throw ClientError.status(http.statusCode, message)
    }

    /// Hummingbird's error body: `{"error": {"message": "..."}}`.
    private struct ErrorBody: Decodable {
        struct Inner: Decodable { let message: String }
        let error: Inner
    }
}
#endif
