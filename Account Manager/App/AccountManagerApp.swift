//
//  AccountManagerApp.swift
//  Account Manager
//

import SwiftUI
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Quit the whole app when the main window's close button is clicked,
    /// instead of leaving it running with no windows.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct AccountManagerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Sparkle updater — kept alive for the full app lifetime. Built directly
    // (instead of SPUStandardUpdaterController) so we can supply our own
    // HybridUserDriver, which shows a native prompt for "update found" and
    // forwards everything else to Sparkle's standard driver.
    private let updater: SPUUpdater
    private let userDriver: HybridUserDriver
    // Captures the real result of an update check (the updater holds it weakly,
    // so we keep a strong reference here).
    private let updaterCoordinator = UpdaterCoordinator()

    init() {
        let coordinator = updaterCoordinator
        let driver = HybridUserDriver(hostBundle: Bundle.main)
        userDriver = driver
        updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: driver,
            delegate: coordinator
        )
        try? updater.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.sparkleUpdater, updater)
                .environment(\.updaterCoordinator, updaterCoordinator)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .accountManagerOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .appInfo) {
                Button("Version Info…") {
                    NotificationCenter.default.post(name: .accountManagerOpenVersionInfo, object: nil)
                }

                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
            }
        }
    }

    // MARK: - Appearance (veil cross-fade, identical to Library Helper)

    static func applyAppearance(_ mode: String, animated: Bool = true) {
        guard let app = NSApp else { return }

        let target: NSAppearance? = {
            switch mode {
            case "light": return NSAppearance(named: .aqua)
            case "dark":  return NSAppearance(named: .darkAqua)
            default:      return nil
            }
        }()

        guard animated else {
            app.appearance = target
            return
        }

        let isDark = { (appearance: NSAppearance?) -> Bool in
            let resolved = appearance ?? NSAppearance.currentDrawing()
            return resolved.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        let sourceIsDark = isDark(app.appearance)
        let targetIsDark = isDark(target)

        guard sourceIsDark != targetIsDark else {
            app.appearance = target
            return
        }

        let veilColor = sourceIsDark
            ? NSColor(white: 0.13, alpha: 1)
            : NSColor(white: 0.96, alpha: 1)

        let veils: [CALayer] = app.windows.compactMap { window in
            guard window.isVisible, let contentView = window.contentView else { return nil }
            contentView.wantsLayer = true
            let veil = CALayer()
            veil.backgroundColor = veilColor.cgColor
            veil.opacity = 0
            veil.zPosition = 9999
            veil.frame = contentView.bounds
            veil.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            contentView.layer?.addSublayer(veil)
            return veil
        }

        guard !veils.isEmpty else {
            app.appearance = target
            return
        }

        let fadeDuration: CFTimeInterval = 0.18

        for veil in veils {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 0; anim.toValue = 1
            anim.duration = fadeDuration
            anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
            anim.fillMode = .forwards; anim.isRemovedOnCompletion = false
            veil.add(anim, forKey: "fadeIn")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) {
            for veil in veils { veil.opacity = 1 }
            app.appearance = target

            for veil in veils {
                let anim = CABasicAnimation(keyPath: "opacity")
                anim.fromValue = 1; anim.toValue = 0
                anim.duration = fadeDuration * 1.5
                anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                anim.fillMode = .forwards; anim.isRemovedOnCompletion = false
                veil.add(anim, forKey: "fadeOut")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration * 1.5) {
                for veil in veils { veil.removeFromSuperlayer() }
            }
        }
    }
}
