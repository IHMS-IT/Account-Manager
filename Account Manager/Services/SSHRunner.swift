//
//  SSHRunner.swift
//  Account Manager
//
//  Executes shell commands on a remote Mac via /usr/bin/ssh.
//  Requires key-based auth (passwordless sudo for privileged commands).
//

import Foundation
import Network

final class SSHRunner: Sendable {

    let host: RemoteHost

    init(host: RemoteHost) {
        self.host = host
    }

    // MARK: - Run a single command

    func run(_ command: String) async throws -> String {
        let expandedKey = host.sshKeyPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let args: [String] = [
            "-i", expandedKey,
            "-p", "\(host.port)",
            "-o", "StrictHostKeyChecking=no",
            "-o", "ConnectTimeout=10",
            "-o", "BatchMode=yes",
            "\(host.sshUser)@\(host.hostname)",
            command
        ]
        return try await runCommand("/usr/bin/ssh", args: args)
    }

    // MARK: - TCP reachability (fast pre-check before full SSH)

    /// Opens a raw TCP connection to host:port. Returns within `timeout` seconds.
    /// Much faster than a full SSH handshake — tells us immediately if the host
    /// is online and has port 22 open, before we spend time on key exchange.
    func canReach(timeout: TimeInterval = 5) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let port = NWEndpoint.Port(rawValue: UInt16(host.port)) else {
                continuation.resume(returning: false)
                return
            }
            let connection = NWConnection(
                host: NWEndpoint.Host(host.hostname),
                port: port,
                using: .tcp
            )
            let queue = DispatchQueue(label: "com.ihms.accountmanager.reachability")
            var resolved = false
            let finish: (Bool) -> Void = { result in
                guard !resolved else { return }
                resolved = true
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:          finish(true)
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }

    // MARK: - Full SSH connection test

    func testConnection() async -> Bool {
        let result = try? await run("echo __ok__")
        return result?.contains("__ok__") == true
    }
}
