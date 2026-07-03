//
//  AccountFilter.swift
//  Account Manager
//
//  Substring matching for the filter sheet (§3, §7.3).
//  Unit-testable; no UI dependencies.
//

import Foundation

enum FilterMatchType: String, CaseIterable, Identifiable {
    case startsWith  = "Starts With"
    case contains    = "Contains"
    case endsWith    = "Ends With"

    var id: String { rawValue }
}

struct AccountFilter {

    let matchType: FilterMatchType
    let pattern: String

    /// Returns true if the username matches according to this filter.
    func matches(_ username: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        switch matchType {
        case .startsWith: return username.localizedCaseInsensitiveCompare(pattern) == .orderedSame
            || username.lowercased().hasPrefix(pattern.lowercased())
        case .contains:   return username.localizedCaseInsensitiveContains(pattern)
        case .endsWith:   return username.lowercased().hasSuffix(pattern.lowercased())
        }
    }

    /// Apply to a list of accounts, returning only matching items.
    func apply(to accounts: [UserAccount]) -> [UserAccount] {
        accounts.filter { matches($0.username) }
    }
}
