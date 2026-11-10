import Foundation
import VaqueroKit

typealias SessionState = (state: RunState, since: Date?)

/// Starts, stops and reports on agent sessions.
protocol Supervisor: Sendable {
    func states(of names: [String]) async -> [String: SessionState]
    func perform(_ action: AgentAction, on name: String) async throws
}

/// Runs each agent as the systemd unit `vaquero-agent@<name>`. A polkit rule from
/// `deploy/install.sh` lets the service's user start, stop and restart those units, and nothing else.
struct SystemdSupervisor: Supervisor {
    func states(of names: [String]) async -> [String: SessionState] {
        guard !names.isEmpty else { return [:] }
        let output = try? await Shell.run(["systemctl", "show", "-p", "Id", "-p", "ActiveState", "-p", "SubState", "-p", "StateChangeTimestamp"] + names.map(unit))
        return output.map(Self.parse) ?? [:]
    }

    func perform(_ action: AgentAction, on name: String) async throws {
        _ = try await Shell.run("systemctl", action.rawValue, unit(name))
    }

    private func unit(_ name: String) -> String { "vaquero-agent@\(name).service" }

    /// Reads `systemctl show` output: one block of `Key=value` lines per unit, with blank lines between.
    static func parse(_ output: String) -> [String: SessionState] {
        var states: [String: SessionState] = [:]
        for block in output.components(separatedBy: "\n\n") {
            var properties: [Substring: Substring] = [:]
            for line in block.split(separator: "\n") {
                let pair = line.split(separator: "=", maxSplits: 1)
                if pair.count == 2 { properties[pair[0]] = pair[1] }
            }
            guard let id = properties["Id"], id.hasPrefix("vaquero-agent@"), id.hasSuffix(".service") else { continue }
            let name = String(id.dropFirst("vaquero-agent@".count).dropLast(".service".count))
            let state: RunState = switch properties["ActiveState"] {
            // A unit that keeps crashing waits in "auto-restart" between tries.
            case "activating" where properties["SubState"] == "auto-restart": .failed
            case "active": .running
            case "activating", "reloading": .starting
            case "inactive", "deactivating": .stopped
            case "failed": .failed
            default: .unknown
            }
            states[name] = (state, properties["StateChangeTimestamp"].flatMap { timestamp.date(from: String($0)) })
        }
        return states
    }

    /// systemd prints times like "Tue 2026-11-10 09:12:00 UTC".
    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE yyyy-MM-dd HH:mm:ss zzz"
        return formatter
    }()
}

/// Keeps run states in memory. For demo mode and tests.
actor FakeSupervisor: Supervisor {
    private var current: [String: SessionState] = [:]
    private let started = Date()
    private let failing: Set<String>

    /// `failing` names agents whose units cannot start.
    init(stopped: [String] = [], failing: Set<String> = []) {
        self.failing = failing
        for name in stopped { current[name] = (.stopped, started) }
    }

    func states(of names: [String]) async -> [String: SessionState] {
        Dictionary(uniqueKeysWithValues: names.map { ($0, current[$0] ?? (.running, started)) })
    }

    func perform(_ action: AgentAction, on name: String) async throws {
        if failing.contains(name) && action != .stop { throw ShellError(command: "start \(name)", status: 1) }
        current[name] = (action == .stop ? .stopped : .running, Date())
    }
}

enum Shell {
    static func run(_ arguments: String...) async throws -> String {
        try await run(arguments)
    }

    /// Runs a command and returns its standard output. Throws if it exits with an error
    /// or takes longer than the time limit.
    static func run(_ arguments: [String], limit: Duration = .seconds(10)) async throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let watchdog = Task {
            try await Task.sleep(for: limit)
            process.terminate()
        }
        defer { watchdog.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(decoding: data, as: UTF8.self))
                } else {
                    continuation.resume(throwing: ShellError(command: arguments.joined(separator: " "), status: process.terminationStatus))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

struct ShellError: Error, CustomStringConvertible {
    let command: String
    let status: Int32
    var description: String { "\(command) exited with status \(status)" }
}
