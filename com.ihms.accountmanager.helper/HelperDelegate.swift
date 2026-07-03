//
//  HelperDelegate.swift
//  com.ihms.accountmanager.helper
//
//  Runs as root. Implements AccountManagerHelperProtocol over XPC.
//  Every method validates its inputs before touching the filesystem.
//

import Foundation

final class HelperDelegate: NSObject, NSXPCListenerDelegate, AccountManagerHelperProtocol {

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: AccountManagerHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    // MARK: - AccountManagerHelperProtocol

    func deleteUser(_ username: String,
                    keepHome: Bool,
                    adminUser: String,
                    adminPassword: String,
                    withReply reply: @escaping (Bool, String?) -> Void) {
        guard isValidUsername(username) else {
            reply(false, "Invalid username: \(username)")
            return
        }

        // Idempotent: if the record is already gone, report success.
        guard userRecordExists(username) else {
            reply(true, nil)
            return
        }

        // Primary path: sysadminctl. It can return exit 0 while leaving the
        // record behind, so we don't trust its status — we verify afterwards.
        // SecureToken (FileVault) accounts require a SecureToken admin to
        // authorise deletion, supplied via -adminUser / -adminPassword.
        var args = ["-deleteUser", username]
        if keepHome { args.append("-keepHome") }
        if !adminUser.isEmpty && !adminPassword.isEmpty, isValidUsername(adminUser) {
            args += ["-adminUser", adminUser, "-adminPassword", adminPassword]
        }
        let sysResult = capture("/usr/sbin/sysadminctl", args: args)

        if !recordExistsWithRetry(username) {
            reply(true, nil)
            return
        }

        // Fallback: delete the directory record outright with dscl (works for
        // accounts without a SecureToken).
        let dsclResult = capture("/usr/bin/dscl", args: [".", "-delete", "/Users/\(username)"])

        if !recordExistsWithRetry(username) {
            reply(true, nil)
            return
        }

        // Still present — surface a clear cause. SecureToken/FileVault accounts
        // need an admin's credentials to be removed.
        let combined = (sysResult.output + " " + dsclResult.output).lowercased()
        if combined.contains("secure token") || combined.contains("securetoken")
            || combined.contains("fde") || combined.contains("-14120")
            || combined.contains("edspermission") {
            reply(false, "This account has a SecureToken (FileVault). Enter a SecureToken administrator's name and password to authorise deleting it.")
        } else {
            reply(false, "Account record for \(username) could not be removed. "
                + "sysadminctl: \(sysResult.trimmed) | dscl: \(dsclResult.trimmed)")
        }
    }

    /// True if a local user record still exists for the given name.
    private func userRecordExists(_ username: String) -> Bool {
        let r = capture("/usr/bin/dscl", args: [".", "-read", "/Users/\(username)", "RecordName"])
        return r.status == 0
    }

    /// Same check, but retries briefly. opendirectoryd can take a moment to
    /// propagate a deletion, so checking exactly once right after sysadminctl
    /// exits can report a false "still exists" even though the deletion succeeded.
    private func recordExistsWithRetry(_ username: String, attempts: Int = 5, delayMs: UInt32 = 300) -> Bool {
        for attempt in 0..<attempts {
            if !userRecordExists(username) { return false }
            if attempt < attempts - 1 { usleep(delayMs * 1000) }
        }
        return true
    }

    func deleteHomeFolder(_ path: String,
                          withReply reply: @escaping (Bool, String?) -> Void) {
        guard isValidHomePath(path) else {
            reply(false, "Refusing to delete non-/Users/ path: \(path)")
            return
        }
        run("/bin/rm", args: ["-rf", path], reply: reply)
    }

    func helperVersion(withReply reply: @escaping (String) -> Void) {
        reply(helperBundledVersion)
    }

    func quitHelper(withReply reply: @escaping (Bool) -> Void) {
        reply(true)
        // Give the reply time to flush, then exit. launchd relaunches the (now
        // updated) binary on the next XPC connection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exit(0)
        }
    }

    func resetPassword(username: String,
                       newPassword: String,
                       adminUser: String,
                       adminPassword: String,
                       withReply reply: @escaping (Bool, String?) -> Void) {
        guard isValidUsername(username) else {
            reply(false, "Invalid username: \(username)")
            return
        }

        // Reset the password with sysadminctl. For accounts WITHOUT a SecureToken,
        // the plain root form works. For SecureToken (FileVault) accounts, macOS
        // requires a SecureToken admin to authorise it, so include -adminUser /
        // -adminPassword when the caller supplied them.
        var args = ["-resetPasswordFor", username, "-newPassword", newPassword]
        if !adminUser.isEmpty && !adminPassword.isEmpty {
            guard isValidUsername(adminUser) else {
                reply(false, "Invalid administrator username: \(adminUser)")
                return
            }
            args += ["-adminUser", adminUser, "-adminPassword", adminPassword]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysadminctl")
        process.arguments = args
        let errPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError  = errPipe
        process.standardInput  = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            reply(false, error.localizedDescription)
            return
        }

        // sysadminctl logs to stderr even on success, so detect real failures by
        // exit code and known error phrases rather than any output at all.
        let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lower = errStr.lowercased()
        let failed = process.terminationStatus != 0
            || lower.contains("failed")
            || lower.contains("error")
            || lower.contains("not permitted")
            || lower.contains("could not")
        if failed {
            // Give a clearer hint for the common SecureToken case.
            let detail: String
            if lower.contains("secure token") {
                detail = "This account has a SecureToken (FileVault). Enter a SecureToken administrator's name and password to authorise the reset."
            } else {
                detail = errStr.isEmpty
                    ? "sysadminctl exited with status \(process.terminationStatus)"
                    : errStr
            }
            reply(false, detail)
            return
        }

        // Clear any DisabledUser lockout (best-effort — ignore failure)
        let unlock = Process()
        unlock.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        unlock.arguments = [".", "-delete", "/Users/\(username)", "AuthenticationAuthority", ";DisabledUser;"]
        unlock.standardOutput = Pipe()
        unlock.standardError  = Pipe()
        unlock.standardInput  = FileHandle.nullDevice
        try? unlock.run()
        unlock.waitUntilExit()

        reply(true, nil)
    }

    func homeSize(path: String, withReply reply: @escaping (Int64) -> Void) {
        guard isValidHomePath(path) else { reply(0); return }
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        ) else { reply(0); return }
        while let obj = enumerator.nextObject() {
            if let url = obj as? URL,
               let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        reply(total)
    }

    // MARK: - Validation

    private func isValidUsername(_ username: String) -> Bool {
        guard !username.isEmpty, username.count < 256 else { return false }
        // Only allow alphanumeric, underscore, hyphen, period
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
        return username.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func isValidHomePath(_ path: String) -> Bool {
        // Must be exactly /Users/<something> — no traversal, no nested paths
        let components = path.components(separatedBy: "/")
        guard components.count == 3,
              components[0] == "",
              components[1] == "Users",
              !components[2].isEmpty else { return false }
        return isValidUsername(components[2])
    }

    // MARK: - Process runner

    private func run(_ executablePath: String,
                     args: [String],
                     reply: @escaping (Bool, String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                reply(true, nil)
            } else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr  = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "Exit code \(process.terminationStatus)"
                reply(false, errStr)
            }
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    // MARK: - Synchronous capture runner

    struct CaptureResult {
        let status: Int32
        let output: String
        var trimmed: String { output.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Runs a process synchronously and captures combined stdout+stderr and exit code.
    @discardableResult
    private func capture(_ executablePath: String, args: [String]) -> CaptureResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe
        process.standardInput  = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let out = String(data: data, encoding: .utf8) ?? ""
            return CaptureResult(status: process.terminationStatus, output: out)
        } catch {
            return CaptureResult(status: -1, output: error.localizedDescription)
        }
    }
}
