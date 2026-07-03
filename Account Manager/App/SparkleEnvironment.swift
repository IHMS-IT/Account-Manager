//
//  SparkleEnvironment.swift
//  Account Manager
//
//  Passes the live SPUUpdater instance through the SwiftUI environment
//  so VersionInfoSheet can call checkForUpdates() without needing a
//  direct reference to the controller in AccountManagerApp.
//
//  Also hosts UpdaterCoordinator, an SPUUpdaterDelegate that captures the
//  *actual* result of an update check so the UI can reflect it truthfully
//  (instead of optimistically claiming "Up to date!").
//

import SwiftUI
import Sparkle

private struct SparkleUpdaterKey: EnvironmentKey {
    static let defaultValue: SPUUpdater? = nil
}

private struct UpdaterCoordinatorKey: EnvironmentKey {
    static let defaultValue: UpdaterCoordinator? = nil
}

extension EnvironmentValues {
    var sparkleUpdater: SPUUpdater? {
        get { self[SparkleUpdaterKey.self] }
        set { self[SparkleUpdaterKey.self] = newValue }
    }

    var updaterCoordinator: UpdaterCoordinator? {
        get { self[UpdaterCoordinatorKey.self] }
        set { self[UpdaterCoordinatorKey.self] = newValue }
    }
}

// MARK: - UpdaterCoordinator

/// Observes Sparkle's update-check lifecycle and exposes the real outcome.
/// Held strongly by the app (the updater keeps its delegate weakly).
@MainActor
@Observable
final class UpdaterCoordinator: NSObject, SPUUpdaterDelegate {

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case failed(String)
    }

    var phase: Phase = .idle

    /// Safety net so the UI never hangs on "Checking…" if Sparkle stalls or its
    /// completion callback is delayed behind a modal error dialog.
    private var watchdog: Task<Void, Never>?
    private let checkTimeout: Duration = .seconds(8)

    /// Call immediately before triggering `updater.checkForUpdates()`.
    func beginCheck() {
        phase = .checking
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: self?.checkTimeout ?? .seconds(8))
            guard let self, !Task.isCancelled else { return }
            if self.phase == .checking {
                self.phase = .failed("Update check timed out. Please try again later.")
            }
        }
    }

    /// Reset to the neutral state (e.g. when the sheet re-appears).
    func reset() {
        if phase != .checking {
            watchdog?.cancel()
            phase = .idle
        }
    }

    /// Resolve to a terminal phase and cancel the watchdog.
    private func settle(_ resolved: Phase) {
        watchdog?.cancel()
        watchdog = nil
        phase = resolved
    }

    /// Maps a Sparkle error to a terminal phase. Nonisolated so the delegate
    /// callbacks can use it before hopping to the main actor.
    nonisolated private func phase(for error: NSError) -> Phase {
        switch error.code {
        case Int(SUError.noUpdateError.rawValue):            return .upToDate
        case Int(SUError.installationCanceledError.rawValue): return .idle
        default:                                             return .failed(error.localizedDescription)
        }
    }

    // MARK: SPUUpdaterDelegate

    /// Fires as soon as the check aborts (e.g. network/appcast error) — before the
    /// user dismisses Sparkle's error dialog, so the button updates promptly.
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let resolved = phase(for: error as NSError)
        Task { @MainActor in self.settle(resolved) }
    }

    /// Fires when a valid update is found; Sparkle then presents its install UI.
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in self.settle(.updateAvailable) }
    }

    /// Final catch-all when the whole update cycle finishes.
    nonisolated func updater(_ updater: SPUUpdater,
                             didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                             error: Error?) {
        let resolved: Phase = (error as NSError?).map { phase(for: $0) } ?? .updateAvailable
        Task { @MainActor in self.settle(resolved) }
    }
}
