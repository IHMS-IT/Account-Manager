//
//  VersionInfoSheet.swift
//  Account Manager
//

import SwiftUI
import Sparkle

// MARK: - Release notes loader

struct ReleaseNotesProvider {
    static func loadAll() -> [String: [String]] {
        guard
            let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data),
            let dict = json as? [String: [String]]
        else { return [:] }
        return dict
    }

    static func notes(for version: String) -> [String] {
        let dict = loadAll()
        if let notes = dict[version] { return notes }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if let notes = dict[trimmed] { return notes }
        if let latestKey = allVersionsNewestFirst().first, let notes = dict[latestKey] { return notes }
        return []
    }

    /// All version keys from ReleaseNotes.json, newest first (proper numeric
    /// dot-version compare, not lexicographic — so "1.0.10" sorts after "1.0.9").
    static func allVersionsNewestFirst() -> [String] {
        loadAll().keys.sorted { compareVersions($0, $1) == .orderedDescending }
    }

    private static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(aParts.count, bParts.count) {
            let x = i < aParts.count ? aParts[i] : 0
            let y = i < bParts.count ? bParts[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

// MARK: - Checking indicator

private struct CheckingIndicator: View {
    let text: String
    @State private var pulse = false

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.75))
            .animation(.easeInOut(duration: 0.2), value: text)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)).blendMode(.overlay)
                    RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.28), lineWidth: 0.5)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hex: "#4A90D9"), lineWidth: 1.5)
                    .blur(radius: pulse ? 4 : 2)
                    .opacity(pulse ? 0.35 : 0.85)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
            )
            .onAppear { pulse = true }
    }
}

// MARK: - VersionInfoSheet

struct VersionInfoSheet: View {
    let appVersion: String
    let fullVersionString: String
    @Binding var isPresented: Bool

    @Environment(\.sparkleUpdater) private var updater
    @Environment(\.updaterCoordinator) private var coordinator

    /// Current update-check phase, driven by Sparkle's real result via the
    /// coordinator. Falls back to `.idle` if no coordinator is present.
    private var phase: UpdaterCoordinator.Phase {
        coordinator?.phase ?? .idle
    }

    /// Label for the primary update button given the real phase.
    private var checkButtonLabel: String {
        switch phase {
        case .idle:            return "Check for Updates"
        case .checking:        return "Checking…"
        case .upToDate:        return "Up to date!"
        case .updateAvailable: return "Update available"
        case .failed:          return "Update failed"
        }
    }

    /// Which version's notes are currently shown. Starts on the installed
    /// version; the picker below lets the user browse older entries.
    @State private var selectedNoteVersion: String?

    private var displayedVersion: String { selectedNoteVersion ?? appVersion }
    private var notes: [String] { ReleaseNotesProvider.notes(for: displayedVersion) }
    private var allVersions: [String] { ReleaseNotesProvider.allVersionsNewestFirst() }

    /// The app's icon. Reads the named asset from the catalog first (deterministic,
    /// independent of the macOS icon-services cache), falling back to the running
    /// app's icon and finally an empty image.
    private var appIconImage: NSImage {
        NSImage(named: "AppIcon") ?? NSApp?.applicationIconImage ?? NSImage()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack(spacing: 10) {
                Image(nsImage: appIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Account Manager")
                        .font(.title3.bold())
                    Text("Version \(fullVersionString)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if allVersions.count > 1 {
                HStack(spacing: 4) {
                    Text("Release notes for")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Menu {
                        ForEach(allVersions, id: \.self) { v in
                            Button {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    selectedNoteVersion = v
                                }
                            } label: {
                                if v == displayedVersion {
                                    Label(v, systemImage: "checkmark")
                                } else {
                                    Text(v)
                                }
                            }
                        }
                    } label: {
                        Text(displayedVersion)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.brandAdaptive)
                    }
                    .menuStyle(.borderlessButton)
                    .tint(Color.brandAdaptive)
                    .fixedSize()
                    Spacer()
                }
                .padding(.top, 2)
            }

            if notes.isEmpty {
                Text("No release notes available for this version.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(notes, id: \.self) { note in
                            HStack(alignment: .top, spacing: 7) {
                                Text("•")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                Text(note)
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .id(displayedVersion)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
                .frame(height: 220)
                // Soft fade at the top and bottom edges so scrolling text eases out
                // instead of hard-cutting against the box edge.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.045),
                            .init(color: .black, location: 0.955),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.20), lineWidth: 0.5))
            }

            Spacer(minLength: 2)

            HStack(spacing: 10) {
                Spacer()

                if phase == .checking {
                    CheckingIndicator(text: checkButtonLabel)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    GlassActionButton(
                        title: checkButtonLabel,
                        baseColor: checkButtonColor,
                        foreground: .white,
                        font: .system(size: 13, weight: .semibold),
                        horizontalPadding: 14,
                        verticalPadding: 7,
                        cornerRadius: 14,
                        disabled: phase == .upToDate
                    ) { startCheck() }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                GlassActionButton(
                    title: "Close",
                    baseColor: Color.gray.opacity(0.55),
                    foreground: .white,
                    font: .system(size: 12, weight: .semibold),
                    horizontalPadding: 12,
                    verticalPadding: 6,
                    cornerRadius: 12,
                    disabled: false
                ) { isPresented = false }

                Spacer()
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: phase)
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 360)
        .onAppear { coordinator?.reset() }
    }

    /// Button tint for the current phase.
    private var checkButtonColor: Color {
        switch phase {
        case .upToDate:        return Color(hex: "#2E7D32")   // green
        case .updateAvailable: return Color(hex: "#1565C0")   // blue
        case .failed:          return Color(hex: "#C62828")   // red
        default:               return Color.ihmsBrand
        }
    }

    private func startCheck() {
        coordinator?.beginCheck()
        // Trigger Sparkle's real update check directly — the same call the
        // menu-bar "Check for Updates…" command uses. Chaining a silent probe
        // into a follow-up checkForUpdates() call raced against Sparkle's
        // internal session state and could silently no-op, so we call it
        // straight away. The coordinator's delegate callbacks still update
        // `phase` (for the button label/colour) whether or not Sparkle's own
        // dialog is shown.
        updater?.checkForUpdates()
    }
}
