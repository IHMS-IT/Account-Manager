//
//  SettingsSheet.swift
//  Account Manager
//

import SwiftUI
import AppKit

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Appearance
    @AppStorage("appearanceMode") private var appearanceMode: String = "auto"

    // MARK: - Deletion defaults
    @AppStorage("defaultDeletionMode")  private var defaultDeletionMode: String  = DeletionMode.accountAndFiles.rawValue

    // MARK: - Default admin credentials (auto-fill only — passwords are never stored)
    @AppStorage("defaultLocalAdminUsername")  private var defaultLocalAdminUsername:  String = ""
    @AppStorage("defaultRemoteAdminUsername") private var defaultRemoteAdminUsername: String = ""

    // MARK: - Protected policy overrides (runtime — advanced)
    @State private var minUID: String = "\(UserDefaults.standard.integer(forKey: "minProtectedUID") > 0 ? UserDefaults.standard.integer(forKey: "minProtectedUID") : 500)"
    @State private var staffTagsText:  String = UserDefaults.standard.string(forKey: "staffTagsDisplay")  ?? "_staff"
    @State private var officeTagsText: String = UserDefaults.standard.string(forKey: "officeTagsDisplay") ?? "_office"
    @State private var adminTagsText:  String = UserDefaults.standard.string(forKey: "adminTagsDisplay")  ?? "_administrator, IT"

    // MARK: - Tool selection
    @AppStorage("useLegacyDeletionTool") private var useLegacyTool: Bool = false

    // MARK: - Swipe-to-reveal direction
    @AppStorage("scrollWheelInverted") private var scrollWheelInverted: Bool = false

    // MARK: - Collapsed sections
    @State private var advancedExpanded: Bool = false

    // MARK: - Security
    private let security = SecurityManager.shared
    @State private var showSetPin       = false
    @State private var showChangePin    = false
    @State private var showRemovePin    = false
    @State private var securityError:  String? = nil

    // MARK: - Log folder
    private var logFolder: String {
        let home = NSHomeDirectory()
        return "\(home)/Library/Logs/AccountManager"
    }

    // MARK: - Privileged helper status
    @State private var helperStatus: HelperStatus? = nil
    @State private var helperBusy = false
    @State private var helperError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {


                // Header
                Text("Settings")
                    .font(.title2.bold())
                    .padding(.bottom, 4)
                Text("Configure appearance, deletion defaults, and policy overrides.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // ── Appearance ──────────────────────────────────────────
                sectionHeader("Appearance")

                AppearancePicker(selection: $appearanceMode)
                    .onChange(of: appearanceMode) { _, mode in
                        AccountManagerApp.applyAppearance(mode)
                    }

                Divider().padding(.vertical, 14)

                // ── Deletion Defaults ───────────────────────────────────
                sectionHeader("Deletion Defaults")

                labeledRow(title: "Default mode",
                           hint: "Applied to newly-checked rows. Can be overridden per row.") {
                    Picker("", selection: $defaultDeletionMode) {
                        ForEach(DeletionMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }

                Divider().padding(.vertical, 14)

                // ── Default Admin Credentials ───────────────────────────
                sectionHeader("Default Admin Credentials")

                Text("If your fleet shares the same admin account, save its username here to auto-fill it. The password is never saved and must always be entered by hand.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)

                labeledRow(title: "Local admin username",
                           hint: "Auto-fills the Administrator field for local deletions and password resets.") {
                    TextField("e.g. ihmsadmin", text: $defaultLocalAdminUsername)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .frame(width: 200)
                }

                labeledRow(title: "Remote admin username",
                           hint: "Auto-fills the SSH/Administrator field when adding a remote host and for remote deletions and password resets.") {
                    TextField("e.g. ihmsadmin", text: $defaultRemoteAdminUsername)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .frame(width: 200)
                }

                Divider().padding(.vertical, 14)

                // ── Policy Overrides ────────────────────────────────────
                sectionHeader("Policy Overrides")

                Text("These override the built-in IHMS defaults. Changes take effect after the next reload. For fleet-wide changes, push a managed preference profile via Mosyle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)

                labeledRow(title: "Minimum protected UID",
                           hint: "Accounts with UID below this floor are always protected (default: 500).") {
                    TextField("500", text: $minUID)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .onSubmit { saveMinUID() }
                    Button("Set") { saveMinUID() }
                        .buttonStyle(.bordered)
                }

                labeledRow(title: "Staff suffixes",
                           hint: "Comma-separated username suffixes that identify staff accounts.") {
                    TextField("_staff", text: $staffTagsText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 160)
                    Button("Save") { saveTags() }
                        .buttonStyle(.bordered)
                }

                labeledRow(title: "Office suffixes",
                           hint: "Comma-separated username suffixes that identify office accounts.") {
                    TextField("_office", text: $officeTagsText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 160)
                }

                labeledRow(title: "Admin tags",
                           hint: "Comma-separated suffixes or exact names that identify admin accounts.") {
                    TextField("_administrator, IT", text: $adminTagsText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 160)
                    Button("Save") { saveTags() }
                        .buttonStyle(.bordered)
                }

                Divider().padding(.vertical, 14)

                // ── Privileged Helper ───────────────────────────────────
                sectionHeader("Privileged Helper")

                Text("Local account deletions and password resets run through a privileged background helper. It must be installed and approved once per Mac before those actions will work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)

                HStack(spacing: 10) {
                    Circle()
                        .fill(helperStatusColor)
                        .frame(width: 8, height: 8)
                    Text(helperStatusLabel)
                        .font(.subheadline)
                    Spacer()
                    if helperBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        GlassActionButton(
                            title: helperActionTitle,
                            baseColor: Color.ihmsBrand,
                            foreground: .white,
                            font: .system(size: 11, weight: .semibold),
                            horizontalPadding: 12, verticalPadding: 6,
                            cornerRadius: 10, disabled: false
                        ) { installOrApproveHelper() }
                    }
                }

                if let err = helperError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }

                Divider().padding(.vertical, 14)

                // ── Advanced ────────────────────────────────────────────
                // Padding is on the DisclosureGroup itself so the chevron stays
                // vertically centred with "Advanced" (not offset by interior padding).
                DisclosureGroup(
                    isExpanded: $advancedExpanded,
                    content: {
                        VStack(spacing: 8) {
                            GlassToggleRow(
                                title: "Invert sideways scroll direction",
                                isOn: $scrollWheelInverted,
                                subtitle: "Flip the scroll direction for swipe-to-reveal on mouse horizontal scroll wheels. Enable if your mouse (e.g. Logitech MX Master side wheel) reveals in the wrong direction."
                            )

                            GlassToggleRow(
                                title: "Use legacy deletion tool (dscl + rm)",
                                isOn: $useLegacyTool,
                                subtitle: "Falls back to dscl -delete and rm -rf instead of sysadminctl. Not recommended — bypasses SecureToken and FileVault handling.",
                                warningStyle: true
                            )

                            labeledRow(title: "Log folder",
                                       hint: "Deletion logs are written here for fleet visibility.") {
                                Text(logFolder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Button("Open") {
                                    let dir = DeletionLogger.logDirectory
                                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                                    NSWorkspace.shared.open(dir)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.top, 8)
                    },
                    label: {
                        Text("Advanced")
                            .font(.headline)
                    }
                )
                .padding(.top, 18)
                .padding(.bottom, 2)

                Divider().padding(.vertical, 14)

                // ── Security & Lock ─────────────────────────────────────
                sectionHeader("Security & Lock")

                Text("Set a PIN to protect settings and restrict features on shared computers. The security PIN is a second recovery code required to change or remove the PIN.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)

                Text("Security settings are stored in /Users/Shared/ so all accounts on this Mac see the same lock. The file is created with your user as owner — students cannot delete it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)

                if let err = securityError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.bottom, 6)
                }

                if security.isPinEnabled {
                    // Feature lock toggles
                    let remoteOn = Binding<Bool>(
                        get: { security.isRemoteHostLocked },
                        set: { on in
                            do    { try security.setFeatureLocked("remoteHosts", locked: on) }
                            catch { securityError = error.localizedDescription }
                        }
                    )
                    let settingsOn = Binding<Bool>(
                        get: { security.isSettingsLocked },
                        set: { on in
                            do    { try security.setFeatureLocked("settings", locked: on) }
                            catch { securityError = error.localizedDescription }
                        }
                    )
                    let launchOn = Binding<Bool>(
                        get: { security.isLaunchLocked },
                        set: { on in
                            do    { try security.setFeatureLocked("launch", locked: on) }
                            catch { securityError = error.localizedDescription }
                        }
                    )
                    VStack(spacing: 10) {
                        GlassToggleRow(
                            title: "Require PIN on Launch",
                            isOn: launchOn,
                            subtitle: "Prompts for the PIN every time the app opens. The app stays locked until the correct PIN is entered.",
                            activeTint: Color.ihmsBrand
                        )
                        GlassToggleRow(
                            title: "Lock Remote Hosts",
                            isOn: remoteOn,
                            subtitle: "Prevents access to the Remote tab without the PIN. Useful when deployed on student computers.",
                            activeTint: Color.ihmsBrand
                        )
                        GlassToggleRow(
                            title: "Lock Settings",
                            isOn: settingsOn,
                            subtitle: "Requires the PIN to open this Settings sheet. Pair with Lock Remote Hosts to prevent students from changing any configuration.",
                            activeTint: Color.ihmsBrand
                        )
                    }
                    .padding(.bottom, 4)

                    HStack(spacing: 8) {
                        GlassActionButton(
                            title: "Change PIN…",
                            baseColor: Color.ihmsBrand.opacity(0.85),
                            foreground: .white,
                            font: .system(size: 11, weight: .semibold),
                            horizontalPadding: 12, verticalPadding: 6,
                            cornerRadius: 10, disabled: false
                        ) { showChangePin = true }

                        GlassActionButton(
                            title: "Remove PIN…",
                            baseColor: Color.red.opacity(0.75),
                            foreground: .white,
                            font: .system(size: 11, weight: .semibold),
                            horizontalPadding: 12, verticalPadding: 6,
                            cornerRadius: 10, disabled: false
                        ) { showRemovePin = true }
                    }
                    .padding(.top, 6)
                } else {
                    GlassActionButton(
                        title: "Set PIN…",
                        baseColor: Color.ihmsBrand,
                        foreground: .white,
                        font: .system(size: 12, weight: .semibold),
                        horizontalPadding: 14, verticalPadding: 7,
                        cornerRadius: 10, disabled: false
                    ) { showSetPin = true }
                }

                Divider().padding(.vertical, 14)

                // ── Protected Accounts (informational) ──────────────────
                sectionHeader("Protected Accounts")

                Text("The following accounts are always protected and cannot be deleted. K-3 shared accounts (k, g1, g2, g3) are no longer protected and can be deleted. The IHMS-reserved set and the UID floor can be overridden above; the system set is hard-coded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)

                let reserved = Config.shared.protectedUsernames.sorted()
                VStack(alignment: .leading, spacing: 4) {
                    Text("IHMS-reserved: \(reserved.joined(separator: ", "))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Operator: \(NSUserName())")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("UID floor: < \(Config.shared.minProtectedUID)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
                )

                Spacer(minLength: 20)

                HStack {
                    Spacer()
                    GlassActionButton(
                        title: "Close",
                        baseColor: Color.gray.opacity(0.55),
                        foreground: .white,
                        font: .system(size: 12, weight: .semibold),
                        horizontalPadding: 16,
                        verticalPadding: 7,
                        cornerRadius: 12,
                        disabled: false
                    ) { dismiss() }
                    Spacer()
                }
                .padding(.bottom, 4)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 460)
        .frame(minHeight: 520)
        .sheet(isPresented: $showSetPin) {
            PinManagementSheet(mode: .set) { securityError = nil }
        }
        .sheet(isPresented: $showChangePin) {
            PinManagementSheet(mode: .change) { securityError = nil }
        }
        .sheet(isPresented: $showRemovePin) {
            PinManagementSheet(mode: .remove) { securityError = nil }
        }
        .task { await refreshHelperStatus() }
    }

    // MARK: - Privileged helper

    private var helperStatusLabel: String {
        switch helperStatus {
        case .none:                     return "Checking…"
        case .installed:                return "Installed and running"
        case .notInstalled:             return "Not installed"
        case .requiresApproval:         return "Needs approval in System Settings"
        case .versionMismatch(let installed, let expected):
            return "Outdated (running \(installed), app is \(expected))"
        }
    }

    private var helperStatusColor: Color {
        switch helperStatus {
        case .none:                return .secondary
        case .installed:           return .green
        case .notInstalled:        return .red
        case .requiresApproval:    return .orange
        case .versionMismatch:     return .orange
        }
    }

    private var helperActionTitle: String {
        switch helperStatus {
        case .installed: return "Recheck"
        case .requiresApproval: return "Open Login Items…"
        default: return "Install Helper"
        }
    }

    private func refreshHelperStatus() async {
        let status = await HelperClient.shared.checkStatus()
        await MainActor.run { helperStatus = status }
    }

    private func installOrApproveHelper() {
        helperBusy  = true
        helperError = nil
        Task {
            do {
                try await HelperClient.shared.installIfNeeded()
            } catch {
                await MainActor.run { helperError = error.localizedDescription }
            }
            // Give SMAppService a moment to update its status after register()/approval.
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refreshHelperStatus()
            await MainActor.run { helperBusy = false }
        }
    }

    // MARK: - Section header

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.top, 18)
            .padding(.bottom, 8)
    }

    // MARK: - Labeled row

    @ViewBuilder
    private func labeledRow<Controls: View>(
        title: String,
        hint: String,
        @ViewBuilder controls: () -> Controls
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(hint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) { controls() }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Save helpers

    private func saveMinUID() {
        guard let uid = Int(minUID), uid >= 0 else { return }
        UserDefaults.standard.set(uid, forKey: "minProtectedUID")
    }

    private func saveTags() {
        let parse: (String) -> [String] = { raw in
            raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        UserDefaults.standard.set(parse(staffTagsText),  forKey: "staffTags")
        UserDefaults.standard.set(parse(officeTagsText), forKey: "officeTags")
        UserDefaults.standard.set(parse(adminTagsText),  forKey: "adminTags")
        UserDefaults.standard.set(staffTagsText,  forKey: "staffTagsDisplay")
        UserDefaults.standard.set(officeTagsText, forKey: "officeTagsDisplay")
        UserDefaults.standard.set(adminTagsText,  forKey: "adminTagsDisplay")
    }

}

#Preview {
    SettingsSheet()
}
