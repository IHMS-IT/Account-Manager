//
//  HybridUserDriver.swift
//  Account Manager
//
//  A Sparkle SPUUserDriver that shows our own native SwiftUI prompt for the
//  "update found" moment (matching the app's design + our bundled release
//  notes), and forwards every other stage — download/extraction progress,
//  installing, errors — to Sparkle's own SPUStandardUserDriver so the
//  well-tested built-in mechanics (cancellation, retries, relaunch) are
//  unchanged.
//

import AppKit
import SwiftUI
import Sparkle

@MainActor
final class HybridUserDriver: NSObject, SPUUserDriver {

    private let standardDriver: SPUStandardUserDriver
    private var updateWindow: NSWindow?

    init(hostBundle: Bundle) {
        standardDriver = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
        super.init()
    }

    // MARK: - Our native "update found" prompt

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let newVersion     = appcastItem.displayVersionString
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let notes          = ReleaseNotesProvider.notes(for: newVersion)

        let rootView = UpdateAvailableView(
            newVersion: newVersion,
            currentVersion: currentVersion,
            notes: notes,
            onInstall: { [weak self] in
                self?.closeUpdateWindow()
                reply(.install)
            },
            onNotNow: { [weak self] in
                self?.closeUpdateWindow()
                reply(.dismiss)
            }
        )

        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "Software Update"
        window.isReleasedWhenClosed = false
        window.center()
        updateWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closeUpdateWindow() {
        updateWindow?.close()
        updateWindow = nil
    }

    // MARK: - Everything else forwards to Sparkle's standard driver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standardDriver.show(request, reply: reply)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        standardDriver.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        standardDriver.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        standardDriver.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        standardDriver.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        standardDriver.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        standardDriver.showDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        standardDriver.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        standardDriver.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        standardDriver.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        standardDriver.showExtractionReceivedProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        standardDriver.showReady(toInstallAndRelaunch: reply)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        standardDriver.showInstallingUpdate(withApplicationTerminated: applicationTerminated, retryTerminatingApplication: retryTerminatingApplication)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        standardDriver.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }

    func dismissUpdateInstallation() {
        closeUpdateWindow()
        standardDriver.dismissUpdateInstallation()
    }

    func showUpdateInFocus() {
        // Bring whichever UI is currently on screen to the front — either our
        // native prompt, or Sparkle's own progress window if that's active.
        if let updateWindow {
            updateWindow.makeKeyAndOrderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
