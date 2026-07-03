//
//  ProtectedPolicy.swift
//  Account Manager
//
//  Single source of truth for which accounts are protected (§4).
//  Unit-testable; no UI dependencies.
//

import Foundation

struct ProtectedPolicy {

    let config: Config
    let currentOperator: String

    init(config: Config = .shared, operatorOverride: String? = nil) {
        self.config = config
        self.currentOperator = operatorOverride ?? NSUserName()
    }

    // MARK: - Public API

    /// Returns the protection tier and reason for a given account.
    func protectionTier(username: String, uid: Int) -> (tier: ProtectionTier, reason: String?) {
        // Session-locked: current operator — deletable when logged out
        if username == currentOperator {
            return (.sessionLocked, "Currently logged in — can be deleted when signed in as another admin")
        }
        // Name-based checks first, before the UID floor, so hidden admin accounts
        // (UID 400-499) are not caught by the floor if they aren't service accounts.
        if username.hasPrefix("_") {
            return (.systemLocked, "macOS service account (starts with _)")
        }
        if username.hasPrefix("com.") {
            return (.systemLocked, "Daemon-style account (starts with com.)")
        }
        if isSystemUsername(username) {
            return (.systemLocked, "macOS system account")
        }
        // UID floor catches anything else with a suspiciously low UID (root, daemon, nobody…)
        if uid < config.minProtectedUID {
            return (.systemLocked, "UID \(uid) is below the protected floor (\(config.minProtectedUID))")
        }
        if config.protectedUsernames.contains(username) {
            return (.systemLocked, "IHMS-reserved account")
        }
        return (.none, nil)
    }

    func isProtected(username: String, uid: Int) -> Bool {
        protectionTier(username: username, uid: uid).tier != .none
    }

    // MARK: - K-3 categorisation

    func isK3Account(_ username: String) -> Bool {
        config.k3Accounts.contains(username)
    }

    // MARK: - Category membership

    func category(for account: UserAccount) -> AccountCategory {
        let tier = protectionTier(username: account.username, uid: account.uid).tier

        // K-3 accounts: always in K-3 Shared
        if isK3Account(account.username) {
            return .k3Shared
        }

        // Truly system/reserved accounts go to System/Protected
        if tier == .systemLocked {
            return .systemProtected
        }

        // Session-locked (current operator) and normal accounts both get natural category

        // Actual admin group member or admin-tagged
        if account.isActuallyAdmin
            || config.adminTags.contains(where: { account.username.hasSuffix($0) || account.username == $0 }) {
            return .admin
        }

        // Student: 2-digit grad year suffix
        if matchesGradYear(account.username) {
            return .students
        }

        // Tagged groups
        if config.staffTags.contains(where: { account.username.hasSuffix($0) }) {
            return .staff
        }
        if config.officeTags.contains(where: { account.username.hasSuffix($0) }) {
            return .office
        }

        return .other
    }

    // MARK: - Privates

    private let systemUsernames: Set<String> = [
        "root", "nobody", "daemon", "_mbsetupuser", "_spotlight", "_mdnsresponder",
        "_networkd", "_softwareupdate", "_coreaudiod", "_usbmuxd", "_driverkit",
        "_analyticsd", "_appstore", "_appleevents", "_astris", "_atsserver",
        "_avbdeviced", "_calendar", "_captiveagent", "_ces", "_cmiodalassistants",
        "_colorsyncd", "_coremediaiod", "_coreml", "_ctkd", "_cvmsroot", "_datadetectors",
        "_demod", "_devdocs", "_devicemgr", "_diskimagesiod", "_displaypolicyd",
        "_distnote", "_dmd", "_ftp", "_gamecontrollerd", "_geod", "_hidd",
        "_iconservices", "_installcoordinationd", "_installer", "_jabber", "_kadmin_admin",
        "_kadmin_changepw", "_krb_anonymous", "_krb_changepw", "_krb_kadmin",
        "_krb_kerberos", "_krb_krbtgt", "_krbfast", "_krbtgt", "_launchservicesd",
        "_lp", "_locationd", "_logd", "_mailman", "_mbsetupuser", "_mcxalr",
        "_mdnsresponder", "_mobileasset", "_mysql", "_netbios", "_networkd",
        "_nsurlsessiond", "_nsurlstoraged", "_oahd", "_ondemand", "_postfix",
        "_postgres", "_qtss", "_reportmemoryexception", "_rmd", "_sandbox",
        "_screensaver", "_scsd", "_securityagent", "_serialnumberd", "_softwareupdate",
        "_ssh", "_svn", "_syspolicyd", "_taskgated", "_teamsserver", "_timed",
        "_timezone", "_trustevaluationagent", "_unknown", "_update_sharing",
        "_usbmuxd", "_uucp", "_warmd", "_webauthserver", "_windowserver", "_www",
        "_xserverdocs",
    ]

    private func isSystemUsername(_ username: String) -> Bool {
        systemUsernames.contains(username)
    }

    private func matchesGradYear(_ username: String) -> Bool {
        guard username.count >= 2 else { return false }
        let suffix = String(username.suffix(2))
        return suffix.allSatisfy(\.isNumber)
    }
}
