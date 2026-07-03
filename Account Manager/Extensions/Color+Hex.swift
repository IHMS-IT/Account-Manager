//
//  Color+Hex.swift
//  Account Manager
//

import SwiftUI
import AppKit

extension Color {
    /// Brand blue that stays legible under the app's *rendered* appearance — even
    /// when the app overrides the system appearance (SwiftUI's `colorScheme` does
    /// NOT track an `NSApp.appearance` override, so relying on it can pick the
    /// wrong shade). This reads the actual effective appearance instead.
    static var brandAdaptive: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0x6B/255.0, green: 0x9B/255.0, blue: 0xE8/255.0, alpha: 1)  // #6B9BE8
                : NSColor(srgbRed: 0x00/255.0, green: 0x30/255.0, blue: 0x76/255.0, alpha: 1)  // #003076
        })
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255

        self.init(red: r, green: g, blue: b)
    }
}
