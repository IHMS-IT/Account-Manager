//
//  AccountTableView.swift
//  Account Manager
//
//  Detail pane: table + toolbar + delete (§7.3).
//

import SwiftUI

// MARK: - AccountTableView

struct AccountTableView: View {

    @Bindable var store: AccountStore
    let category: AccountCategory
    @Binding var isDeleting: Bool

    private let policy = ProtectedPolicy()

    @AppStorage("defaultDeletionMode")   private var defaultDeletionModeRaw: String = DeletionMode.accountAndFiles.rawValue
    @AppStorage("fileDeleteDefault")     private var defaultFileMethodRaw:   String = FileDeletionMethod.hard.rawValue

    @State private var filterText            = ""
    @State private var sortOrder: [KeyPathComparator<UserAccount>] = [KeyPathComparator(\.username)]
    @State private var bulkMode: DeletionMode = .accountAndFiles
    @State private var showConfirmation      = false
    @State private var deletionProgress: String? = nil
    @State private var progressIsReset       = false
    @State private var deletionResults: [DeletionResult] = []
    @State private var showResults = false
    @State private var dryRun = false
    @State private var resettingAccount: UserAccount? = nil

    private var defaultDeletionMode: DeletionMode {
        DeletionMode(rawValue: defaultDeletionModeRaw) ?? .accountAndFiles
    }
    private var defaultFileMethod: FileDeletionMethod {
        FileDeletionMethod(rawValue: defaultFileMethodRaw) ?? .hard
    }

    // MARK: - Filtered accounts for this category

    private var visibleAccounts: [UserAccount] {
        var base = store.accounts.filter { account in
            let cat = policy.category(for: account)
            switch category {
            case .all:             return account.protectionTier != .systemLocked
            case .systemProtected: return account.protectionTier == .systemLocked
            case .k3Shared:        return policy.isK3Account(account.username)
            default:               return cat == category
            }
        }
        if !filterText.isEmpty {
            let lower = filterText.lowercased()
            base = base.filter { $0.username.lowercased().contains(lower) }
        }
        return base.sorted(using: sortOrder)
    }

    private var allSelectableChecked: Bool {
        let selectable = visibleAccounts.filter { !$0.isProtected }
        return !selectable.isEmpty && selectable.allSatisfy { $0.isChecked }
    }

    private var checkedAccounts: [UserAccount] {
        visibleAccounts.filter { $0.isChecked && !$0.isProtected }
    }

    private var checkedForDeletion: [UserAccount] {
        checkedAccounts.filter { $0.deletionMode != .resetPassword }
    }

    private var checkedForReset: [UserAccount] {
        checkedAccounts.filter { $0.deletionMode == .resetPassword }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.35)
            accountTable
            Divider().opacity(0.35)
            bottomBar
        }
        .sheet(isPresented: $showConfirmation) {
            let allChecked   = store.accounts.filter { $0.isChecked && !$0.isProtected }
            let toReset      = allChecked.filter { $0.deletionMode == .resetPassword }
            let toDelete     = allChecked.filter { $0.deletionMode != .resetPassword }
            // One unified confirm sheet for both resets and deletions. It shows a
            // password field only when resetting, and the SecureToken admin fields
            // for both (needed to reset/delete FileVault accounts).
            ActionConfirmSheet(
                toReset: toReset,
                toDelete: toDelete,
                isDryRun: dryRun,
                isRemote: store.sshRunner != nil,
                onConfirm: { pwd, admin, adminPw in
                    showConfirmation = false
                    runActions(newPassword: pwd, adminUser: admin, adminPassword: adminPw)
                },
                onCancel:  { showConfirmation = false }
            )
        }
        .sheet(isPresented: $showResults) {
            DeletionResultsSheet(results: deletionResults, isDryRun: dryRun) {
                showResults = false
                Task { await store.reload() }
            }
        }
        .sheet(item: $resettingAccount) { account in
            PasswordResetSheet(account: account, store: store) {
                resettingAccount = nil
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            GlassActionButton(
                title: allSelectableChecked ? "Deselect All" : "Select All",
                baseColor: allSelectableChecked ? Color.gray.opacity(0.55) : Color.ihmsBrand,
                foreground: .white,
                font: .system(size: 12, weight: .semibold),
                horizontalPadding: 10,
                verticalPadding: 6,
                cornerRadius: 10,
                disabled: category.isReadOnly
            ) { selectAll(!allSelectableChecked) }

            HStack(spacing: 5) {
                Text("Mode:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: $bulkMode) {
                    ForEach(DeletionMode.allCases) { mode in
                        Text(mode.shortLabel).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .onChange(of: bulkMode) { _, newMode in applyBulkMode(newMode) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5))
            )

            // Manual refresh — re-reads the account list. Handy on remote hosts to
            // pick up someone logging in/out since the last load.
            Button {
                Task { await store.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh accounts")
            .disabled(store.isLoading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("Filter accounts…", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !filterText.isEmpty {
                    Button { filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5))
            )
            .frame(maxWidth: 220)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Account table

    private var accountTable: some View {
        VStack(spacing: 0) {
            if store.isLoading {
                Spacer()
                ProgressView("Loading accounts…")
                    .padding()
                Spacer()
            } else if let err = store.loadError {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(err).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Retry") { Task { await store.reload() } }
                        .buttonStyle(.bordered)
                }
                .padding()
                Spacer()
            } else {
                Table(visibleAccounts, sortOrder: $sortOrder) {
                    // Checkbox / lock column — not sortable
                    TableColumn("") { account in
                        checkboxCell(account)
                    }
                    .width(24)

                    // Sortable by username
                    TableColumn("Username", value: \.username) { account in
                        Text(account.username)
                            .foregroundStyle(account.isProtected ? .secondary : .primary)
                    }

                    // Sortable by display name
                    TableColumn("Display Name", value: \.displayNameSortKey) { account in
                        Text(account.displayName ?? "")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                    }

                    // Sortable by UID
                    TableColumn("UID", value: \.uid) { account in
                        Text("\(account.uid)")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .width(42)

                    // Sortable by home size
                    TableColumn("Home", value: \.homeSortKey) { account in
                        homeCell(account)
                    }
                    .width(min: 35, ideal: 72)

                    // Not sortable — only meaningful when checked
                    TableColumn("Mode") { account in
                        modeCellForAccount(account)
                    }
                    .width(min: 60, ideal: 85)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func checkboxCell(_ account: UserAccount) -> some View {
        if account.isPasswordLocked {
            Button { resettingAccount = account } label: {
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
            }
            .buttonStyle(.plain)
            .help("Account locked — click to reset password")
        } else if account.isProtected {
            Image(systemName: account.protectionTier == .sessionLocked ? "lock.rotation" : "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(account.protectionTier == .sessionLocked ? Color.orange : Color.secondary)
                .help(account.protectionReason ?? "Protected")
        } else {
            let isChecked = store.accounts.first(where: { $0.id == account.id })?.isChecked ?? false
            Toggle("", isOn: Binding(
                get: { store.accounts.first(where: { $0.id == account.id })?.isChecked ?? false },
                set: { newValue in
                    if let idx = store.accounts.firstIndex(where: { $0.id == account.id }) {
                        store.accounts[idx].isChecked = newValue
                        if newValue {
                            store.accounts[idx].deletionMode = bulkMode
                        }
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .tint(Color.ihmsBrand)
            .disabled(isDeleting)
            .overlay(
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(
                        isChecked ? Color.white.opacity(0.45) : Color.primary.opacity(0.22),
                        lineWidth: 1
                    )
                    .frame(width: 13, height: 13)
            )
        }
    }

    @ViewBuilder
    private func homeCell(_ account: UserAccount) -> some View {
        // Look up fresh from store so SwiftUI tracks store.accounts as a dependency
        // and re-renders this cell when homeSize is written (Table won't re-diff
        // by itself because UserAccount.== only compares id).
        let live = store.accounts.first(where: { $0.id == account.id }) ?? account
        if live.homeExists {
            if live.homeSize != nil {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(live.homeSizeString)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else if store.isLoadingHomeSizes {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 12, height: 12)
            } else {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text("No home")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func modeCellForAccount(_ account: UserAccount) -> some View {
        let isChecked = store.accounts.first(where: { $0.id == account.id })?.isChecked ?? false
        if isChecked && !account.isProtected {
            Picker("", selection: Binding(
                get: {
                    store.accounts.first(where: { $0.id == account.id })?.deletionMode ?? defaultDeletionMode
                },
                set: { newMode in
                    if let idx = store.accounts.firstIndex(where: { $0.id == account.id }) {
                        store.accounts[idx].deletionMode = newMode
                    }
                }
            )) {
                ForEach(DeletionMode.allCases) { mode in
                    Text(mode.shortLabel).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .disabled(isDeleting)
        } else {
            Text("—")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Bottom bar

    private let bottomBarPreviewColor = Color(hex: "#E88C2A")

    private var actionButtonTitle: String {
        let nReset  = checkedForReset.count
        let nDelete = checkedForDeletion.count
        let total   = checkedAccounts.count
        if total == 0 { return dryRun ? "Preview Selected" : "Delete Selected" }
        if nReset > 0 && nDelete == 0 {
            return dryRun
                ? "Preview \(nReset) Reset\(nReset == 1 ? "" : "s")…"
                : "Reset \(nReset) Password\(nReset == 1 ? "" : "s")…"
        }
        if nReset == 0 {
            return dryRun
                ? "Preview \(nDelete) Account\(nDelete == 1 ? "" : "s")…"
                : "Delete \(nDelete) Account\(nDelete == 1 ? "" : "s")…"
        }
        return dryRun
            ? "Preview \(total) Action\(total == 1 ? "" : "s")…"
            : "Run \(total) Action\(total == 1 ? "" : "s")…"
    }

    private var actionButtonColor: Color {
        if !checkedForReset.isEmpty && checkedForDeletion.isEmpty { return Color.ihmsBrand }
        if checkedForReset.isEmpty { return dryRun ? bottomBarPreviewColor : .red }
        return Color.ihmsBrand  // mixed: reset takes precedence for color
    }

    private var indicatorPulseColor: Color {
        progressIsReset ? Color.ihmsBrand : (dryRun ? bottomBarPreviewColor : .red)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            GlassToggleRow(
                title: "Preview Mode",
                isOn: $dryRun,
                subtitle: "Simulates actions — shows what would be deleted or reset without making any changes",
                activeTint: Color(hex: "#E88C2A")
            )
            .frame(maxWidth: 300)

            Spacer()

            if isDeleting {
                WatchingIndicator(
                    text: deletionProgress.map {
                        if progressIsReset { return "Resetting \($0)…" }
                        return dryRun ? "Previewing \($0)…" : "Deleting \($0)…"
                    } ?? (progressIsReset ? "Resetting…" : (dryRun ? "Previewing…" : "Deleting…")),
                    color: indicatorPulseColor
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                GlassActionButton(
                    title: actionButtonTitle,
                    baseColor: actionButtonColor,
                    foreground: .white,
                    font: .system(size: 13, weight: .semibold),
                    horizontalPadding: 16,
                    verticalPadding: 8,
                    cornerRadius: 14,
                    disabled: checkedAccounts.isEmpty || category.isReadOnly
                ) {
                    showConfirmation = true
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isDeleting)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: dryRun)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func selectAll(_ on: Bool) {
        let visibleIDs = Set(visibleAccounts.filter { !$0.isProtected }.map { $0.id })
        for i in store.accounts.indices {
            guard visibleIDs.contains(store.accounts[i].id) else { continue }
            store.accounts[i].isChecked = on
            if on { store.accounts[i].deletionMode = bulkMode }
        }
    }

    private func applyBulkMode(_ mode: DeletionMode) {
        for i in store.accounts.indices {
            if store.accounts[i].isChecked && !store.accounts[i].isProtected {
                store.accounts[i].deletionMode = mode
            }
        }
    }

    private func runActions(newPassword: String?, adminUser: String = "", adminPassword: String = "") {
        isDeleting = true
        let toReset  = checkedForReset
        let toDelete = checkedForDeletion
        let isDry    = dryRun
        let method   = defaultFileMethod
        let host     = store.sshRunner?.host.hostname ?? "local"

        Task {
            var results: [DeletionResult] = []

            // 1. Password resets
            for account in toReset {
                await MainActor.run {
                    deletionProgress = account.username
                    progressIsReset  = true
                }
                let result: DeletionResult
                do {
                    try await store.resetPassword(for: account, newPassword: newPassword ?? "",
                                                  adminUser: adminUser, adminPassword: adminPassword,
                                                  isDryRun: isDry, reloadAfter: false)
                    result = DeletionResult(username: account.username, displayName: account.displayName,
                                            mode: .resetPassword, fileMethod: .hard, success: true, error: nil)
                } catch {
                    result = DeletionResult(username: account.username, displayName: account.displayName,
                                            mode: .resetPassword, fileMethod: .hard, success: false,
                                            error: error.localizedDescription)
                }
                results.append(result)
            }

            // 2. Deletions
            if !toDelete.isEmpty {
                await MainActor.run { progressIsReset = false }
                let deleter = Deleter(sshRunner: store.sshRunner)
                deleter.isDryRun = isDry
                deleter.adminUser     = adminUser
                deleter.adminPassword = adminPassword
                let deleteResults = await deleter.deleteBatch(toDelete, fileMethod: method) { name in
                    await MainActor.run { deletionProgress = name }
                }
                results.append(contentsOf: deleteResults)
            }

            // 3. Write log
            DeletionLogger.write(results: results, isDryRun: isDry, host: host)

            await MainActor.run {
                deletionResults  = results
                isDeleting       = false
                deletionProgress = nil
                progressIsReset  = false
                showResults      = true
            }
        }
    }


}

// MARK: - Delete confirmation sheet

struct DeleteConfirmationSheet: View {
    let accounts:  [UserAccount]
    let isDryRun:  Bool
    let onConfirm: () -> Void
    let onCancel:  () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let previewColor = Color(hex: "#E88C2A")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((isDryRun ? previewColor : Color.red).opacity(0.15))
                    Image(systemName: isDryRun ? "eye.circle.fill" : "trash.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(isDryRun ? previewColor : .red)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isDryRun
                         ? "Preview Delete — \(accounts.count) Account\(accounts.count == 1 ? "" : "s")"
                         : "Delete \(accounts.count) Account\(accounts.count == 1 ? "" : "s")?")
                        .font(.title3.bold())
                    Text(isDryRun
                         ? "No changes will be made. This shows exactly what would happen."
                         : "This cannot be undone. Deleted accounts and files cannot be recovered.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            // Preview description callout
            if isDryRun {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(previewColor)
                    Text("Delete Preview simulates the deletion process — it checks which accounts are eligible, lists what would be removed, and reports any issues. No accounts or files are touched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(previewColor.opacity(colorScheme == .dark ? 0.10 : 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(previewColor.opacity(0.35), lineWidth: 0.75)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            Divider().opacity(0.35)

            // ── Two-column account list ───────────────────────────────────────
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Column headers
                    HStack(spacing: 0) {
                        Text("Account")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Action")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 140, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)

                    // Account rows — alternating, rounded
                    ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.username)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let display = account.displayName, !display.isEmpty {
                                    Text(display)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(account.deletionMode.label)
                                .font(.system(size: 11))
                                .foregroundStyle(isDryRun ? previewColor : .secondary)
                                .frame(width: 140, alignment: .leading)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(index % 2 == 0
                                      ? Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04)
                                      : Color.clear)
                        )
                        .padding(.horizontal, 6)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 260)

            Divider().opacity(0.35)

            // ── Buttons ───────────────────────────────────────────────────────
            HStack(spacing: 12) {
                GlassActionButton(
                    title: "Cancel",
                    baseColor: Color.gray.opacity(0.45),
                    foreground: .white,
                    font: .system(size: 12, weight: .semibold),
                    horizontalPadding: 16, verticalPadding: 7,
                    cornerRadius: 12, disabled: false
                ) { onCancel() }

                Spacer()

                GlassActionButton(
                    title: isDryRun ? "Run Preview" : "Delete",
                    baseColor: isDryRun ? previewColor : .red,
                    foreground: .white,
                    font: .system(size: 13, weight: .semibold),
                    horizontalPadding: 20, verticalPadding: 8,
                    cornerRadius: 12, disabled: false
                ) { onConfirm() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 420, maxWidth: 540)
    }
}

// MARK: - Action confirm sheet (resets + optional deletions)

struct ActionConfirmSheet: View {
    let toReset:   [UserAccount]
    let toDelete:  [UserAccount]
    let isDryRun:  Bool
    var isRemote:  Bool = false
    /// (newPassword, adminUser, adminPassword)
    let onConfirm: (String?, String, String) -> Void
    let onCancel:  () -> Void

    @State private var newPassword      = ""
    @State private var confirmPassword  = ""
    @State private var showNewPassword  = false
    @State private var showConfirmPassword = false
    // SecureToken (FileVault) accounts need a SecureToken admin to authorise the reset.
    @State private var adminUser         = ""
    @State private var adminPassword     = ""
    @State private var showAdminPassword = false
    @Environment(\.colorScheme) private var colorScheme

    private let previewColor = Color(hex: "#E88C2A")

    init(toReset: [UserAccount], toDelete: [UserAccount], isDryRun: Bool, isRemote: Bool = false,
         onConfirm: @escaping (String?, String, String) -> Void, onCancel: @escaping () -> Void) {
        self.toReset   = toReset
        self.toDelete  = toDelete
        self.isDryRun  = isDryRun
        self.isRemote  = isRemote
        self.onConfirm = onConfirm
        self.onCancel  = onCancel
        // Auto-fill the admin username from Settings — the password always
        // starts blank and must be entered by hand every time.
        let key = isRemote ? "defaultRemoteAdminUsername" : "defaultLocalAdminUsername"
        _adminUser = State(initialValue: UserDefaults.standard.string(forKey: key) ?? "")
    }

    private var passwordMismatch: Bool {
        !confirmPassword.isEmpty && confirmPassword != newPassword
    }

    private var canConfirm: Bool {
        let needPassword = !toReset.isEmpty && !isDryRun
        if needPassword {
            // Require a matching new password AND administrator credentials —
            // FileVault / Secure Token accounts can't be reset without them.
            return !newPassword.isEmpty && newPassword == confirmPassword
                && !adminUser.isEmpty && !adminPassword.isEmpty
        }
        return true
    }

    private var totalCount: Int { toReset.count + toDelete.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((isDryRun ? previewColor : Color.orange).opacity(0.15))
                    Image(systemName: isDryRun ? "eye.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(isDryRun ? previewColor : .orange)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isDryRun
                         ? "Preview \(totalCount) Action\(totalCount == 1 ? "" : "s")"
                         : "Run \(totalCount) Action\(totalCount == 1 ? "" : "s")?")
                        .font(.title3.bold())
                    Text(isDryRun
                         ? "No changes will be made. This shows exactly what would happen."
                         : "Review the actions below. Password resets cannot be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider().opacity(0.35)

            // ── Account list ──────────────────────────────────────────────────
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Account")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Action")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 140, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)

                    let allAccounts = toReset + toDelete
                    ForEach(Array(allAccounts.enumerated()), id: \.element.id) { index, account in
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.username)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let display = account.displayName, !display.isEmpty {
                                    Text(display)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(account.deletionMode.label)
                                .font(.system(size: 11))
                                .foregroundStyle(account.deletionMode == .resetPassword
                                                 ? .orange
                                                 : (isDryRun ? previewColor : .secondary))
                                .frame(width: 140, alignment: .leading)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(index % 2 == 0
                                      ? Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04)
                                      : Color.clear)
                        )
                        .padding(.horizontal, 6)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 220)

            Divider().opacity(0.35)

            // ── Password field (only when resetting and not dry run) ───────────
            if !toReset.isEmpty && !isDryRun {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New password for \(toReset.count == 1 ? toReset[0].username : "\(toReset.count) accounts")")
                        .font(.subheadline.weight(.semibold))

                    HStack(spacing: 8) {
                        Group {
                            if showNewPassword {
                                TextField("New password", text: $newPassword)
                            } else {
                                SecureField("New password", text: $newPassword)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button { showNewPassword.toggle() } label: {
                            Image(systemName: showNewPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 8) {
                        Group {
                            if showConfirmPassword {
                                TextField("Confirm password", text: $confirmPassword)
                            } else {
                                SecureField("Confirm password", text: $confirmPassword)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button { showConfirmPassword.toggle() } label: {
                            Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if passwordMismatch {
                        Label("Passwords do not match", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

                Divider().opacity(0.35)
            }

            // ── Administrator authorization — shown for any live action (resets
            //    AND deletions), since FileVault / Secure Token accounts need a
            //    Secure Token admin to reset or delete them. ────────────────────
            if !isDryRun {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Administrator authorization — a Secure Token admin (e.g. your IT account). Required for password resets; also needed to delete FileVault / Secure Token accounts (leave blank for standard account deletions).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    TextField("Administrator name", text: $adminUser)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()

                    HStack(spacing: 8) {
                        Group {
                            if showAdminPassword {
                                TextField("Administrator password", text: $adminPassword)
                            } else {
                                SecureField("Administrator password", text: $adminPassword)
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
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

                Divider().opacity(0.35)
            }

            // ── Buttons ───────────────────────────────────────────────────────
            HStack(spacing: 12) {
                GlassActionButton(
                    title: "Cancel",
                    baseColor: Color.gray.opacity(0.45),
                    foreground: .white,
                    font: .system(size: 12, weight: .semibold),
                    horizontalPadding: 16, verticalPadding: 7,
                    cornerRadius: 12, disabled: false
                ) { onCancel() }

                Spacer()

                GlassActionButton(
                    title: isDryRun ? "Run Preview" : "Confirm",
                    baseColor: isDryRun ? previewColor : .orange,
                    foreground: .white,
                    font: .system(size: 13, weight: .semibold),
                    horizontalPadding: 20, verticalPadding: 8,
                    cornerRadius: 12, disabled: !canConfirm
                ) { onConfirm(newPassword.isEmpty ? nil : newPassword, adminUser, adminPassword) }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 420, maxWidth: 540)
    }
}

// MARK: - Deletion results sheet

struct DeletionResultsSheet: View {
    let results: [DeletionResult]
    let isDryRun: Bool
    let onDone: () -> Void

    private let previewColor = Color(hex: "#E88C2A")

    private var resetCount:   Int { results.filter { $0.mode == .resetPassword }.count }
    private var deleteCount:  Int { results.filter { $0.mode != .resetPassword }.count }
    private var successCount: Int { results.filter(\.success).count }
    private var failureCount: Int { results.count - successCount }

    /// Every action failed (live run only — previews always "succeed").
    private var allFailed: Bool { !isDryRun && !results.isEmpty && successCount == 0 }
    /// Some but not all actions failed.
    private var someFailed: Bool { !isDryRun && failureCount > 0 && successCount > 0 }

    /// Noun describing the batch: "Password Reset", "Deletion", or "Actions".
    private var actionNoun: String {
        if resetCount > 0 && deleteCount > 0 { return "Actions" }
        if resetCount > 0 { return "Password Reset" }
        return "Deletion"
    }

    private var headerTitle: String {
        if isDryRun {
            if resetCount > 0 && deleteCount > 0 { return "Preview Complete" }
            if resetCount > 0 { return "Reset Preview Complete" }
            return "Delete Preview Complete"
        }
        if allFailed  { return "\(actionNoun) Failed" }
        if someFailed { return "\(actionNoun) — Completed with Errors" }
        return "\(actionNoun) Complete"
    }

    private var headerSubtitle: String {
        if isDryRun {
            return "\(successCount) of \(results.count) action\(results.count == 1 ? "" : "s") previewed successfully"
        }
        if failureCount > 0 {
            return "\(successCount) of \(results.count) succeeded · \(failureCount) failed"
        }
        return "\(successCount) of \(results.count) action\(results.count == 1 ? "" : "s") completed successfully"
    }

    private var headerIcon: String {
        if isDryRun   { return "eye.circle.fill" }
        if allFailed  { return "xmark.octagon.fill" }
        if someFailed { return "exclamationmark.triangle.fill" }
        return "checkmark.seal.fill"
    }

    private var headerColor: Color {
        if isDryRun   { return previewColor }
        if allFailed  { return .red }
        if someFailed { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(headerColor.opacity(0.15))
                    Image(systemName: headerIcon)
                        .font(.system(size: 26))
                        .foregroundStyle(headerColor)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerTitle)
                        .font(.title3.bold())
                    Text(headerSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(results, id: \.username) { result in
                        HStack(spacing: 8) {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.success ? .green : .red)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(result.username).font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    if let display = result.displayName, !display.isEmpty {
                                        Text(display).font(.system(size: 12)).foregroundStyle(.secondary)
                                    }
                                }
                                Text(result.mode.label).font(.caption).foregroundStyle(.secondary)
                                if let err = result.error {
                                    Text(err).font(.caption).foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)

            // Full Disk Access guidance — home-folder deletion is blocked by macOS
            // privacy protection (TCC) unless the helper has Full Disk Access.
            if hasPermissionError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange)
                        Text("macOS blocked deletion of protected folders. This almost always means the account is still logged in — its files are in use. Fully log the user out (Apple menu → Log Out, or restart), then reload and try again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("If the account is definitely logged out and it still fails, grant the helper Full Disk Access: open the pane below, click ➕, press ⌘⇧G and paste:\n/Applications/Account Manager.app/Contents/Library/LaunchDaemons/com.ihms.accountmanager.helper")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                        )
                    } label: {
                        Text("Open Full Disk Access Settings")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.orange.opacity(0.30), lineWidth: 0.75))
            }

            HStack {
                Spacer()
                GlassActionButton(
                    title: "Done",
                    baseColor: Color.ihmsBrand,
                    foreground: .white,
                    font: .system(size: 13, weight: .semibold),
                    horizontalPadding: 20,
                    verticalPadding: 8,
                    cornerRadius: 12,
                    disabled: false
                ) { onDone() }
                Spacer()
            }
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 280)
    }

    /// True if any failure looks like a macOS privacy/permission block.
    private var hasPermissionError: Bool {
        results.contains { r in
            guard !r.success, let e = r.error?.lowercased() else { return false }
            return e.contains("not permitted") || e.contains("operation not permitted")
        }
    }
}
