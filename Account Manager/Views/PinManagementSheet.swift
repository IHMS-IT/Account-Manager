//
//  PinManagementSheet.swift
//  Account Manager
//
//  Handles Set, Change, and Remove PIN flows in a single reusable sheet.
//

import SwiftUI

struct PinManagementSheet: View {

    enum Mode {
        case set    // Enter new PIN + security PIN (no current PIN needed)
        case change // Enter current PIN + security PIN + new PIN
        case remove // Enter current PIN + security PIN to clear
    }

    let mode: Mode
    /// Called after the operation succeeds (sheet has already been dismissed).
    let onComplete: () -> Void

    @State private var currentPin  = ""
    @State private var securityPin = ""
    @State private var newPin      = ""
    @State private var confirmPin  = ""
    @State private var error: String? = nil
    @State private var done = false

    @State private var showCurrent  = false
    @State private var showSecurity = false
    @State private var showNew      = false
    @State private var showConfirm  = false

    @FocusState private var focus: Field?
    private enum Field: Hashable { case current, security, new, confirm }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let security = SecurityManager.shared

    // Reads the actual rendered appearance (colorScheme misses NSApp overrides).
    private var brandAccent: Color { Color.brandAdaptive }

    // MARK: - Computed

    private var title: String {
        switch mode {
        case .set:    return "Set PIN"
        case .change: return "Change PIN"
        case .remove: return "Remove PIN"
        }
    }

    private var icon: String {
        switch mode {
        case .set:    return "lock.badge.plus"
        case .change: return "lock.rotation"
        case .remove: return "lock.slash"
        }
    }

    private var iconColor: Color {
        mode == .remove ? .red : brandAccent
    }

    private var canSubmit: Bool {
        switch mode {
        case .set:
            return !newPin.isEmpty && !securityPin.isEmpty && newPin == confirmPin
        case .change:
            return !currentPin.isEmpty && !securityPin.isEmpty && !newPin.isEmpty && newPin == confirmPin
        case .remove:
            return !currentPin.isEmpty && !securityPin.isEmpty
        }
    }

    private var confirmButtonTitle: String {
        switch mode {
        case .set:    return "Set PIN"
        case .change: return "Change PIN"
        case .remove: return "Remove PIN"
        }
    }

    private var doneMessage: String {
        switch mode {
        case .set:    return "PIN set. Settings are now protected."
        case .change: return "PIN changed successfully."
        case .remove: return "PIN removed. Settings are now unlocked."
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(iconColor.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(iconColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title3.bold())
                    Text(modeSubtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider().opacity(0.35)

            if done {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text(doneMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(alignment: .leading, spacing: 14) {

                    // Current PIN (change/remove only)
                    if mode == .change || mode == .remove {
                        pinField("Current PIN", placeholder: "Enter current PIN",
                                 text: $currentPin, show: $showCurrent, field: .current, next: .security)
                    }

                    // Security / recovery PIN
                    pinField(
                        "Recovery PIN",
                        placeholder: "Enter recovery PIN",
                        text: $securityPin, show: $showSecurity, field: .security,
                        next: (mode == .remove) ? nil : .new
                    )
                    Text("The recovery PIN is required along with the current PIN to change or remove the lock. Store it somewhere safe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if mode == .set || mode == .change {
                        Divider().opacity(0.3)
                        pinField("New PIN", placeholder: "Enter new PIN",
                                 text: $newPin, show: $showNew, field: .new, next: .confirm)
                        pinField("Confirm PIN", placeholder: "Re-enter new PIN",
                                 text: $confirmPin, show: $showConfirm, field: .confirm, next: nil)
                        if !confirmPin.isEmpty && newPin != confirmPin {
                            Text("PINs do not match").font(.caption).foregroundStyle(.red)
                        }
                    }

                    if let err = error {
                        Text(err).font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }

            Divider().opacity(0.35)

            HStack(spacing: 12) {
                GlassActionButton(
                    title: done ? "Done" : "Cancel",
                    baseColor: Color.gray.opacity(0.45), foreground: .white,
                    font: .system(size: 12, weight: .semibold),
                    horizontalPadding: 16, verticalPadding: 7,
                    cornerRadius: 12, disabled: false
                ) { dismiss() }

                Spacer()

                if !done {
                    GlassActionButton(
                        title: confirmButtonTitle,
                        baseColor: iconColor, foreground: .white,
                        font: .system(size: 13, weight: .semibold),
                        horizontalPadding: 20, verticalPadding: 8,
                        cornerRadius: 12, disabled: !canSubmit
                    ) { submit() }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 380, maxWidth: 460)
        .onAppear {
            focus = (mode == .set) ? .security : .current
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func pinField(_ label: String, placeholder: String,
                          text: Binding<String>, show: Binding<Bool>,
                          field: Field, next: Field?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .medium))
            HStack(spacing: 6) {
                Group {
                    if show.wrappedValue {
                        TextField(placeholder, text: text)
                    } else {
                        SecureField(placeholder, text: text)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: field)
                .onSubmit {
                    if let n = next { focus = n }
                    else if canSubmit { submit() }
                }

                Button {
                    show.wrappedValue.toggle()
                } label: {
                    Image(systemName: show.wrappedValue ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var modeSubtitle: String {
        switch mode {
        case .set:    return "Create a PIN to lock settings and features"
        case .change: return "Requires current PIN and recovery PIN"
        case .remove: return "Requires current PIN and recovery PIN"
        }
    }

    // MARK: - Submit

    private func submit() {
        error = nil
        do {
            switch mode {
            case .set:
                try security.setPin(newPin, securityPin: securityPin)
            case .change:
                try security.changePin(currentPin: currentPin, securityPin: securityPin, newPin: newPin)
            case .remove:
                try security.clearPin(currentPin: currentPin, securityPin: securityPin)
            }
            withAnimation(.easeInOut(duration: 0.22)) { done = true }
            onComplete()
        } catch {
            withAnimation { self.error = error.localizedDescription }
        }
    }
}
