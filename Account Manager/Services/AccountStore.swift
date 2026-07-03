//
//  AccountStore.swift
//  Account Manager
//
//  Enumerates macOS user accounts via dscl, applies ProtectedPolicy,
//  and publishes the resulting [UserAccount] list.
//  Pass an SSHRunner to load from a remote Mac instead of the local one.
//

import Foundation
import Observation

/// Error carrying a user-facing message from a reset/command failure.
enum ResetError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

@Observable
final class AccountStore {

    var accounts: [UserAccount] = []
    var isLoading: Bool = false
    var isLoadingHomeSizes: Bool = false
    var loadError: String? = nil

    let sshRunner: SSHRunner?   // nil = local

    private let policy: ProtectedPolicy
    private let config:  Config

    init(config: Config = .shared, sshRunner: SSHRunner? = nil) {
        self.config    = config
        self.sshRunner = sshRunner
        // For remote sessions the SSH user is effectively "logged in" and
        // should be treated as sessionLocked (visible but not deletable).
        self.policy = ProtectedPolicy(config: config,
                                      operatorOverride: sshRunner?.host.sshUser)
    }

    // MARK: - Reload entry point

    func reload() async {
        await MainActor.run { isLoading = true; loadError = nil }
        do {
            if let runner = sshRunner {
                try await reloadRemote(runner: runner)
            } else {
                try await reloadLocal()
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Local load

    private func reloadLocal() async throws {
        let raw          = try await enumerateRaw()
        let adminMembers = (try? await fetchAdminGroupMembers()) ?? []
        let displayNames = (try? await fetchDisplayNamesLocal()) ?? [:]
        let authOutput   = (try? await runCommand("/usr/bin/dscl", args: [".", "-list", "/Users", "AuthenticationAuthority"])) ?? ""
        let lockedAccounts = parseLockedAccounts(authOutput)
        let loggedInUIDs = await fetchLoggedInUIDs()
        let built        = raw.map { buildAccount(name: $0.name, uid: $0.uid, adminMembers: adminMembers, displayNames: displayNames, lockedAccounts: lockedAccounts, loggedInUIDs: loggedInUIDs) }

        var result = built
        await MainActor.run {
            accounts  = result
            isLoading = false
            isLoadingHomeSizes = true
        }

        for i in result.indices {
            let size = await measureHomeSize(path: result[i].homePath)
            result[i].homeSize = size
            let captured = result[i]
            await MainActor.run {
                if let idx = accounts.firstIndex(where: { $0.id == captured.id }) {
                    accounts[idx].homeSize = size
                }
            }
        }

        await MainActor.run { isLoadingHomeSizes = false }
    }

    private func buildAccount(name: String, uid: Int, adminMembers: Set<String>,
                              displayNames: [String: String] = [:],
                              lockedAccounts: Set<String> = [],
                              loggedInUIDs: Set<Int> = []) -> UserAccount {
        let homePath  = "/Users/\(name)"
        let homeExists = FileManager.default.fileExists(atPath: homePath)
        var (tier, reason) = policy.protectionTier(username: name, uid: uid)
        // Lock accounts with an active local session — their home is in use and
        // can't be deleted, and resets/deletions on a live user are unsafe.
        if tier == .none && loggedInUIDs.contains(uid) {
            tier   = .sessionLocked
            reason = "User is currently logged in on this Mac"
        }
        return UserAccount(
            id: name, username: name, displayName: displayNames[name],
            uid: uid,
            homePath: homePath, homeExists: homeExists, homeSize: nil,
            isProtected: tier != .none, protectionTier: tier, protectionReason: reason,
            isActuallyAdmin: adminMembers.contains(name),
            isPasswordLocked: lockedAccounts.contains(name)
        )
    }

    /// UIDs with an active local GUI session. Every logged-in user (including
    /// fast-user-switched ones) has their own `loginwindow` process, so we map
    /// those back to UIDs. Used to lock live accounts from deletion/reset.
    private func fetchLoggedInUIDs() async -> Set<Int> {
        let output = (try? await runCommand("/bin/ps", args: ["-axo", "uid,comm"])) ?? ""
        var uids: Set<Int> = []
        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, let uid = Int(parts[0]), uid >= 500 else { continue }
            let comm = parts[1...].joined(separator: " ")
            if comm.hasSuffix("loginwindow") { uids.insert(uid) }
        }
        return uids
    }

    private func fetchAdminGroupMembers() async throws -> Set<String> {
        let output = try await runCommand("/usr/bin/dscl", args: [
            ".", "-read", "/Groups/admin", "GroupMembership"
        ])
        return parseAdminGroupOutput(output)
    }

    private func fetchDisplayNamesLocal() async throws -> [String: String] {
        let output = try await runCommand("/usr/bin/dscl", args: [".", "-list", "/Users", "RealName"])
        return parseDisplayNames(output)
    }

    private func enumerateRaw() async throws -> [(name: String, uid: Int)] {
        let output = try await runCommand("/usr/bin/dscl", args: [".", "-list", "/Users", "UniqueID"])
        return parseUserList(output)
    }

    private func measureHomeSize(path: String) async -> Int64? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        if HelperClient.shared.isRunning,
           let size = try? await HelperClient.shared.getHomeSize(path) {
            return size > 0 ? size : nil
        }
        return await Task.detached(priority: .utility) {
            var total: Int64 = 0
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return nil }
            while let obj = enumerator.nextObject() {
                if let url = obj as? URL,
                   let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
            return total > 0 ? total : nil
        }.value
    }

    // MARK: - Password reset

    /// Resets the password for the given account and clears any DisabledUser lock.
    /// For remote hosts the command runs over SSH; for local it goes through the privileged helper
    /// (which runs as root) to avoid blocking on stdin auth that dscl prompts for as a non-root user.
    /// When `isDryRun` is true the call succeeds immediately without making any changes.
    func resetPassword(for account: UserAccount, newPassword: String,
                       adminUser: String = "", adminPassword: String = "",
                       isDryRun: Bool = false, reloadAfter: Bool = true) async throws {
        if isDryRun { return }
        let username = account.username
        if let runner = sshRunner {
            // Use sysadminctl (not `dscl -passwd`) — dscl reports success but does
            // NOT sync a SecureToken/FileVault account's login credential, so the
            // login window rejects the new password. sysadminctl resets it properly
            // and, for SecureToken accounts, accepts a SecureToken admin's creds.
            func esc(_ s: String) -> String { s.replacingOccurrences(of: "'", with: "'\\''") }
            var cmd = "sudo sysadminctl -resetPasswordFor \(username) -newPassword '\(esc(newPassword))'"
            if !adminUser.isEmpty && !adminPassword.isEmpty {
                cmd += " -adminUser '\(esc(adminUser))' -adminPassword '\(esc(adminPassword))'"
            }
            cmd += " 2>&1"
            let output = try await runner.run(cmd)
            let lower = output.lowercased()
            if lower.contains("secure token") {
                throw ResetError.message("This account has a SecureToken (FileVault). Enter a SecureToken administrator's name and password to authorise the reset.")
            }
            if lower.contains("error") || lower.contains("not permitted") || lower.contains("failed") || lower.contains("unable to") {
                throw ResetError.message(output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            // Clear any DisabledUser lockout (best-effort — ignore failure).
            _ = try? await runner.run("sudo dscl . -delete /Users/\(username) AuthenticationAuthority ';DisabledUser;' 2>/dev/null; true")
        } else {
            try await HelperClient.shared.resetPassword(
                username: username, newPassword: newPassword,
                adminUser: adminUser, adminPassword: adminPassword)
        }
        // Skipped during batch runs so the account list refreshes only once, after
        // every action finishes (see runActions).
        if reloadAfter { await reload() }
    }

    // MARK: - Remote load

    private func reloadRemote(runner: SSHRunner) async throws {
        let raw          = try await enumerateRawRemote(runner: runner)
        let adminMembers = (try? await fetchAdminGroupMembersRemote(runner: runner)) ?? []
        let displayNames = (try? await fetchDisplayNamesRemote(runner: runner)) ?? [:]

        // Check which home folders exist on the remote in one ls call
        let homeListing = (try? await runner.run("ls /Users 2>/dev/null")) ?? ""
        let existingHomes: Set<String> = Set(
            homeListing.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )

        // Detect users with active GUI/console sessions on the remote Mac
        let whoOutput = (try? await runner.run("who | awk '{print $1}' | sort -u 2>/dev/null")) ?? ""
        let loggedIn: Set<String> = Set(
            whoOutput.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )

        // Detect accounts locked due to failed password attempts
        let authOutput = (try? await runner.run("dscl . -list /Users AuthenticationAuthority 2>/dev/null")) ?? ""
        let lockedAccounts = parseLockedAccounts(authOutput)

        var result = raw.map {
            buildAccountRemote(name: $0.name, uid: $0.uid,
                               adminMembers: adminMembers,
                               existingHomes: existingHomes,
                               displayNames: displayNames,
                               loggedIn: loggedIn,
                               lockedAccounts: lockedAccounts)
        }

        await MainActor.run {
            accounts  = result
            isLoading = false
            isLoadingHomeSizes = true
        }

        // Measure all home sizes at once with a single du call.
        // Try without sudo first (works if SSH user is admin); fall back to
        // sudo -n (non-interactive) for setups where passwordless sudo is configured.
        let duOutput = (try? await runner.run("du -sk /Users/* 2>/dev/null || sudo -n du -sk /Users/* 2>/dev/null")) ?? ""
        var sizeMap: [String: Int64] = [:]
        for line in duOutput.components(separatedBy: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count == 2,
                  let kb = Int64(parts[0].trimmingCharacters(in: .whitespaces))
            else { continue }
            let username = URL(fileURLWithPath: String(parts[1].trimmingCharacters(in: .whitespaces))).lastPathComponent
            sizeMap[username] = kb * 1024
        }

        for i in result.indices {
            if let bytes = sizeMap[result[i].username] {
                result[i].homeSize = bytes > 0 ? bytes : nil
                let captured = result[i]
                await MainActor.run {
                    if let idx = accounts.firstIndex(where: { $0.id == captured.id }) {
                        accounts[idx].homeSize = captured.homeSize
                    }
                }
            }
        }

        await MainActor.run { isLoadingHomeSizes = false }
    }

    private func buildAccountRemote(name: String, uid: Int,
                                     adminMembers: Set<String>,
                                     existingHomes: Set<String>,
                                     displayNames: [String: String] = [:],
                                     loggedIn: Set<String> = [],
                                     lockedAccounts: Set<String> = []) -> UserAccount {
        var (tier, reason) = policy.protectionTier(username: name, uid: uid)
        // If account has an active GUI session, mark sessionLocked so it shows
        // the orange lock icon and can't be deleted while someone is using it.
        if tier == .none && loggedIn.contains(name) {
            tier   = .sessionLocked
            reason = "User is currently logged in on this Mac"
        }
        return UserAccount(
            id: name, username: name, displayName: displayNames[name],
            uid: uid,
            homePath: "/Users/\(name)",
            homeExists: existingHomes.contains(name),
            homeSize: nil,
            isProtected: tier != .none, protectionTier: tier, protectionReason: reason,
            isActuallyAdmin: adminMembers.contains(name),
            isPasswordLocked: lockedAccounts.contains(name)
        )
    }

    private func enumerateRawRemote(runner: SSHRunner) async throws -> [(name: String, uid: Int)] {
        let output = try await runner.run("dscl . -list /Users UniqueID")
        return parseUserList(output)
    }

    private func fetchAdminGroupMembersRemote(runner: SSHRunner) async throws -> Set<String> {
        let output = try await runner.run("dscl . -read /Groups/admin GroupMembership")
        return parseAdminGroupOutput(output)
    }

    private func fetchDisplayNamesRemote(runner: SSHRunner) async throws -> [String: String] {
        let output = try await runner.run("dscl . -list /Users RealName")
        return parseDisplayNames(output)
    }

    // MARK: - Shared parsers

    private func parseUserList(_ output: String) -> [(name: String, uid: Int)] {
        var result: [(String, Int)] = []
        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let uid = Int(parts[parts.count - 1]) else { continue }
            result.append((String(parts[0]), uid))
        }
        return result
    }

    private func parseDisplayNames(_ output: String) -> [String: String] {
        var map: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let spaceRange = trimmed.range(of: #"\s+"#, options: .regularExpression)
            else { continue }
            let username    = String(trimmed[trimmed.startIndex..<spaceRange.lowerBound])
            let displayName = String(trimmed[spaceRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !displayName.isEmpty { map[username] = displayName }
        }
        return map
    }

    private func parseLockedAccounts(_ output: String) -> Set<String> {
        var locked = Set<String>()
        for line in output.components(separatedBy: "\n") {
            guard line.contains("DisabledUser") else { continue }
            if let username = line.split(separator: " ", omittingEmptySubsequences: true).first {
                locked.insert(String(username))
            }
        }
        return locked
    }

    private func parseAdminGroupOutput(_ output: String) -> Set<String> {
        let line = output.components(separatedBy: "\n")
            .first(where: { $0.hasPrefix("GroupMembership:") }) ?? ""
        let members = line
            .replacingOccurrences(of: "GroupMembership:", with: "")
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        return Set(members)
    }
}

// MARK: - Shell helper (shared with SSHRunner via runCommand free function)

func runCommand(_ path: String, args: [String]) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = Pipe()
            process.standardInput  = FileHandle.nullDevice
            do {
                try process.run()
                // Read to EOF BEFORE waiting. If we wait first, a command whose
                // output exceeds the pipe buffer (e.g. `ps -axo`) blocks writing
                // and waitUntilExit() hangs forever. Draining the pipe as the
                // process writes avoids that deadlock.
                let data   = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
