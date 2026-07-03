//
//  RemoteSetupSheet.swift
//  Account Manager
//
//  Guided wizard that bootstraps a remote Mac for SSH key-based access:
//    1. Collects hostname / admin credentials (one-time password, never stored)
//    2. Generates an SSH key if needed
//    3. SSHes in with the password, installs the key + passwordless sudo
//    4. Tests key-based login and saves the host on success
//

import SwiftUI

struct RemoteSetupSheet: View {

    let onSave: (RemoteHost) -> Void
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var label      = ""
    @State private var hostname   = ""
    @State private var username   = "admin"
    @State private var password   = ""
    @State private var port       = "22"
    @State private var deviceType: DeviceType   = .desktop
    @State private var colorTag:   HostColorTag = .none
    @State private var phase      = Phase.form

    @State private var log: [LogEntry] = []

    // MARK: - Phase

    enum Phase: Equatable {
        case form
        case running
        case success
        case failure(String)
    }

    struct LogEntry: Identifiable {
        let id   = UUID()
        var text: String
        var done: Bool
    }

    private var canBegin: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty &&
        !hostname.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        Int(port) != nil
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Fixed header ──────────────────────────────────────────────────
            HStack(spacing: 10) {
                Image(systemName: "wand.and.sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.brandAdaptive)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Remote Mac Setup")
                        .font(.title2.bold())
                    Text("Configures SSH key access and sudo from within this app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 14)

            Divider()

            // ── Scrollable content ────────────────────────────────────────────
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    switch phase {
                    case .form:
                        formContent
                    case .running:
                        runningContent
                    case .success:
                        successContent
                    case .failure(let msg):
                        failureContent(msg)
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 460, minHeight: 440)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: phase)
    }

    // MARK: - Form

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Enter the remote Mac's details and an **admin account** password. The password is used once to configure SSH and is never stored.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            fieldRow("Sidebar Label", hint: "Name shown in the sidebar, e.g. 'Room 101 iMac'") {
                TextField("Room 101 iMac", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            fieldRow("Hostname / IP", hint: "IP address or Bonjour hostname of the remote Mac") {
                TextField("192.168.1.50   or   mac-101.local", text: $hostname)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            HStack(alignment: .top, spacing: 12) {
                fieldRow("Admin Username", hint: "Local admin account on the remote Mac") {
                    TextField("admin", text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                fieldRow("SSH Port", hint: "Usually 22") {
                    TextField("22", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }

            fieldRow("Admin Password", hint: "Used once to install the SSH key and configure sudo — never saved") {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            Divider().padding(.vertical, 14)

            // Device type
            VStack(alignment: .leading, spacing: 4) {
                Text("Device Type").font(.subheadline.weight(.semibold))
                Text("Shown as an icon in the sidebar").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(DeviceType.allCases, id: \.self) { type in
                        let selected = deviceType == type
                        Button { deviceType = type } label: {
                            VStack(spacing: 4) {
                                Image(systemName: type.systemImage)
                                    .font(.system(size: 18))
                                Text(type.label)
                                    .font(.caption2)
                            }
                            .foregroundStyle(selected ? Color.white : .primary)
                            .frame(width: 72, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? Color.brandAdaptive : Color.primary.opacity(0.07))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selected ? Color.brandAdaptive : Color.primary.opacity(0.15), lineWidth: 0.75)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 7)

            // Sidebar colour tag
            VStack(alignment: .leading, spacing: 4) {
                Text("Sidebar Colour").font(.subheadline.weight(.semibold))
                Text("Tints the host row for quick identification").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(HostColorTag.allCases, id: \.self) { tag in
                        let selected = colorTag == tag
                        Button { colorTag = tag } label: {
                            ZStack {
                                Circle()
                                    .fill(tag.color ?? Color.primary.opacity(0.12))
                                    .frame(width: 22, height: 22)
                                if tag == .none {
                                    Image(systemName: "slash.circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                if selected {
                                    Circle()
                                        .stroke(Color.primary.opacity(0.6), lineWidth: 2)
                                        .frame(width: 26, height: 26)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(tag.label)
                    }
                }
            }
            .padding(.vertical, 7)

            Divider().padding(.vertical, 14)

            requirementNote

            Divider().padding(.top, 14)

            // ── Fixed footer ──────────────────────────────────────────────
            HStack {
                GlassActionButton(
                    title: "Cancel",
                    baseColor: Color.gray.opacity(0.45), foreground: .white,
                    font: .system(size: 12, weight: .semibold),
                    horizontalPadding: 14, verticalPadding: 7,
                    cornerRadius: 12, disabled: false
                ) { dismiss() }

                Spacer()

                GlassActionButton(
                    title: "Set Up Remote Mac",
                    baseColor: Color.ihmsBrand, foreground: .white,
                    font: .system(size: 13, weight: .semibold),
                    horizontalPadding: 20, verticalPadding: 8,
                    cornerRadius: 12, disabled: !canBegin
                ) { beginSetup() }
            }
            .padding(.top, 16)
        }
    }

    // MARK: - Running

    private var runningContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Configuring the remote Mac — this takes about 10–20 seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(log) { entry in
                    HStack(spacing: 8) {
                        if entry.done {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 14))
                        } else {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                        }
                        Text(entry.text)
                            .font(.system(size: 13))
                            .foregroundStyle(entry.done ? .primary : .secondary)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: log.count)

            Spacer(minLength: 20)
        }
    }

    // MARK: - Success

    private var successContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remote Mac ready!")
                        .font(.title3.bold())
                    Text("Key-based SSH and passwordless sudo are configured.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(log) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                        Text(entry.text)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.20), lineWidth: 0.5))

            Spacer(minLength: 16)

            HStack {
                Spacer()
                GlassActionButton(
                    title: "Add Host to Sidebar",
                    baseColor: Color.ihmsBrand, foreground: .white,
                    font: .system(size: 13, weight: .semibold),
                    horizontalPadding: 20, verticalPadding: 8,
                    cornerRadius: 12, disabled: false
                ) { saveAndDismiss() }
                Spacer()
            }
        }
    }

    // MARK: - Failure

    @ViewBuilder
    private func failureContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup failed")
                        .font(.title3.bold())
                    Text("Check the details below and try again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                Text(message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 140)
            .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.30), lineWidth: 0.5))

            Text("Common causes: Remote Login not enabled on the remote Mac, wrong password, or the admin account doesn't have sudo rights.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            HStack {
                GlassActionButton(
                    title: "Cancel",
                    baseColor: Color.gray.opacity(0.45), foreground: .white,
                    font: .system(size: 12, weight: .semibold),
                    horizontalPadding: 14, verticalPadding: 7,
                    cornerRadius: 12, disabled: false
                ) { dismiss() }

                Spacer()

                GlassActionButton(
                    title: "Try Again",
                    baseColor: Color.ihmsBrand, foreground: .white,
                    font: .system(size: 13, weight: .semibold),
                    horizontalPadding: 20, verticalPadding: 8,
                    cornerRadius: 12, disabled: false
                ) { phase = .form; log = [] }
            }
        }
    }

    // MARK: - Requirement note

    private var requirementNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Before continuing", systemImage: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Remote Login must be enabled on the remote Mac:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("System Settings → General → Sharing → Remote Login: On")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fieldRow<C: View>(_ title: String, hint: String, @ViewBuilder control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(hint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            control()
        }
        .padding(.vertical, 7)
    }

    // MARK: - Actions

    private func beginSetup() {
        guard canBegin, let portInt = Int(port) else { return }

        phase = .running
        log   = [LogEntry(text: "Generating SSH key...", done: false)]

        let capturedHostname = hostname.trimmingCharacters(in: .whitespaces)
        let capturedUsername = username.trimmingCharacters(in: .whitespaces)
        let capturedPassword = password

        Task {
            do {
                _ = try await SSHBootstrapper.publicKey()
                markDone(0, "SSH key ready")
                appendLog("Connecting to \(capturedHostname)...")

                try await SSHBootstrapper.bootstrap(
                    hostname: capturedHostname,
                    port: portInt,
                    username: capturedUsername,
                    password: capturedPassword
                ) { @MainActor [self] message in
                    if let last = log.indices.last, !log[last].done {
                        log[last].done = true
                    }
                    log.append(LogEntry(text: message, done: false))
                }

                await MainActor.run {
                    if let last = log.indices.last { log[last].done = true }
                    phase = .success
                }

            } catch {
                await MainActor.run {
                    phase = .failure(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func markDone(_ index: Int, _ text: String) {
        guard index < log.count else { return }
        log[index] = LogEntry(text: text, done: true)
    }

    @MainActor
    private func appendLog(_ text: String) {
        log.append(LogEntry(text: text, done: false))
    }

    private func saveAndDismiss() {
        guard let portInt = Int(port) else { return }
        let host = RemoteHost(
            label:      label.trimmingCharacters(in: .whitespaces),
            hostname:   hostname.trimmingCharacters(in: .whitespaces),
            sshUser:    username.trimmingCharacters(in: .whitespaces),
            sshKeyPath: SSHBootstrapper.accountManagerKeyPath,
            port:       portInt,
            deviceType: deviceType,
            colorTag:   colorTag
        )
        onSave(host)
        dismiss()
    }
}

#Preview {
    RemoteSetupSheet { _ in }
}
