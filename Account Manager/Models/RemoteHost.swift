//
//  RemoteHost.swift
//  Account Manager
//

import Foundation
import SwiftUI

// MARK: - Supporting types

enum DeviceType: String, Codable, CaseIterable {
    case desktop, laptop

    var systemImage: String {
        switch self {
        case .desktop: return "desktopcomputer"
        case .laptop:  return "laptopcomputer"
        }
    }
    var label: String {
        switch self {
        case .desktop: return "Desktop"
        case .laptop:  return "Laptop"
        }
    }
}

enum HostColorTag: String, Codable, CaseIterable {
    case none, red, orange, yellow, green, blue, purple, pink

    var color: Color? {
        switch self {
        case .none:   return nil
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .blue:   return Color(hex: "#6B9BE8")
        case .purple: return .purple
        case .pink:   return .pink
        }
    }
    var label: String { rawValue.capitalized }
}

// MARK: - RemoteHost

struct RemoteHost: Identifiable, Equatable, Hashable {
    var id: UUID
    var label: String       // display name, e.g. "Room 101 iMac"
    var hostname: String    // IP address or hostname
    var sshUser: String     // user with passwordless sudo
    var sshKeyPath: String  // path to private key
    var port: Int           // SSH port, usually 22
    var deviceType: DeviceType  = .desktop
    var colorTag: HostColorTag  = .none

    init(label: String = "",
         hostname: String = "",
         sshUser: String = "admin",
         sshKeyPath: String = "~/.ssh/id_accountmanager",
         port: Int = 22,
         deviceType: DeviceType = .desktop,
         colorTag: HostColorTag = .none) {
        self.id         = UUID()
        self.label      = label
        self.hostname   = hostname
        self.sshUser    = sshUser
        self.sshKeyPath = sshKeyPath
        self.port       = port
        self.deviceType = deviceType
        self.colorTag   = colorTag
    }
}

// MARK: - Codable (manual, for backward-compatible optional keys)

extension RemoteHost: Codable {
    enum CodingKeys: String, CodingKey {
        case id, label, hostname, sshUser, sshKeyPath, port, deviceType, colorTag
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self,   forKey: .id)
        label      = try c.decode(String.self, forKey: .label)
        hostname   = try c.decode(String.self, forKey: .hostname)
        sshUser    = try c.decode(String.self, forKey: .sshUser)
        sshKeyPath = try c.decode(String.self, forKey: .sshKeyPath)
        port       = try c.decode(Int.self,    forKey: .port)
        deviceType = (try? c.decode(DeviceType.self,   forKey: .deviceType)) ?? .desktop
        colorTag   = (try? c.decode(HostColorTag.self, forKey: .colorTag))   ?? .none
    }
}
