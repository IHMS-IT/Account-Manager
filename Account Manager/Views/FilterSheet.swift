//
//  FilterSheet.swift
//  Account Manager
//
//  Substring filter: Starts With / Contains / Ends With
//  with Add to selection, Preview, Remove from selection (§3, §7.3).
//

import SwiftUI

struct FilterSheet: View {
    let accounts: [UserAccount]
    let onAdd:    ([UserAccount]) -> Void
    let onRemove: ([UserAccount]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var matchType: FilterMatchType = .startsWith
    @State private var pattern: String = ""
    @State private var previewResults: [UserAccount] = []
    @State private var didPreview = false

    private var filter: AccountFilter {
        AccountFilter(matchType: matchType, pattern: pattern)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── Header ────────────────────────────────────────────────
            Text("Filter Selection")
                .font(.title2.bold())

            Text("Match non-protected accounts by username pattern, then add or remove them from the deletion selection.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // ── Match type ────────────────────────────────────────────
            HStack(spacing: 10) {
                ForEach(FilterMatchType.allCases) { type in
                    Button {
                        withAnimation { matchType = type }
                        didPreview = false
                    } label: {
                        Text(type.rawValue)
                            .font(.system(size: 12, weight: matchType == type ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(matchType == type
                                          ? Color.ihmsBrand.opacity(0.88)
                                          : Color.primary.opacity(0.07))
                            )
                            .foregroundStyle(matchType == type ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            // ── Pattern input ─────────────────────────────────────────
            HStack {
                TextField("Pattern (e.g. jdoe, 26, _staff)", text: $pattern)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: pattern) { _, _ in didPreview = false }

                Button("Preview") {
                    previewResults = filter.apply(to: accounts.filter { !$0.isProtected })
                    didPreview = true
                }
                .buttonStyle(.bordered)
                .disabled(pattern.isEmpty)
            }

            // ── Preview list ──────────────────────────────────────────
            if didPreview {
                VStack(alignment: .leading, spacing: 6) {
                    Text(previewResults.isEmpty
                         ? "No accounts match."
                         : "\(previewResults.count) match\(previewResults.count == 1 ? "" : "es"):")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(previewResults.isEmpty ? .secondary : .primary)

                    if !previewResults.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(previewResults) { account in
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        Text(account.username)
                                            .font(.system(size: 12, design: .monospaced))
                                        Spacer()
                                        Text("UID \(account.uid)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                        }
                        .frame(maxHeight: 160)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
                        )
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 4)

            // ── Action buttons ────────────────────────────────────────
            HStack(spacing: 10) {
                GlassActionButton(
                    title: "Add to Selection",
                    baseColor: Color.ihmsBrand,
                    foreground: .white,
                    font: .system(size: 12, weight: .semibold),
                    horizontalPadding: 12,
                    verticalPadding: 7,
                    cornerRadius: 12,
                    disabled: !didPreview || previewResults.isEmpty
                ) {
                    onAdd(previewResults)
                    dismiss()
                }

                GlassActionButton(
                    title: "Remove from Selection",
                    baseColor: Color.gray.opacity(0.55),
                    foreground: .white,
                    font: .system(size: 12, weight: .semibold),
                    horizontalPadding: 12,
                    verticalPadding: 7,
                    cornerRadius: 12,
                    disabled: !didPreview || previewResults.isEmpty
                ) {
                    onRemove(previewResults)
                    dismiss()
                }

                Spacer()

                GlassActionButton(
                    title: "Close",
                    baseColor: Color.gray.opacity(0.45),
                    foreground: .white,
                    font: .system(size: 12, weight: .semibold),
                    horizontalPadding: 12,
                    verticalPadding: 7,
                    cornerRadius: 12,
                    disabled: false
                ) { dismiss() }
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 420)
        .animation(.spring(response: 0.32, dampingFraction: 0.80), value: didPreview)
    }
}

#Preview {
    FilterSheet(accounts: [], onAdd: { _ in }, onRemove: { _ in })
}
