//
//  PasswordResetSheet.swift
//  Account Manager
//
//  Sheet for resetting the password of a macOS user account.
//  Works for both local (via dscl) and remote (via SSH) accounts.
//

import SwiftUI

struct PasswordResetSheet: View {

    let account:   UserAccount
    let store:     AccountStore
    let onDismiss: () -> Void

    @State private var newPassword         = ""
    @State private var confirmPassword     = ""
    @State private var showNewPassword     = false
    @State private var showConfirmPassword = false
    @State private var isResetting         = false
    @State private var errorMessage:       String? = nil
    @State private var succeeded           = false

    // SecureToken (FileVault) accounts require a SecureToken admin to authorise
    // the reset. These fields are revealed when macOS reports that requirement.
    @State private var adminUser           = ""
    @State private var adminPassword       = ""
    @State private var showAdminPassword   = false
    @State private var showAdminFields     = false

    @FocusState private var focus: Field?
    private enum Field { case new, confirm }

    private var isRemote: Bool { store.sshRunner != nil }

    private var canSubmit: Bool {
        !newPassword.isEmpty && newPassword == confirmPassword && !isResetting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.orange.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: succeeded ? "key.fill" : "key.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(succeeded ? .green : .orange)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(succeeded ? "Password Reset" : "Reset Password")
                        .font(.title3.bold())
                    if let display = account.displayName {
                        Text("\(account.username) · \(display)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text(account.username)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider().opacity(0.35)

            if succeeded {
                // Success state
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("Password successfully reset.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if account.isPasswordLocked {
                        Text("The account lockout has been cleared.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                // Form
                VStack(alignment: .leading, spacing: 14) {

                    if account.isPasswordLocked {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.orange)
                            Text("This account is locked due to too many failed login attempts. Resetting the password will unlock it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.orange.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.orange.opacity(0.35), lineWidth: 0.75)
                        )
                    }

                    if isRemote {
                        HStack(spacing: 8) {
                            Image(systemName: "network")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("Remote reset via SSH — requires the SSH user to have admin sudo access.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("New Password").font(.system(size: 12, weight: .medium))
                        HStack(spacing: 6) {
                            Group {
                                if showNewPassword {
                                    TextField("New password", text: $newPassword)
                                } else {
                                    SecureField("New password", text: $newPassword)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .new)
                            .onSubmit { focus = .confirm }

                            Button { showNewPassword.toggle() } label: {
                                Image(systemName: showNewPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Confirm Password").font(.system(size: 12, weight: .medium))
                        HStack(spacing: 6) {
                            Group {
                                if showConfirmPassword {
                                    TextField("Confirm password", text: $confirmPassword)
                                } else {
                                    SecureField("Confirm password", text: $confirmPassword)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .confirm)
                            .onSubmit { if canSubmit { runReset() } }

                            Button { showConfirmPassword.toggle() } label: {
                                Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        if !confirmPassword.isEmpty && newPassword != confirmPassword {
                            Text("Passwords do not match")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    if !isRemote {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield")
                                    .font(.system(size: 12))
                                    .foregroundStyle(showAdminFields ? .orange : .secondary)
                                Text(showAdminFields
                                     ? "This account uses FileVault / Secure Token. Enter a Secure Token administrator (e.g. your IT admin account) to authorise the reset."
                                     : "Administrator authorization — required only for FileVault / Secure Token accounts. Leave blank otherwise.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Administrator Name").font(.system(size: 12, weight: .medium))
                                TextField("admin username", text: $adminUser)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Administrator Password").font(.system(size: 12, weight: .medium))
                                HStack(spacing: 6) {
                                    Group {
                                        if showAdminPassword {
                                            TextField("admin password", text: $adminPassword)
                                        } else {
                                            SecureField("admin password", text: $adminPassword)
                                        }
                                    }
                                    .textFieldStyle(.roundedBorder)
                                    Button { showAdminPassword.toggle() } label: {
                                        Image(systemName: showAdminPassword ? "eye.slash" : "eye")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.orange.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.orange.opacity(0.30), lineWidth: 0.75)
                        )
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            Divider().opacity(0.35)

            // Buttons
            HStack(spacing: 12) {
                GlassActionButton(
                    title: succeeded ? "Done" : "Cancel",
                    baseColor: Color.gray.opacity(0.45),
                    foreground: .white,
                    font: .system(size: 12, weight: .semibold),
                    horizontalPadding: 16, verticalPadding: 7,
                    cornerRadius: 12, disabled: false
                ) { onDismiss() }

                Spacer()

                if !succeeded {
                    if isResetting {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 16)
                    } else {
                        GlassActionButton(
                            title: "Reset Password",
                            baseColor: .orange,
                            foreground: .white,
                            font: .system(size: 13, weight: .semibold),
                            horizontalPadding: 20, verticalPadding: 8,
                            cornerRadius: 12, disabled: !canSubmit
                        ) { runReset() }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 380, maxWidth: 480)
        .onAppear { focus = .new }
    }

    private func runReset() {
        guard canSubmit else { return }
        isResetting  = true
        errorMessage = nil
        let pwd     = newPassword
        let admin   = adminUser
        let adminPw = adminPassword
        Task {
            do {
                try await store.resetPassword(for: account, newPassword: pwd,
                                              adminUser: admin, adminPassword: adminPw)
                await MainActor.run {
                    isResetting = false
                    succeeded   = true
                }
            } catch {
                await MainActor.run {
                    isResetting  = false
                    errorMessage = error.localizedDescription
                    // Any failed local reset most likely means the account needs a
                    // SecureToken admin to authorise it, so reveal the admin fields
                    // for a retry. (Remote resets go over SSH and don't use them.)
                    if !isRemote { withAnimation { showAdminFields = true } }
                }
            }
        }
    }
}
