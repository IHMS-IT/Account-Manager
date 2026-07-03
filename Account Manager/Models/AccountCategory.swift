//
//  AccountCategory.swift
//  Account Manager
//

import Foundation

enum AccountCategory: String, CaseIterable, Identifiable {
    case all              = "all"
    case students         = "students"
    case k3Shared         = "k3Shared"
    case staff            = "staff"
    case office           = "office"
    case admin            = "admin"
    case other            = "other"
    case systemProtected  = "systemProtected"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:             return "All Accounts"
        case .students:        return "Students"
        case .k3Shared:        return "K-3 Shared"
        case .staff:           return "Staff"
        case .office:          return "Office"
        case .admin:           return "Admin"
        case .other:           return "Other"
        case .systemProtected: return "System"
        }
    }

    var systemImage: String {
        switch self {
        case .all:             return "person.3"
        case .students:        return "graduationcap"
        case .k3Shared:        return "figure.child"
        case .staff:           return "briefcase"
        case .office:          return "tray.full"
        case .admin:           return "key"
        case .other:           return "person.crop.circle.badge.questionmark"
        case .systemProtected: return "lock.shield"
        }
    }

    var scopeHint: String {
        switch self {
        case .all:
            return "Every non-system account on this Mac. System accounts appear only under System."
        case .students:
            return "Accounts matching a graduation-year suffix (e.g. jdoe26)."
        case .k3Shared:
            return "Shared primary-grade accounts (k, g1, g2, g3)."
        case .staff:
            return "Accounts tagged with a staff suffix (e.g. _staff)."
        case .office:
            return "Accounts tagged with an office suffix (e.g. _office)."
        case .admin:
            return "Accounts tagged as administrator or IT."
        case .other:
            return "Accounts that don't match any named group. Deletable."
        case .systemProtected:
            return "macOS system and IHMS-reserved accounts. Read-only — cannot be selected."
        }
    }

    /// Whether rows in this category are always read-only (never deletable).
    var isReadOnly: Bool {
        self == .systemProtected
    }
}
