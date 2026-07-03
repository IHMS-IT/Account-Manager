//
//  ContentView.swift
//  Account Manager
//

import SwiftUI

// MARK: - Notification names

extension Notification.Name {
    static let accountManagerOpenSettings    = Notification.Name("accountManagerOpenSettings")
    static let accountManagerOpenVersionInfo = Notification.Name("accountManagerOpenVersionInfo")
}

// MARK: - ContentView

struct ContentView: View {

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Stores
    @State private var localStore  = AccountStore()
    @State private var remoteStore: AccountStore? = nil

    // MARK: - Navigation
    @State private var sidebarTab     = SidebarTab.local
    @State private var selectedHost: RemoteHost? = nil

    @AppStorage("lastSelectedCategory") private var localSelection:  AccountCategory = .all
    @State private var remoteSelection: AccountCategory = .all

    @AppStorage("scrollWheelInverted")      private var scrollWheelInverted: Bool = false

    // MARK: - Security
    private let security = SecurityManager.shared
    @State private var showPinForRemote   = false
    @State private var showPinForSettings = false

    // MARK: - Sheet / hover state
    @State private var showSettings      = false
    @State private var showVersionInfo   = false
    @State private var showAddHost       = false
    @State private var showHelperRequired = false
    @State private var showLaunchLock     = false
    @State private var editingHost: RemoteHost? = nil
    // Offset from 0 (closed) to -hostRowActionWidth (fully open) per host row
    @State private var hostRevealOffsets: [UUID: CGFloat] = [:]
    @State private var dragBaseOffsets:   [UUID: CGFloat] = [:]
    private let hostRowActionWidth: CGFloat = 72   // 2×30pt circles + 8pt gap + 2pt trailing pad = 70, +2 breathing room
    @State private var isVersionHovering  = false
    @State private var isSettingsHovering = false
    @State private var isDeleting         = false

    private let policy          = ProtectedPolicy()
    private let remoteHostStore = RemoteHostStore.shared

    // MARK: - Remote connection state
    enum HostConnectState: Equatable {
        case idle
        case connecting
        case failed(String)
    }
    @State private var hostConnectStates: [UUID: HostConnectState] = [:]
    @State private var connectTasks: [UUID: Task<Void, Never>] = [:]

    @Namespace private var tabNamespace

    enum SidebarTab { case local, remote }

    // MARK: - Version

    private var appVersion:        String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    private var appBuild:          String { Bundle.main.infoDictionary?["CFBundleVersion"]              as? String ?? "—" }
    private var fullVersionString: String { "\(appVersion) (\(appBuild))" }

    // MARK: - Counts

    private func count(for category: AccountCategory, in store: AccountStore) -> Int {
        store.accounts.filter { account in
            if category == .all { return account.protectionTier != .systemLocked }
            let cat = policy.category(for: account)
            return cat == category
        }.count
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
                .disabled(isDeleting)   // lock the account list & actions during a run
        }
        .navigationTitle("Account Manager")
        .frame(minWidth: 760, minHeight: 460)
        .sheet(isPresented: $showVersionInfo) {
            VersionInfoSheet(appVersion: appVersion, fullVersionString: fullVersionString,
                             isPresented: $showVersionInfo)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .sheet(isPresented: $showPinForRemote) {
            PinEntrySheet(
                title: "Remote Access Locked",
                subtitle: "Enter the PIN to access remote hosts.",
                onCorrect: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        sidebarTab = .remote
                    }
                },
                onCancel: { }
            )
        }
        .sheet(isPresented: $showPinForSettings) {
            PinEntrySheet(
                title: "Settings Locked",
                subtitle: "Enter the PIN to open settings.",
                onCorrect: { showSettings = true },
                onCancel: { }
            )
        }
        .sheet(isPresented: $showAddHost) {
            AddRemoteHostSheet { host in
                remoteHostStore.add(host)
            }
        }
        .sheet(item: $editingHost) { host in
            AddRemoteHostSheet(existing: host) { updated in
                remoteHostStore.update(updated)
                if selectedHost?.id == updated.id {
                    selectedHost = updated
                }
            }
        }
        .onChange(of: sidebarTab) { _, newTab in
            if newTab == .local { disconnectRemote() }
        }
        // Launch PIN gate — blocks the app until the correct PIN is entered.
        .sheet(isPresented: $showLaunchLock) {
            PinEntrySheet(
                title: "Account Manager Locked",
                subtitle: "Enter the PIN to unlock the app.",
                onCorrect: { showLaunchLock = false },
                onCancel:  { NSApp.terminate(nil) }   // no way past the lock except the PIN
            )
            .interactiveDismissDisabled(true)
        }
        // Privileged-helper gate — stays up until the helper is installed & enabled.
        .sheet(isPresented: $showHelperRequired) {
            HelperRequiredSheet(onInstalled: { showHelperRequired = false })
                .interactiveDismissDisabled(true)
        }
        .onAppear {
            AccountManagerApp.applyAppearance(
                UserDefaults.standard.string(forKey: "appearanceMode") ?? "auto",
                animated: false
            )
            // If a launch PIN is configured, gate the app behind it first.
            if security.isPinEnabled && security.isLaunchLocked {
                showLaunchLock = true
            }
            // Require the privileged helper before the app is usable. Check its
            // real status, and if it isn't enabled, present a blocking sheet that
            // can't be dismissed until installation completes.
            Task {
                let status = await HelperClient.shared.checkStatus()
                if case .installed = status {
                    // helper ready — nothing to do
                } else {
                    await MainActor.run { showHelperRequired = true }
                }
            }
            Task { await localStore.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountManagerOpenSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountManagerOpenVersionInfo)) { _ in
            showVersionInfo = true
        }
    }

    // MARK: - Detail content

    @ViewBuilder
    private var detailContent: some View {
        if sidebarTab == .local {
            AccountTableView(
                store: localStore,
                category: localSelection,
                isDeleting: $isDeleting
            )
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.22), value: localSelection)
        } else if let rs = remoteStore {
            AccountTableView(
                store: rs,
                category: remoteSelection,
                isDeleting: $isDeleting
            )
            .id("remote-\(selectedHost?.id.uuidString ?? "")")
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.22), value: remoteSelection)
        } else {
            // Remote tab, no host selected yet
            VStack(spacing: 14) {
                Image(systemName: "network")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("No remote host selected")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.8))
                Text("Choose a host from the sidebar to load its accounts,\nor add a new host with the + button.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Everything above the footer is locked while a run is in progress —
            // only the Version and Settings controls below stay interactive.
            Group {
                // Local / Remote tab switcher
                tabSwitcher
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                Divider().opacity(0.35).padding(.horizontal, 12)

                // Pinned host header bubble (remote + connected only)
                if sidebarTab == .remote, let host = selectedHost {
                    hostHeaderBubble(for: host)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                }

                // Scrollable sidebar body
                ScrollView(.vertical, showsIndicators: false) {
                    if sidebarTab == .local {
                        localCategoryList
                    } else {
                        remoteSidebarBody
                    }
                }
            }
            .disabled(isDeleting)

            Divider().opacity(0.35).padding(.horizontal, 12)

            // Version + Settings row
            HStack {
                Button { showVersionInfo = true } label: {
                    Text("v\(appVersion)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.7))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ultraThinMaterial)
                                if isVersionHovering {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.10)).blendMode(.overlay)
                                        .transition(.opacity)
                                }
                            }
                        )
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(isVersionHovering ? 0.30 : 0.25), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isVersionHovering = h } }

                Spacer(minLength: 8)

                Button {
                    if security.isSettingsLocked {
                        showPinForSettings = true
                    } else {
                        showSettings = true
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.7))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.ultraThinMaterial)
                                if isSettingsHovering {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.10)).blendMode(.overlay)
                                        .transition(.opacity)
                                }
                            }
                        )
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(isSettingsHovering ? 0.30 : 0.25), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isSettingsHovering = h } }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 190, idealWidth: 220, maxWidth: 280, minHeight: 300)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle().frame(width: 1).foregroundColor(Color.gray.opacity(0.2)),
            alignment: .trailing
        )
    }

    // MARK: - Tab switcher

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            tabPill("Local",  systemImage: "desktopcomputer", tab: .local)
            tabPill("Remote", systemImage: "network",         tab: .remote)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
    }

    @ViewBuilder
    private func tabPill(_ label: String, systemImage: String, tab: SidebarTab) -> some View {
        let isSelected = sidebarTab == tab
        Button {
            guard !isDeleting else { return }
            if tab == .remote && security.isRemoteHostLocked && !isSelected {
                showPinForRemote = true
                return
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                sidebarTab = tab
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .white : Color.primary.opacity(0.65))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.ihmsBrand)
                        .matchedGeometryEffect(id: "tabSlider", in: tabNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Local category list

    private var localCategoryList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(AccountCategory.allCases) { category in
                categoryRow(
                    for: category,
                    isSelected: localSelection == category,
                    badgeCount: count(for: category, in: localStore)
                ) {
                    guard !isDeleting else { return }
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                        localSelection = category
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: localSelection)
    }

    // MARK: - Remote sidebar

    @ViewBuilder
    private var remoteSidebarBody: some View {
        if let rs = remoteStore {
            // Category list only — header is pinned above the ScrollView
            VStack(alignment: .leading, spacing: 10) {
                ForEach(AccountCategory.allCases) { category in
                    categoryRow(
                        for: category,
                        isSelected: remoteSelection == category,
                        badgeCount: count(for: category, in: rs)
                    ) {
                        guard !isDeleting else { return }
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                            remoteSelection = category
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .animation(.spring(response: 0.36, dampingFraction: 0.84), value: remoteSelection)
        } else {
            // Host list
            remoteHostListView
        }
    }

    // MARK: - Connected host header bubble

    private func hostHeaderBubble(for host: RemoteHost) -> some View {
        let accent: Color = colorScheme == .dark ? Color(hex: "#6B9BE8") : Color.ihmsBrand
        let tint:   Color = host.colorTag.color ?? accent
        // Chevron is white when the bubble has a dark/saturated tint, dark otherwise
        let chevronColor: Color = colorScheme == .dark ? .white : accent
        // The entire bubble is one back button — clicking anywhere returns to the hosts list
        return Button {
            guard !isDeleting else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                disconnectRemote()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isDeleting ? chevronColor.opacity(0.35) : chevronColor)
                    .frame(width: 18, height: 18)

                // Host identity — takes all remaining width, no centering spacers
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text(host.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text("\(host.sshUser)@\(host.hostname)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(colorScheme == .dark ? 0.28 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(colorScheme == .dark ? 0.65 : 0.45), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
    }

    // MARK: - Remote host list

    private var remoteHostListView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Add host
            Button { showAddHost = true } label: {
                let addHostColor: Color = colorScheme == .dark ? Color(hex: "#6B9BE8") : Color.ihmsBrand
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(addHostColor)
                    Text("Add Host")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(addHostColor)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.22)
                                    : Color.ihmsBrand.opacity(0.38),
                                lineWidth: 0.75
                            )
                    }
                )
            }
            .buttonStyle(.plain)

            if remoteHostStore.hosts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("No remote hosts.\nTap + to add one.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
            } else {
                ForEach(remoteHostStore.hosts) { host in
                    remoteHostRow(for: host)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func remoteHostRow(for host: RemoteHost) -> some View {
        let isActive       = selectedHost?.id == host.id
        let revealOffset   = hostRevealOffsets[host.id] ?? 0
        let actionWidth    = hostRowActionWidth
        let isRevealed     = revealOffset < -actionWidth * 0.5
        let revealProgress = min(1.0, abs(revealOffset) / actionWidth)
        let rowTint: Color = host.colorTag.color ?? (colorScheme == .dark ? Color(hex: "#6B9BE8") : Color.ihmsBrand)
        let connectState   = hostConnectStates[host.id] ?? .idle
        let isConnecting   = connectState == .connecting
        let failedMessage: String? = { if case .failed(let m) = connectState { return m } else { return nil } }()

        VStack(spacing: 4) {
            ZStack(alignment: .trailing) {
                // ── Liquid-glass action bubbles ──────────────────────────────────
                HStack(spacing: 4) {
                    // Edit — slate-blue glass circle
                    Button { editingHost = host; snap(host: host, to: 0) } label: {
                        ZStack {
                            Circle().fill(.ultraThinMaterial)
                            Circle().fill(Color(hex: "#6B9BE8").opacity(0.15))
                            Circle().stroke(Color(hex: "#6B9BE8").opacity(0.55), lineWidth: 0.75)
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(hex: "#6B9BE8"))
                        }
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit host")

                    // Delete — red glass circle
                    Button {
                        if selectedHost?.id == host.id { disconnectRemote() }
                        hostConnectStates[host.id] = nil
                        connectTasks[host.id]?.cancel()
                        connectTasks[host.id] = nil
                        remoteHostStore.remove(host)
                        hostRevealOffsets[host.id] = nil
                    } label: {
                        ZStack {
                            Circle().fill(.ultraThinMaterial)
                            Circle().fill(Color.red.opacity(0.15))
                            Circle().stroke(Color.red.opacity(0.55), lineWidth: 0.75)
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete host")
                }
                .padding(.horizontal, 4)
                .opacity(revealProgress)

                // ── Host row — slides left continuously to reveal actions ─────────
                Button {
                    if isRevealed { snap(host: host, to: 0) }
                    else if !isConnecting { connectToHost(host) }
                } label: {
                    HStack(spacing: 8) {
                        // Icon: spinner while connecting, device icon otherwise
                        ZStack {
                            if isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.85)
                            } else {
                                Image(systemName: host.deviceType.systemImage)
                                    .font(.system(size: 13))
                                    .foregroundStyle(isActive ? .white : Color.primary.opacity(0.75))
                            }
                        }
                        .frame(width: 18)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(host.label)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isActive ? .white : .primary)
                                .lineLimit(1)
                            Text(isConnecting ? "Connecting…" : "\(host.sshUser)@\(host.hostname)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(isActive ? Color.white.opacity(0.75) : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .animation(.none, value: isConnecting)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            if isActive {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(rowTint.opacity(0.90))
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                            } else if host.colorTag != .none {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(rowTint.opacity(colorScheme == .dark ? 0.28 : 0.16))
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(rowTint.opacity(0.55), lineWidth: 0.5)
                            } else {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.ultraThinMaterial)
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.20), lineWidth: 0.5)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .offset(x: revealOffset)
            }

            // ── Error callout (shown below row when connection fails) ─────────
            if failedMessage != nil {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .padding(.top, 1)
                    Text("\(host.label) is unreachable. Check connection settings and try again.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation { hostConnectStates[host.id] = .idle }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(3)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 0.75)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: failedMessage != nil)
        // Click-drag (mouse): smooth tracking from gesture start position
        .gesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .local)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) else { return }
                    if dragBaseOffsets[host.id] == nil {
                        dragBaseOffsets[host.id] = hostRevealOffsets[host.id] ?? 0
                    }
                    let base = dragBaseOffsets[host.id] ?? 0
                    hostRevealOffsets[host.id] = max(-actionWidth, min(0, base + dx))
                }
                .onEnded { _ in
                    dragBaseOffsets[host.id] = nil
                    settleSnap(host: host)
                }
        )
        // Trackpad two-finger swipe + mouse scroll wheel (NSEvent monitor)
        .detectHorizontalSwipe(
            invertMouseDirection: scrollWheelInverted,
            onDelta: { delta in
                let current = hostRevealOffsets[host.id] ?? 0
                hostRevealOffsets[host.id] = max(-actionWidth, min(0, current + delta))
            },
            onSettle: { settleSnap(host: host) }
        )
        .contextMenu {
            Button("Edit Host") { editingHost = host }
            Divider()
            Button("Delete Host", role: .destructive) {
                if selectedHost?.id == host.id { disconnectRemote() }
                remoteHostStore.remove(host)
                hostRevealOffsets[host.id] = nil
            }
        }
    }

    private func snap(host: RemoteHost, to offset: CGFloat) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            hostRevealOffsets[host.id] = offset
        }
    }

    private func settleSnap(host: RemoteHost) {
        let current = hostRevealOffsets[host.id] ?? 0
        snap(host: host, to: current < -hostRowActionWidth / 2 ? -hostRowActionWidth : 0)
    }

    // MARK: - Category row (shared by local + remote)

    @ViewBuilder
    private func categoryRow(for category: AccountCategory,
                              isSelected: Bool,
                              badgeCount: Int,
                              action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SidebarToolButton(
                title: category.title,
                systemImage: category.systemImage,
                isSelected: isSelected,
                badge: badgeCount
            ) { action() }
            .opacity(isDeleting && !isSelected ? 0.4 : 1)
            .animation(.easeInOut(duration: 0.2), value: isDeleting)

            if isSelected {
                Text(category.scopeHint)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
                    .padding(.top, 2)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal:   .move(edge: .bottom).combined(with: .opacity)
                    ))
            }
        }
        .clipped()
    }

    // MARK: - Remote host session

    private func connectToHost(_ host: RemoteHost) {
        // If already connecting or connected, ignore tap
        if hostConnectStates[host.id] == .connecting { return }
        if selectedHost?.id == host.id { return }

        // Cancel any previous failed-state task for this host
        connectTasks[host.id]?.cancel()

        hostConnectStates[host.id] = .connecting

        let task = Task {
            let runner = SSHRunner(host: host)

            // 1. Fast TCP check — tells us within ~5s if the host is reachable
            let reachable = await runner.canReach(timeout: 5)
            guard !Task.isCancelled else { return }

            guard reachable else {
                await MainActor.run {
                    withAnimation { hostConnectStates[host.id] = .failed(host.label) }
                }
                autoDismissError(for: host.id)
                return
            }

            // 2. Full SSH auth check — confirms key works and sudo are available
            let authed = await runner.testConnection()
            guard !Task.isCancelled else { return }

            guard authed else {
                await MainActor.run {
                    withAnimation { hostConnectStates[host.id] = .failed(host.label) }
                }
                autoDismissError(for: host.id)
                return
            }

            // 3. Connected — load accounts
            let store = AccountStore(sshRunner: runner)
            await MainActor.run {
                hostConnectStates[host.id] = .idle
                withAnimation(.easeInOut(duration: 0.22)) {
                    selectedHost    = host
                    remoteSelection = .all
                    remoteStore     = store
                }
            }
            await store.reload()
        }
        connectTasks[host.id] = task
    }

    private func disconnectRemote() {
        if let id = selectedHost?.id {
            hostConnectStates[id] = .idle
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedHost = nil
            remoteStore  = nil
        }
    }

    private func autoDismissError(for id: UUID) {
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await MainActor.run {
                if case .failed = hostConnectStates[id] {
                    withAnimation { hostConnectStates[id] = .idle }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
