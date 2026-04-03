import AppKit
import SwiftUI
import Sparkle

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private var alertWindowController: AlertWindowController?
    private var launchWindow: NSWindow?
    private var showingOnboarding = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        alertWindowController = AlertWindowController.shared
        CalendarSyncManager.shared.startPeriodicSync()
        NeverMissApp.updaterController.startUpdater()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.showLaunchWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        CalendarSyncManager.shared.stopPeriodicSync()
        MeetingScheduler.shared.cancelAllAlerts()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showLaunchWindow()
        }
        return true
    }

    // MARK: - Private Helpers

    private func showLaunchWindow() {
        if let window = launchWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        showingOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        let rootView: AnyView = showingOnboarding
            ? AnyView(OnboardingView())
            : AnyView(LaunchView())
        let size = showingOnboarding
            ? NSSize(width: 540, height: 520)
            : NSSize(width: 400, height: 300)

        let hostingController = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "NeverMiss"
        window.styleMask = [.titled, .closable]
        window.setContentSize(size)
        window.center()
        window.delegate = self

        self.launchWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSWindowDelegate

@MainActor
extension AppDelegate: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === launchWindow {
            let justFinishedOnboarding = showingOnboarding && SettingsManager.shared.hasCompletedOnboarding
            launchWindow = nil

            if justFinishedOnboarding {
                showLaunchWindow()
            } else {
                hideAppMenuIfSafe()
            }
        } else {
            DispatchQueue.main.async {
                let hasVisibleWindows = NSApp.windows.contains { $0.isVisible && $0.title != "" }
                if !hasVisibleWindows {
                    self.hideAppMenuIfSafe()
                }
            }
        }
    }

    private func hideAppMenuIfSafe() {
        if SettingsManager.shared.showMenuBarIcon {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
