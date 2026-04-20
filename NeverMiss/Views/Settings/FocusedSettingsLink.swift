import AppKit
import SwiftUI

struct FocusedSettingsLink<Label: View>: View {

    // MARK: - Properties

    @ViewBuilder let label: () -> Label

    // MARK: - Body

    var body: some View {
        SettingsLink {
            label()
        }
        .simultaneousGesture(TapGesture().onEnded {
            focusSettingsWindow()
        })
    }

    // MARK: - Private Helper Methods

    private func focusSettingsWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            bringSettingsWindowForward()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            bringSettingsWindowForward()
        }
    }

    private func bringSettingsWindowForward() {
        NSApp.activate(ignoringOtherApps: true)

        guard let settingsWindow = NSApp.windows.first(where: isSettingsWindow) else {
            return
        }

        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible, window.canBecomeKey else {
            return false
        }

        let title = window.title.lowercased()
        if title.contains("settings") || title.contains("preferences") {
            return true
        }

        let controllerType = window.contentViewController.map { String(describing: type(of: $0)) } ?? ""
        return controllerType.contains("SettingsView")
    }
}
