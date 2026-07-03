//
//  Config.swift
//  Account Manager
//
//  Single source of configuration. Reads managed preferences first,
//  falls back to UserDefaults, then to compile-time defaults.
//  Mosyle can push an MDM config profile to override any key.
//

import Foundation

struct Config {

    // MARK: - IHMS-reserved protected usernames (§4)
    var protectedUsernames: Set<String> = ["temp", "Local"]

    // MARK: - K-3 shared accounts — used for sidebar categorisation only, not protection
    var k3Accounts: Set<String> = ["k", "g1", "g2", "g3"]

    // MARK: - UID floor — accounts with UID below this are protected (§4)
    // 200 instead of 500: macOS service accounts in the 200-499 range all start with "_"
    // and are caught earlier. Hidden admin accounts (e.g. ihmsadmin) typically sit at
    // UID 498-499 and should be visible.
    var minProtectedUID: Int = 200

    // MARK: - Group tags (§6)
    var staffTags:  [String] = ["_staff"]
    var officeTags: [String] = ["_office"]
    var adminTags:  [String] = ["_administrator", "IT"]

    // MARK: - Deletion defaults (§10.5)
    var deletionModeDefault: DeletionMode       = .accountAndFiles
    var fileDeleteDefault:   FileDeletionMethod = .hard

    // MARK: - Tool selection
    var useLegacyDeletionTool: Bool = false   // false → sysadminctl, true → dscl+rm

    // MARK: - Shared singleton, reads from UserDefaults / managed preferences

    static let shared: Config = {
        var c = Config()
        let ud = UserDefaults.standard

        if let names = ud.stringArray(forKey: "protectedUsernames") {
            c.protectedUsernames = Set(names)
        }
        if let k3 = ud.stringArray(forKey: "k3Accounts") {
            c.k3Accounts = Set(k3)
        }
        if ud.object(forKey: "minProtectedUID") != nil {
            c.minProtectedUID = ud.integer(forKey: "minProtectedUID")
        }
        if let s = ud.stringArray(forKey: "staffTags")  { c.staffTags  = s }
        if let o = ud.stringArray(forKey: "officeTags") { c.officeTags = o }
        if let a = ud.stringArray(forKey: "adminTags")  { c.adminTags  = a }

        if let raw = ud.string(forKey: "deletionModeDefault"),
           let mode = DeletionMode(rawValue: raw) {
            c.deletionModeDefault = mode
        }
        if let raw = ud.string(forKey: "fileDeleteDefault"),
           let method = FileDeletionMethod(rawValue: raw) {
            c.fileDeleteDefault = method
        }
        if ud.object(forKey: "useLegacyDeletionTool") != nil {
            c.useLegacyDeletionTool = ud.bool(forKey: "useLegacyDeletionTool")
        }

        return c
    }()
}
