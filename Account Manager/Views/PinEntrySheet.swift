//
//  PinEntrySheet.swift
//  Account Manager
//
//  Reusable PIN prompt shown when the user tries to access a locked feature.
//

import SwiftUI

struct PinEntrySheet: View {

    let title:    String
    let subtitle: String
    /// Called when the correct PIN is entered. The sheet is dismissed first.
    let onCorrect: () -> Void
    /// If nil, the Cancel button is hidden (non-dismissable gate).
    let onCancel: (() -> Void)?

    @State private var pin      = ""
    @State private var shake    = false
    @State private var isWrong  = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let security = SecurityManager.shared

    // Reads the actual rendered appearance (colorScheme misses NSApp overrides).
    private var accent: Color { Color.brandAdaptive }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 4)

            ZStack {
                Circle()
                    .fill(accent.opacity(colorScheme == .dark ? 0.20 : 0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(accent)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            SecureField("Enter PIN", text: $pin)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .focused($focused)
                .onSubmit { attempt() }
                .offset(x: shake ? -6 : 0)
                .animation(.interpolatingSpring(stiffness: 600, damping: 8), value: shake)

            if isWrong {
                Text("Incorrect PIN — try again")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 12) {
                if let cancel = onCancel {
                    GlassActionButton(
                        title: "Cancel",
                        baseColor: Color.gray.opacity(0.45),
                        foreground: .white,
                        font: .system(size: 12, weight: .semibold),
                        horizontalPadding: 16, verticalPadding: 7,
                        cornerRadius: 12, disabled: false
                    ) {
                        cancel()
                        dismiss()
                    }
                }

                GlassActionButton(
                    title: "Unlock",
                    baseColor: Color.ihmsBrand,
                    foreground: .white,
                    font: .system(size: 13, weight: .semibold),
                    horizontalPadding: 20, verticalPadding: 8,
                    cornerRadius: 12,
                    disabled: pin.isEmpty
                ) { attempt() }
            }

            Spacer(minLength: 4)
        }
        .padding(32)
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .onAppear { focused = true }
        .animation(.easeInOut(duration: 0.18), value: isWrong)
    }

    private func attempt() {
        if security.verify(pin: pin) {
            dismiss()
            onCorrect()
        } else {
            pin = ""
            withAnimation {
                isWrong = true
                shake   = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { shake = false }
        }
    }
}
