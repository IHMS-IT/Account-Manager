//
//  SecurityManager.swift
//  Account Manager
//
//  Cross-account PIN/security lock stored at /Users/Shared/.ihms_am_security.json.
//  The file is created with 644 permissions so all local user accounts can read it,
//  but only the user who created it (the admin who first set the PIN) can overwrite it.
//  The sticky bit on /Users/Shared/ (1777) prevents other users from deleting it.
//

import Foundation
import CryptoKit
import Observation

@Observable
final class SecurityManager {

    static let shared = SecurityManager()

    // MARK: - Storage

    private let storagePath = "/Users/Shared/.ihms_am_security.json"

    struct SecurityConfig: Codable {
        var pinHash:         String?
        var securityPinHash: String?
        var lockedFeatures:  [String] = []
    }

    // MARK: - Published state

    private(set) var config = SecurityConfig()
    private(set) var isLoaded = false

    var isPinEnabled:       Bool { config.pinHash != nil }
    // A feature lock is only in effect while a PIN actually exists — a lock with
    // no PIN would be impossible to satisfy, so guard every lock on isPinEnabled.
    var isRemoteHostLocked: Bool { isPinEnabled && config.lockedFeatures.contains("remoteHosts") }
    var isSettingsLocked:   Bool { isPinEnabled && config.lockedFeatures.contains("settings") }
    /// When enabled, the PIN must be entered every time the app launches.
    var isLaunchLocked:     Bool { isPinEnabled && config.lockedFeatures.contains("launch") }

    // MARK: - Init

    private init() { load() }

    // MARK: - Load

    func load() {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: storagePath)),
            let loaded = try? JSONDecoder().decode(SecurityConfig.self, from: data)
        else {
            config = SecurityConfig()
            isLoaded = true
            return
        }
        config = loaded
        isLoaded = true
    }

    // MARK: - Verification

    func verify(pin: String) -> Bool {
        guard let hash = config.pinHash else { return true }   // no PIN set = always pass
        return sha256(pin) == hash
    }

    func verifySecurityPin(_ pin: String) -> Bool {
        guard let hash = config.securityPinHash else { return false }
        return sha256(pin) == hash
    }

    // MARK: - Mutation (requires write access to /Users/Shared/)

    /// Sets a new PIN and recovery PIN. Fails if the file cannot be written (no write access).
    func setPin(_ pin: String, securityPin: String) throws {
        var newConfig = config
        newConfig.pinHash         = sha256(pin)
        newConfig.securityPinHash = sha256(securityPin)
        try save(newConfig)
    }

    /// Changes the PIN. Requires the current PIN AND the recovery PIN.
    func changePin(currentPin: String, securityPin: String, newPin: String) throws {
        guard verify(pin: currentPin) else     { throw SecurityError.wrongPin }
        guard verifySecurityPin(securityPin) else { throw SecurityError.wrongSecurityPin }
        var newConfig = config
        newConfig.pinHash = sha256(newPin)
        try save(newConfig)
    }

    /// Removes the PIN entirely. Requires the current PIN AND the recovery PIN.
    /// Also clears all feature locks — a lock is meaningless without a PIN.
    func clearPin(currentPin: String, securityPin: String) throws {
        guard verify(pin: currentPin) else     { throw SecurityError.wrongPin }
        guard verifySecurityPin(securityPin) else { throw SecurityError.wrongSecurityPin }
        var newConfig = config
        newConfig.pinHash         = nil
        newConfig.securityPinHash = nil
        newConfig.lockedFeatures  = []
        try save(newConfig)
    }

    /// Locks or unlocks a named feature. PIN must already be enabled.
    func setFeatureLocked(_ feature: String, locked: Bool) throws {
        var newConfig = config
        if locked {
            if !newConfig.lockedFeatures.contains(feature) {
                newConfig.lockedFeatures.append(feature)
            }
        } else {
            newConfig.lockedFeatures.removeAll { $0 == feature }
        }
        try save(newConfig)
    }

    // MARK: - Private helpers

    private func save(_ newConfig: SecurityConfig) throws {
        let data = try JSONEncoder().encode(newConfig)
        let url  = URL(fileURLWithPath: storagePath)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644 as UInt16)],
            ofItemAtPath: storagePath
        )
        config = newConfig
    }

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Errors

    enum SecurityError: LocalizedError {
        case wrongPin
        case wrongSecurityPin
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .wrongPin:            return "Incorrect PIN — try again."
            case .wrongSecurityPin:    return "Incorrect recovery PIN — try again."
            case .writeFailed(let m):  return "Could not save security settings: \(m)"
            }
        }
    }
}
