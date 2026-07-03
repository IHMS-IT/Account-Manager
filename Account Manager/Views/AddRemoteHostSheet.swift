//
//  AddRemoteHostSheet.swift
//  Account Manager
//

import SwiftUI

struct AddRemoteHostSheet: View {

    let existing: RemoteHost?   // nil = add, non-nil = edit
    let onSave: (RemoteHost) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var label      = ""
    @State private var hostname   = ""
    @State private var sshUser    = "admin"
    @State private var sshKeyPath = "~/.ssh/id_accountmanager"
    @State private var port       = "22"
    @State private var deviceType: DeviceType  = .desktop
    @State private var colorTag:   HostColorTag = .none
    @State private var testPhase  = TestPhase.idle
    @State private var showSetup  = false

    init(existing: RemoteHost? = nil, onSave: @escaping (RemoteHost) -> Void) {
        self.existing = existing
        self.onSave   = onSave
        if let h = existing {
            _label      = State(initialValue: h.label)
            _hostname   = State(initialValue: h.hostname)
            _sshUser    = State(initialValue: h.sshUser)
            _sshKeyPath = State(initialValue: h.sshKeyPath)
            _port       = State(initialValue: "\(h.port)")
            _deviceType = State(initialValue: h.deviceType)
            _colorTag   = State(initialValue: h.colorTag)
        }
    }

    enum TestPhase: Equatable { case idle, testing, ok, failed(String) }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty &&
        !hostname.trimmingCharacters(in: .whitespaces).isEmpty &&
        !sshUser.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(port) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Fixed header ──────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text(existing == nil ? "Add Remote Host" : "Edit Remote Host")
                    .font(.title2.bold())
                Text("Connect to a remote Mac over SSH to manage its local accounts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 14)

            Divider()

            // ── Scrollable form body ──────────────────────────────────────────
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // Setup wizard callout
                    setupCallout
                        .padding(.horizontal, 24)
                        .padding(.top, 14)

                    Divider().padding(.vertical, 14).padding(.horizontal, 24)

                    // Manual entry fields
                    Text("Or fill in manually if SSH key access is already configured:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 4)

                    Group {
                        fieldRow("Label", hint: "Friendly name shown in the sidebar") {
                            TextField("Room 101 iMac", text: $label)
                                .textFieldStyle(.roundedBorder)
                        }

                        fieldRow("Hostname / IP", hint: "IP address or Bonjour hostname of the remote Mac") {
                            TextField("192.168.1.50   or   mac-101.local", text: $hostname)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }

                        fieldRow("SSH User", hint: "Account with passwordless sudo on the remote Mac") {
                            TextField("admin", text: $sshUser)
                                .textFieldStyle(.roundedBorder)
                        }

                        fieldRow("SSH Key", hint: "Path to the private key (passwordless auth required)") {
                            HStack(spacing: 6) {
                                TextField("~/.ssh/id_accountmanager", text: $sshKeyPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                                Button("Browse...") { pickKeyFile() }
                                    .buttonStyle(.bordered)
                            }
                        }

                        fieldRow("Port", hint: "SSH port (default: 22)") {
                            TextField("22", text: $port)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }

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
                                                .fill(selected ? Color.ihmsBrand : Color.primary.opacity(0.07))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(selected ? Color.ihmsBrand : Color.primary.opacity(0.15), lineWidth: 0.75)
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
                    }
                    .padding(.horizontal, 24)

                    Divider().padding(.vertical, 14).padding(.horizontal, 24)

                    // Test connection row
                    HStack(spacing: 10) {
                        GlassActionButton(
                            title: testPhase == .testing ? "Testing..." : "Test Connection",
                            baseColor: Color.ihmsBrand.opacity(0.75),
                            foreground: .white,
                            font: .system(size: 12, weight: .semibold),
                            horizontalPadding: 12, verticalPadding: 6,
                            cornerRadius: 10,
                            disabled: !canSave || testPhase == .testing
                        ) { runTest() }

                        testStatusLabel
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }

            Divider()

            // ── Fixed footer ──────────────────────────────────────────────────
            HStack(spacing: 10) {
                GlassActionButton(
                    title: "Cancel",
                    baseColor: Color.gray.opacity(0.45), foreground: .white,
                    font: .system(size: 12, weight: .semibold),
                    horizontalPadding: 14, verticalPadding: 7,
                    cornerRadius: 12, disabled: false
                ) { dismiss() }

                Spacer()

                GlassActionButton(
                    title: "Save",
                    baseColor: Color.ihmsBrand, foreground: .white,
                    font: .system(size: 13, weight: .semibold),
                    horizontalPadding: 20, verticalPadding: 8,
                    cornerRadius: 12, disabled: !canSave
                ) { save() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 460, minHeight: 480)
        .sheet(isPresented: $showSetup) {
            RemoteSetupSheet { host in
                // Auto-fill fields from what setup configured, then auto-save
                onSave(host)
                dismiss()
            }
        }
    }

    // MARK: - Setup callout

    private var setupCallout: some View {
        let accent: Color = colorScheme == .dark ? Color(hex: "#6B9BE8") : Color.ihmsBrand
        return HStack(spacing: 12) {
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 20))
                .foregroundStyle(accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text("First time? Use the setup wizard")
                    .font(.system(size: 13, weight: .semibold))
                Text("Configures SSH key auth and sudo on the remote Mac — just enter the admin password once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            GlassActionButton(
                title: "Set Up...",
                baseColor: accent, foreground: .white,
                font: .system(size: 12, weight: .semibold),
                horizontalPadding: 12, verticalPadding: 6,
                cornerRadius: 10, disabled: false
            ) { showSetup = true }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(colorScheme == .dark ? 0.40 : 0.25), lineWidth: 0.75)
        )
    }

    // MARK: - Test status label

    @ViewBuilder
    private var testStatusLabel: some View {
        switch testPhase {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .ok:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .lineLimit(1)
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

    private func save() {
        guard canSave, let portInt = Int(port) else { return }
        var host = RemoteHost(
            label:      label.trimmingCharacters(in: .whitespaces),
            hostname:   hostname.trimmingCharacters(in: .whitespaces),
            sshUser:    sshUser.trimmingCharacters(in: .whitespaces),
            sshKeyPath: sshKeyPath,
            port:       portInt,
            deviceType: deviceType,
            colorTag:   colorTag
        )
        if let existing { host.id = existing.id }  // preserve ID when editing
        onSave(host)
        dismiss()
    }

    private func runTest() {
        guard canSave, let portInt = Int(port) else { return }
        testPhase = .testing
        let host = RemoteHost(
            label: label, hostname: hostname.trimmingCharacters(in: .whitespaces),
            sshUser: sshUser.trimmingCharacters(in: .whitespaces),
            sshKeyPath: sshKeyPath, port: portInt
        )
        let runner = SSHRunner(host: host)
        Task {
            let ok = await runner.testConnection()
            await MainActor.run {
                withAnimation {
                    testPhase = ok ? .ok : .failed("Could not connect — check hostname, key, and sudo access")
                }
            }
        }
    }

    private func pickKeyFile() {
        let panel = NSOpenPanel()
        panel.title             = "Choose SSH Private Key"
        panel.showsHiddenFiles  = true
        panel.canChooseFiles    = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "\(NSHomeDirectory())/.ssh")
        guard let window = NSApp?.keyWindow ?? NSApp?.windows.first else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            var path = url.path
            let home = NSHomeDirectory()
            if path.hasPrefix(home) { path = "~" + path.dropFirst(home.count) }
            sshKeyPath = path
        }
    }
}

#Preview {
    AddRemoteHostSheet { _ in }
}
