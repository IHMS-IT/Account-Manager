//
//  UpdateAvailableView.swift
//  Account Manager
//
//  Native "update available" prompt shown by HybridUserDriver in place of
//  Sparkle's built-in dialog. Uses the app's own bundled release notes
//  instead of fetching HTML notes from the appcast, matching Version Info.
//

import SwiftUI

struct UpdateAvailableView: View {
    let newVersion:     String
    let currentVersion: String
    let notes:          [String]
    let onInstall:      () -> Void
    let onNotNow:       () -> Void

    /// The app's icon — same lookup as VersionInfoSheet.
    private var appIconImage: NSImage {
        NSImage(named: "AppIcon") ?? NSApp?.applicationIconImage ?? NSImage()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: appIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("A new version of Account Manager is available!")
                        .font(.system(size: 14, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Account Manager \(newVersion) is now available — you have \(currentVersion).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !notes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(notes, id: \.self) { note in
                            HStack(alignment: .top, spacing: 7) {
                                Text("•")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Text(note)
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(height: 180)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.20), lineWidth: 0.5))
            }

            HStack(spacing: 10) {
                Spacer()

                GlassActionButton(
                    title: "Not Now",
                    baseColor: Color.gray.opacity(0.45),
                    foreground: .white,
                    font: .system(size: 12, weight: .semibold),
                    horizontalPadding: 14, verticalPadding: 7,
                    cornerRadius: 12, disabled: false
                ) { onNotNow() }

                GlassActionButton(
                    title: "Install Update",
                    baseColor: Color.brandAdaptive,
                    foreground: .white,
                    font: .system(size: 13, weight: .semibold),
                    horizontalPadding: 18, verticalPadding: 8,
                    cornerRadius: 12, disabled: false
                ) { onInstall() }
            }
        }
        .padding(22)
        .frame(width: 380)
    }
}
