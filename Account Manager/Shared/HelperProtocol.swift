//
//  HelperProtocol.swift
//  Account Manager + com.ihms.accountmanager.helper
//
//  IMPORTANT: Add this file to BOTH the main app target and the helper target.
//  The @objc name must match exactly on both sides of the XPC connection.
//

import Foundation

let helperMachServiceName = "com.ihms.accountmanager.helper"

/// Version of the helper's *behaviour*, compiled into BOTH the app and the helper.
/// Bump this whenever the helper's code changes so the app detects that a
/// previously-registered daemon is stale and re-registers the new binary.
let helperBundledVersion = "6"

@objc(AccountManagerHelperProtocol)
protocol AccountManagerHelperProtocol {
    /// Delete a user account. Pass keepHome: true to leave /Users/<name> on disk.
    /// SecureToken (FileVault) accounts need a SecureToken admin's credentials to
    /// authorise deletion — pass adminUser/adminPassword (empty otherwise).
    func deleteUser(_ username: String,
                    keepHome: Bool,
                    adminUser: String,
                    adminPassword: String,
                    withReply reply: @escaping (Bool, String?) -> Void)

    /// Remove /Users/<name> from disk. Validates path is under /Users/ before proceeding.
    func deleteHomeFolder(_ path: String,
                          withReply reply: @escaping (Bool, String?) -> Void)

    /// Returns the helper's version string for sanity-checking the installed version.
    func helperVersion(withReply reply: @escaping (String) -> Void)

    /// Asks the helper to exit so launchd relaunches the updated binary on the next
    /// connection. Used to cleanly swap in a new helper build without re-registering.
    func quitHelper(withReply reply: @escaping (Bool) -> Void)

    /// Returns the total byte size of a home folder. Runs as root so it can read any user's directory.
    func homeSize(path: String, withReply reply: @escaping (Int64) -> Void)

    /// Reset a user's password and clear any DisabledUser lockout. Runs as root via the helper.
    /// For accounts with a SecureToken (FileVault), macOS requires a SecureToken
    /// admin's credentials to authorise the reset — pass `adminUser`/`adminPassword`
    /// for those. Pass empty strings to attempt an unauthenticated root reset
    /// (works for accounts without a SecureToken).
    func resetPassword(username: String,
                       newPassword: String,
                       adminUser: String,
                       adminPassword: String,
                       withReply reply: @escaping (Bool, String?) -> Void)
}
