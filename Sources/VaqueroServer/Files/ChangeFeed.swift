import Foundation
import VaqueroKit

enum FeedEvent: Sendable {
    case change(Change)
    /// Keeps idle connections open.
    case ping
}

/// Checks a fingerprint of each topic every second and tells each subscriber which topics changed.
/// The fingerprints cover files and the supervisor's view of each session.
actor ChangeFeed {
    private let fingerprints: @Sendable () async -> [Change: Int]
    private var last: [Change: Int] = [:]
    private var subscribers: [UUID: AsyncStream<FeedEvent>.Continuation] = [:]

    init(fingerprints: @escaping @Sendable () async -> [Change: Int]) {
        self.fingerprints = fingerprints
    }

    /// A stream that starts with every topic, so a new subscriber loads everything it needs
    /// and cannot miss a change between loading and listening.
    func subscribe() async -> AsyncStream<FeedEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<FeedEvent>.makeStream(bufferingPolicy: .bufferingNewest(256))
        for change in await fingerprints().keys.sorted(by: { ($0.topic.rawValue, $0.key ?? "") < ($1.topic.rawValue, $1.key ?? "") }) {
            continuation.yield(.change(change))
        }
        subscribers[id] = continuation
        continuation.onTermination = { _ in Task { await self.unsubscribe(id) } }
        return stream
    }

    var subscriberCount: Int { subscribers.count }

    /// Checks every second and pings every 20 seconds, until cancelled.
    func run() async {
        var ticks = 0
        while !Task.isCancelled {
            await tick()
            ticks += 1
            if ticks % 20 == 0 { broadcast(.ping) }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Compares each topic with the last check and announces the ones that changed.
    func tick() async {
        let current = await fingerprints()
        let first = last.isEmpty
        for (change, print) in current where last[change] != print && !first {
            broadcast(.change(change))
        }
        last = current
    }

    private func broadcast(_ event: FeedEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }
}
