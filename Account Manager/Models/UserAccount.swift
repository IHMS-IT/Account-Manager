//
//  UserAccount.swift
//  Account Manager
//

import Foundation

// MARK: - Deletion mode

enum DeletionMode: String, CaseIterable, Identifiable, Codable {
    case accountAndFiles = "both"
    case accountOnly     = "account"
    case filesOnly       = "files"
    case resetPassword   = "resetPassword"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .accountAndFiles: return "Account + Files"
        case .accountOnly:     return "Account Only"
        case .filesOnly:       return "Files Only"
        case .resetPassword:   return "Reset Password"
        }
    }

    var shortLabel: String {
        switch self {
        case .accountAndFiles: return "Acct + Files"
        case .accountOnly:     return "Acct Only"
        case .filesOnly:       return "Files Only"
        case .resetPassword:   return "Reset Pwd"
        }
    }

    var isDestructive: Bool { self != .resetPassword }
}

// MARK: - File deletion method (for file-removal portion)

enum FileDeletionMethod: String, CaseIterable, Identifiable, Codable {
    var id: String { rawValue }

    case hard = "hard"

    var label: String { "Hard Delete" }
}

// MARK: - Protection tier

enum ProtectionTier {
    case none           // deletable
    case sessionLocked  // current operator — deletable when logged out
    case systemLocked   // system/reserved — never deletable
}

// MARK: - User account model

struct UserAccount: Identifiable, Equatable {
    let id: String          // username is stable identity
    var username: String
    var displayName: String?
    var uid: Int
    var homePath: String
    var homeExists: Bool
    var homeSize: Int64?    // bytes; nil = not yet measured

    var isProtected: Bool
    var protectionTier: ProtectionTier = .none
    var protectionReason: String?   // surfaced in UI for protected rows
    var isActuallyAdmin: Bool = false   // member of macOS admin group
    var isPasswordLocked: Bool = false  // account locked due to too many failed login attempts

    var isChecked: Bool = false
    var deletionMode: DeletionMode = .accountAndFiles

    static func == (lhs: UserAccount, rhs: UserAccount) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Home size formatting

extension UserAccount {
    var homeSortKey: Int64 { homeSize ?? -1 }
    var displayNameSortKey: String { displayName ?? "" }

    var homeSizeString: String {
        guard homeExists else { return "No home" }
        guard let bytes = homeSize else { return "…" }
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
