//
//  HelperRequiredSheet.swift
//  Account Manager
//
//  Blocking gate shown at launch when the privileged helper isn't installed.
//  Cannot be dismissed — it polls the helper status and calls `onInstalled`
//  automatically once the daemon is registered and enabled.
//

import SwiftUI

struct HelperRequiredSheet: View {
    let onInstalled: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var status: HelperStatus = .notInstalled
    @State private var busy = false
    @State private var errorText: String?
    @State private var pollTask: Task<Void, Never>?

    // Reads the actual rendered appearance (colorScheme misses NSApp overrides).
    private var accent: Color { Color.brandAdaptive }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(accent)
            }
            .padding(.top, 6)

            VStack(spacing: 6) {
                Text("Set Up the Privileged Helper")
                    .font(.title3.bold())
                Text("Account Manager needs a one-time background helper to delete accounts and reset passwords on this Mac. It runs as root so no admin password is ever required during normal use.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)

            // Live status row — glass card matching the rest of the app
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(statusLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                if busy {
                    ProgressView().controlSize(.small).padding(.leading, 2)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
            )

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(hex: "#C62828"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }

            Text("If macOS asks you to approve “Account Manager” in Login Items & Extensions, enable it there — this window will continue automatically once the helper is active.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)

            GlassActionButton(
                title: status == .requiresApproval ? "Open Login Items…" : "Install Helper",
                baseColor: accent,
                foreground: .white,
                font: .system(size: 13, weight: .semibold),
                horizontalPadding: 20, verticalPadding: 9,
                cornerRadius: 12,
                disabled: busy
            ) { install() }
        }
        .padding(28)
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .onAppear {
            refresh()
            startPolling()
        }
        .onDisappear { pollTask?.cancel() }
    }

    // MARK: - Status presentation

    private var statusColor: Color {
        switch status {
        case .installed:        return Color(hex: "#2E7D32")
        case .requiresApproval: return Color(hex: "#E8A32A")
        default:                return Color(hex: "#C62828")
        }
    }

    private var statusLabel: String {
        switch status {
        case .installed:                       return "Helper installed and active"
        case .requiresApproval:                return "Waiting for your approval…"
        case .versionMismatch:                 return "Helper needs updating"
        case .notInstalled:                    return "Helper not installed"
        }
    }

    // MARK: - Actions

    private func install() {
        busy = true
        errorText = nil
        Task {
            do {
                try await HelperClient.shared.installIfNeeded()
            } catch {
                await MainActor.run { errorText = error.localizedDescription }
            }
            try? await Task.sleep(for: .milliseconds(700))
            await refreshAsync()
            await MainActor.run { busy = false }
        }
    }

    private func refresh() {
        Task { await refreshAsync() }
    }

    private func refreshAsync() async {
        let s = await HelperClient.shared.checkStatus()
        await MainActor.run {
            status = s
            if case .installed = s { onInstalled() }
        }
    }

    /// Poll every 1.5s so the sheet advances automatically once the user
    /// approves the helper in System Settings.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500))
                await refreshAsync()
                if case .installed = status { break }
            }
        }
    }
}
