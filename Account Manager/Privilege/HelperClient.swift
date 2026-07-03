//
//  HelperClient.swift
//  Account Manager
//
//  App-side XPC client. Connects to the privileged helper and exposes
//  async methods for Deleter to call.
//

import Foundation
import ServiceManagement

// MARK: - Installation status

enum HelperStatus: Equatable {
    case installed
    case notInstalled
    case requiresApproval   // user must approve in System Settings → Login Items
    case versionMismatch(installed: String, expected: String)
}

// MARK: - HelperClient

final class HelperClient {

    static let shared = HelperClient()
    private init() {}

    var isRunning: Bool {
        SMAppService.daemon(plistName: "com.ihms.accountmanager.helper.plist").status == .enabled
    }

    private var connection: NSXPCConnection?

    // MARK: - Installation

    private static let plistName = "com.ihms.accountmanager.helper.plist"

    /// Registers the helper if needed, and re-registers it when the currently
    /// running daemon is an older build than the one bundled with this app.
    /// Async because verifying the running daemon's version needs an XPC call.
    func installIfNeeded() async throws {
        let service = SMAppService.daemon(plistName: Self.plistName)
        switch service.status {
        case .notRegistered, .notFound:
            // A daemon that has never been registered has no Background Task
            // Management record yet, so `.status` reports `.notFound` rather than
            // `.notRegistered` on macOS 13+. In both cases register() is the right
            // action — the OS creates the record and surfaces the approval prompt.
            // A genuinely missing/invalid plist makes register() throw.
            try service.register()
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        case .enabled:
            // Registered — but the running daemon may be an older build. If its
            // reported version differs from the one bundled with this app, swap in
            // the new binary.
            let running = try? await getVersion()
            if running != helperBundledVersion {
                // Preferred path: ask the old daemon to exit. launchd relaunches
                // the updated binary (same path) on the next connection — no BTM
                // churn. Works for helpers new enough to expose quitHelper.
                try? await quitHelper()
                connection?.invalidate(); connection = nil
                try? await Task.sleep(for: .milliseconds(700))

                // If it's still stale (old helper without quitHelper, or launchd
                // didn't relaunch), fall back to a full re-register.
                let after = try? await getVersion()
                if after != helperBundledVersion {
                    try? await service.unregister()
                    try? await Task.sleep(for: .milliseconds(600))
                    try service.register()
                    connection?.invalidate(); connection = nil
                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
        @unknown default:
            break
        }
    }

    /// Asks the running helper to exit (best-effort). Uses a short timeout since a
    /// successful quit tears down the connection almost immediately.
    private func quitHelper() async throws {
        _ = try await callHelper(timeout: 3) { (h, resolve: @escaping (Bool) -> Void, _) in
            h.quitHelper { ok in resolve(ok) }
        }
    }

    func checkStatus() async -> HelperStatus {
        let service = SMAppService.daemon(plistName: Self.plistName)
        guard service.status == .enabled else {
            return service.status == .requiresApproval ? .requiresApproval : .notInstalled
        }
        guard let version = try? await getVersion() else { return .notInstalled }
        return version == helperBundledVersion
            ? .installed
            : .versionMismatch(installed: version, expected: helperBundledVersion)
    }

    // MARK: - XPC connection

    private func makeConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(machServiceName: helperMachServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: AccountManagerHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            self?.connection = nil
        }
        conn.interruptionHandler = { [weak self] in
            self?.connection = nil
        }
        conn.resume()
        return conn
    }

    private func proxy() throws -> AccountManagerHelperProtocol {
        if connection == nil { connection = makeConnection() }
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ [weak self] error in
            self?.connection = nil
        }) as? AccountManagerHelperProtocol else {
            throw HelperClientError.connectionFailed
        }
        return proxy
    }

    /// Wraps an XPC call so it can never hang forever — fails fast if the helper
    /// daemon isn't installed/running, and times out if it never replies.
    private func callHelper<T: Sendable>(
        timeout: Double = 10,
        _ operation: @escaping (AccountManagerHelperProtocol, @escaping (T) -> Void, @escaping (Error) -> Void) -> Void
    ) async throws -> T {
        guard isRunning else { throw HelperClientError.helperNotRunning }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                    guard let h = try? self.proxy() else {
                        continuation.resume(throwing: HelperClientError.connectionFailed)
                        return
                    }
                    operation(
                        h,
                        { value in continuation.resume(returning: value) },
                        { error in continuation.resume(throwing: error) }
                    )
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw HelperClientError.timedOut
            }
            guard let result = try await group.next() else {
                throw HelperClientError.timedOut
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Remote calls

    func getVersion() async throws -> String {
        try await callHelper { h, resolve, _ in
            h.helperVersion { version in resolve(version) }
        }
    }

    // sysadminctl can legitimately take minutes — killing a user's live
    // processes, SecureToken authorisation, and large home folders all add
    // real time. A short timeout here doesn't mean the operation failed, only
    // that the app gave up waiting, so these use a much longer budget.
    private static let longOperationTimeout: Double = 300

    func deleteUser(_ username: String, keepHome: Bool,
                    adminUser: String = "", adminPassword: String = "") async throws {
        try await callHelper(timeout: Self.longOperationTimeout) { h, resolve, reject in
            h.deleteUser(username, keepHome: keepHome,
                         adminUser: adminUser, adminPassword: adminPassword) { success, error in
                if success { resolve(()) }
                else { reject(HelperClientError.commandFailed(error ?? "sysadminctl failed")) }
            }
        }
    }

    func deleteHomeFolder(_ path: String) async throws {
        try await callHelper(timeout: Self.longOperationTimeout) { h, resolve, reject in
            h.deleteHomeFolder(path) { success, error in
                if success { resolve(()) }
                else { reject(HelperClientError.commandFailed(error ?? "rm failed")) }
            }
        }
    }

    func resetPassword(username: String, newPassword: String,
                       adminUser: String = "", adminPassword: String = "") async throws {
        try await callHelper(timeout: Self.longOperationTimeout) { h, resolve, reject in
            h.resetPassword(username: username, newPassword: newPassword,
                            adminUser: adminUser, adminPassword: adminPassword) { success, error in
                if success { resolve(()) }
                else { reject(HelperClientError.commandFailed(error ?? "Password reset failed")) }
            }
        }
    }

    func getHomeSize(_ path: String) async throws -> Int64 {
        try await callHelper { h, resolve, _ in
            h.homeSize(path: path) { size in resolve(size) }
        }
    }

}

// MARK: - Errors

enum HelperClientError: LocalizedError {
    case helperNotRunning
    case connectionFailed
    case timedOut
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperNotRunning:
            return "The privileged helper isn't installed or approved yet. Open Settings → Security & Lock, or System Settings → General → Login Items & Extensions, and approve \"Account Manager Helper\", then try again."
        case .connectionFailed:
            return "Could not connect to the privileged helper. Try reinstalling Account Manager."
        case .timedOut:
            return "The privileged helper didn't respond in time. It may have crashed — try reopening Account Manager."
        case .commandFailed(let detail):
            return "Helper command failed: \(detail)"
        }
    }
}
