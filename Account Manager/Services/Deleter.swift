//
//  Deleter.swift
//  Account Manager
//
//  Deletion engine — local via privileged XPC helper, remote via SSH + sudo.
//

import Foundation

// MARK: - Result type

struct DeletionResult {
    let username: String
    let displayName: String?
    let mode: DeletionMode
    let fileMethod: FileDeletionMethod
    let success: Bool
    let error: String?
}

// MARK: - Errors

enum DeleterError: LocalizedError {
    case helperNotInstalled
    case toolFailed(String)
    var errorDescription: String? {
        switch self {
        case .helperNotInstalled:
            return "The privileged helper is not installed. Please reinstall Account Manager."
        case .toolFailed(let detail):
            return "Deletion tool failed: \(detail)"
        }
    }
}

// MARK: - Deleter

final class Deleter {

    let config:    Config
    let sshRunner: SSHRunner?   // nil = local, non-nil = remote via SSH
    var isDryRun:  Bool = false
    // SecureToken admin credentials for deleting FileVault/SecureToken accounts.
    var adminUser:     String = ""
    var adminPassword: String = ""

    init(config: Config = .shared, sshRunner: SSHRunner? = nil) {
        self.config    = config
        self.sshRunner = sshRunner
    }

    // MARK: - Delete one account

    func delete(_ account: UserAccount, fileMethod: FileDeletionMethod) async -> DeletionResult {
        let mode = account.deletionMode

        let displayName = account.displayName

        if isDryRun {
            return DeletionResult(username: account.username, displayName: displayName,
                                  mode: mode, fileMethod: fileMethod, success: true, error: nil)
        }

        do {
            switch mode {
            case .accountAndFiles:
                try await deleteAccountRecord(account.username)
                if account.homeExists {
                    try await deleteHome(account, method: fileMethod)
                }
            case .accountOnly:
                try await deleteAccountRecordKeepHome(account.username)
            case .filesOnly:
                if account.homeExists {
                    try await deleteHome(account, method: fileMethod)
                }
            case .resetPassword:
                break  // handled by AccountStore.resetPassword — should not reach here
            }
            return DeletionResult(username: account.username, displayName: displayName,
                                  mode: mode, fileMethod: fileMethod, success: true, error: nil)
        } catch {
            return DeletionResult(username: account.username, displayName: displayName,
                                  mode: mode, fileMethod: fileMethod, success: false,
                                  error: error.localizedDescription)
        }
    }

    // MARK: - Delete a batch

    func deleteBatch(_ accounts: [UserAccount],
                     fileMethod: FileDeletionMethod,
                     progress: @escaping @Sendable (String) async -> Void) async -> [DeletionResult] {
        var results: [DeletionResult] = []
        for account in accounts {
            await progress(account.username)
            let result = await delete(account, fileMethod: fileMethod)
            results.append(result)
        }
        return results
    }

    // MARK: - Account record deletion

    /// `-adminUser/-adminPassword` arguments for sysadminctl over SSH, when the
    /// operator supplied SecureToken admin credentials (empty otherwise).
    private var remoteAdminArgs: String {
        guard !adminUser.isEmpty, !adminPassword.isEmpty else { return "" }
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "'", with: "'\\''") }
        return " -adminUser '\(esc(adminUser))' -adminPassword '\(esc(adminPassword))'"
    }

    private func deleteAccountRecord(_ username: String) async throws {
        if let runner = sshRunner {
            _ = try await runner.run("sudo sysadminctl -deleteUser \(username) -secure\(remoteAdminArgs) 2>&1")
        } else if config.useLegacyDeletionTool {
            try await legacyDeleteAccountRecord(username)
        } else {
            try await HelperClient.shared.deleteUser(username, keepHome: false,
                                                     adminUser: adminUser, adminPassword: adminPassword)
        }
    }

    private func deleteAccountRecordKeepHome(_ username: String) async throws {
        if let runner = sshRunner {
            _ = try await runner.run("sudo sysadminctl -deleteUser \(username) -keepHome\(remoteAdminArgs) 2>&1")
        } else {
            try await HelperClient.shared.deleteUser(username, keepHome: true,
                                                     adminUser: adminUser, adminPassword: adminPassword)
        }
    }

    private func deleteHome(_ account: UserAccount, method: FileDeletionMethod) async throws {
        if let runner = sshRunner {
            _ = try await runner.run("sudo rm -rf '\(account.homePath)' 2>&1")
        } else {
            try await HelperClient.shared.deleteHomeFolder(account.homePath)
        }
    }

    // MARK: - Legacy fallback (local only)

    private func legacyDeleteAccountRecord(_ username: String) async throws {
        let output = try await runCommand("/usr/bin/dscl", args: [
            ".", "-delete", "/Users/\(username)"
        ])
        if output.lowercased().contains("error") {
            throw DeleterError.toolFailed(output)
        }
    }
}
