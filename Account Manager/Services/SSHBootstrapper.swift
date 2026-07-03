//
//  SSHBootstrapper.swift
//  Account Manager
//
//  One-time setup: generates an SSH key (if needed), copies it to a remote Mac
//  via password auth, and writes a passwordless-sudo rule — all without leaving
//  the app. Uses SSH_ASKPASS + SSH_ASKPASS_REQUIRE=force (OpenSSH 8.4+, which
//  ships with macOS Ventura / Sonoma) so no expect or sshpass is needed.
//

import Foundation

// MARK: - Errors

enum BootstrapError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        if case .failed(let m) = self { return m }
        return "Bootstrap failed"
    }
}

// MARK: - SSHBootstrapper

final class SSHBootstrapper {

    static let accountManagerKeyPath    = "~/.ssh/id_accountmanager"
    static let accountManagerKeyComment = "AccountManager"

    // MARK: - Key generation

    /// Returns the public-key string, generating a new key pair if one doesn't exist.
    /// Runs synchronous work on a background thread so it's safe to call from the main actor.
    static func publicKey() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let expanded = expand(accountManagerKeyPath)
                    let pubPath  = expanded + ".pub"
                    if !FileManager.default.fileExists(atPath: expanded) {
                        let args = ["-t", "ed25519", "-f", expanded, "-N", "", "-C", accountManagerKeyComment]
                        let out  = try runSync("/usr/bin/ssh-keygen", args: args)
                        if !FileManager.default.fileExists(atPath: pubPath) {
                            throw BootstrapError.failed("Key generation failed: \(out)")
                        }
                    }
                    let key = try String(contentsOfFile: pubPath, encoding: .utf8)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: key)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Bootstrap

    /// Connects to the remote Mac with a one-time admin password and:
    ///   1. Adds the AccountManager public key to ~/.ssh/authorized_keys
    ///   2. Writes a passwordless sudo rule to /etc/sudoers.d/10-accountmanager
    ///
    /// Progress strings are delivered on the main actor via `log`.
    static func bootstrap(hostname: String, port: Int,
                          username: String, password: String,
                          log: @escaping @MainActor (String) -> Void) async throws {

        let pubKey = try await publicKey()

        // Build askpass helper in a private temp dir (deleted on exit)
        let tmpDir      = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("acctmgr-bootstrap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let askpassURL  = tmpDir.appendingPathComponent("askpass.sh")
        // Print password from env var — no newline needed for newer OpenSSH
        try "#!/bin/sh\necho \"$_ACCTMGR_PW\"\n"
            .write(to: askpassURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o700))],
                                               ofItemAtPath: askpassURL.path)

        // Escape single-quote characters for safe shell embedding
        let safeKey  = pubKey.replacingOccurrences(of: "'", with: "'\\''")
        let safePw   = password.replacingOccurrences(of: "'", with: "'\\''")
        let safeUser = username.replacingOccurrences(of: "'", with: "'\\''")

        // ── Step 1: install SSH key ────────────────────────────────────────────
        log("Connecting to \(hostname)...")

        let keyCmd = """
        mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
        (grep -qF '\(safeKey)' ~/.ssh/authorized_keys 2>/dev/null || \
         printf '%s\\n' '\(safeKey)' >> ~/.ssh/authorized_keys) && \
        chmod 600 ~/.ssh/authorized_keys && echo __KEY_OK__
        """

        let keyOut = try await runSSH(hostname: hostname, port: port, username: username,
                                      command: keyCmd, password: password,
                                      askpassPath: askpassURL.path)

        guard keyOut.contains("__KEY_OK__") else {
            throw BootstrapError.failed("Could not install SSH key.\n\nOutput: \(keyOut.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        log("SSH key installed.")

        // ── Step 2: configure passwordless sudo ───────────────────────────────
        log("Configuring sudo access...")

        let sudoContent  = "\(safeUser) ALL=(ALL) NOPASSWD: ALL"
        let sudoCmd = """
        printf '%s\\n' '\(safePw)' | sudo -S sh -c \
        "printf '%s\\n' '\(sudoContent)' > /etc/sudoers.d/10-accountmanager && \
         chmod 440 /etc/sudoers.d/10-accountmanager && echo __SUDO_OK__"
        """

        let sudoOut = try await runSSH(hostname: hostname, port: port, username: username,
                                       command: sudoCmd, password: password,
                                       askpassPath: askpassURL.path)

        guard sudoOut.contains("__SUDO_OK__") else {
            throw BootstrapError.failed("Could not configure sudo.\nMake sure '\(username)' can run sudo.\n\nOutput: \(sudoOut.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        log("Passwordless sudo configured.")

        // ── Step 3: verify key-based login works ──────────────────────────────
        log("Verifying key-based login...")

        let host   = RemoteHost(label: "", hostname: hostname,
                                sshUser: username, sshKeyPath: accountManagerKeyPath, port: port)
        let runner = SSHRunner(host: host)
        guard await runner.testConnection() else {
            throw BootstrapError.failed("Setup completed but key-based login test failed. Check that Remote Login is enabled on the remote Mac (System Settings → General → Sharing).")
        }

        log("Setup complete — key-based login verified.")
    }

    // MARK: - Internals

    private static func runSSH(hostname: String, port: Int,
                                username: String, command: String,
                                password: String, askpassPath: String) async throws -> String {
        var env                        = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"]             = askpassPath
        env["SSH_ASKPASS_REQUIRE"]     = "force"
        env["DISPLAY"]                 = ":0"          // triggers askpass on older OpenSSH
        env["_ACCTMGR_PW"]            = password       // read by askpass.sh

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = [
                    "-p", "\(port)",
                    "-o", "StrictHostKeyChecking=no",
                    "-o", "PasswordAuthentication=yes",
                    "-o", "PreferredAuthentications=keyboard-interactive,password",
                    "-o", "NumberOfPasswordPrompts=1",
                    "-o", "ConnectTimeout=15",
                    "\(username)@\(hostname)",
                    command
                ]
                process.environment = env
                let out = Pipe(); let err = Pipe()
                process.standardOutput = out
                process.standardError  = err
                do {
                    try process.run()
                    process.waitUntilExit()
                    let outStr = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    // Return combined output; caller checks for markers
                    continuation.resume(returning: outStr + errStr)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runSync(_ path: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments     = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = Pipe()
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static func expand(_ path: String) -> String {
        path.replacingOccurrences(of: "~", with: NSHomeDirectory())
    }
}
