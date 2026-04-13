import AppKit
import AVFoundation
import SwiftUI

@Observable
@MainActor
final class AlertWindowController {
    static let shared = AlertWindowController()

    // MARK: - Properties

    var isShowingAlert = false
    var skipRequested = false
    var snoozeRequested = false

    @ObservationIgnored private var windows: [NSWindow] = []
    @ObservationIgnored private var currentEvent: CalendarEvent?
    @ObservationIgnored private var currentTiming: AlertTiming?

    @ObservationIgnored private let settings = SettingsManager.shared
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var eventMonitor: Any?

    @ObservationIgnored private var showAlertObserver: Any?
    @ObservationIgnored private var screenObserver: Any?

    // MARK: - Init

    private init() {
        setupNotificationObservers()
    }

    deinit {
        if let observer = showAlertObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public API

    func showAlert(for event: CalendarEvent, timing: AlertTiming) {
        guard !isShowingAlert else { return }

        currentEvent = event
        currentTiming = timing
        isShowingAlert = true

        playAlertSound()

        let popupMode = settings.popupMode
        // Banner mode always shows on main screen only, regardless of multi-monitor setting
        let screens: [NSScreen] = if popupMode == .banner {
            [NSScreen.main].compactMap { $0 }
        } else {
            screensForDisplay()
        }

        for screen in screens {
            let window = createWindow(for: screen, event: event, timing: timing, mode: popupMode)
            windows.append(window)

            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)

            // For native full screen, toggle after showing
            if popupMode == .nativeFullScreen {
                window.toggleFullScreen(nil)
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        }

        // Activate app so keyboard shortcuts work when alert appears over other apps
        NSApp.activate()

        setupKeyboardShortcuts()
    }

    func dismissAlert(animated: Bool = true) {
        guard isShowingAlert else { return }

        stopSound()
        removeKeyboardShortcuts()

        let dismissAction = { [weak self] in
            guard let self else { return }
            for window in self.windows {
                // Exit native full screen before closing if needed
                if (window.styleMask.contains(.fullScreen)) {
                    window.toggleFullScreen(nil)
                    // Delay close slightly to allow fullscreen exit animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        window.close()
                    }
                } else {
                    window.close()
                }
            }
            self.windows.removeAll()
            self.currentEvent = nil
            self.currentTiming = nil
            self.isShowingAlert = false
        }

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                windows.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: dismissAction)
        } else {
            dismissAction()
        }
    }

    // MARK: - Private Methods

    private func createWindow(for screen: NSScreen, event: CalendarEvent, timing: AlertTiming, mode: PopupMode) -> NSWindow {
        let window: NSWindow

        switch mode {
        case .nativeFullScreen:
            window = createNativeFullScreenWindow(for: screen)

        case .overlay:
            window = createOverlayPanel(for: screen)

        case .coverScreen:
            window = createCoverScreenPanel(for: screen)

        case .banner:
            window = createBannerPanel(for: screen)
        }

        // Banner uses BannerAlertView directly; other modes wrap in AlertWrapperView
        if mode == .banner {
            let bannerView = BannerAlertView(
                event: event,
                timing: timing,
                onJoin: { [weak self] in self?.handleJoin() },
                onSnooze: { [weak self] snoozeTime in self?.dismissAndSnooze(until: snoozeTime) },
                onDismiss: { [weak self] in self?.handleDismiss() }
            )
            installHostingView(bannerView, in: window)
        } else {
            let contentView = AlertWrapperView(
                event: event,
                timing: timing,
                popupMode: mode,
                onJoin: { [weak self] in self?.handleJoin() },
                onSnooze: { [weak self] snoozeTime in self?.dismissAndSnooze(until: snoozeTime) },
                onDismiss: { [weak self] in self?.handleDismiss() }
            )
            installHostingView(contentView, in: window)
        }

        return window
    }

    /// Native macOS full screen: uses NSWindow with fullscreen capability
    private func createNativeFullScreenWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.setFrame(screen.frame, display: true)
        return window
    }

    /// Overlay: FloatingPanel-style NSPanel that sits above everything
    private func createOverlayPanel(for screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        // Hide traffic light buttons
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setFrame(screen.frame, display: true)
        return panel
    }

    /// Cover screen: borderless NSPanel filling the screen
    private func createCoverScreenPanel(for screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.setFrame(screen.frame, display: true)
        return panel
    }

    /// Banner: compact floating panel at the top-center of the screen
    private func createBannerPanel(for screen: NSScreen) -> NSPanel {
        let panelWidth: CGFloat = 420
        let panelHeight: CGFloat = 100
        let topInset: CGFloat = 20

        let screenFrame = screen.visibleFrame
        let originX = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
        let originY = screenFrame.origin.y + screenFrame.height - panelHeight - topInset

        let panelRect = NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight)

        let panel = NSPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        // Hide traffic light buttons
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setFrame(panelRect, display: true)
        return panel
    }

    private func installHostingView<Content: View>(_ rootView: Content, in window: NSWindow) {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(hostingView)
    }

    private func screensForDisplay() -> [NSScreen] {
        switch settings.multiMonitorOption {
        case .allScreens:
            return NSScreen.screens
        case .mainScreenOnly:
            return [NSScreen.main].compactMap { $0 }
        case .primaryMonitor:
            return [NSScreen.screens.first].compactMap { $0 }
        }
    }

    private func handleJoin() {
        if let eventId = currentEvent?.id {
            MeetingScheduler.shared.cancelAlerts(for: eventId)
        }

        guard let event = currentEvent,
              let linkString = event.meetingLink,
              let url = URL(string: linkString) else {
            dismissAlert()
            MeetingScheduler.shared.dismissCurrentAlert()
            return
        }

        NSWorkspace.shared.open(url)
        dismissAlert()
        MeetingScheduler.shared.dismissCurrentAlert()
    }

    private func dismissAndSnooze(until when: Date) {
        dismissAlert()
        MeetingScheduler.shared.snoozeCurrentAlert(until: when)
    }

    private func handleDismiss() {
        if let eventId = currentEvent?.id {
            MeetingScheduler.shared.cancelAlerts(for: eventId)
        }
        dismissAlert()
        MeetingScheduler.shared.dismissCurrentAlert()
    }

    private func playAlertSound() {
        guard settings.soundSettings.isEnabled else { return }

        let soundName = settings.soundSettings.soundName

        if let url = Bundle.main.url(forResource: soundName, withExtension: "aiff") {
            playSound(from: url)
        } else if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.volume = settings.soundSettings.volume
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func playSound(from url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = settings.soundSettings.volume
            audioPlayer?.play()
        } catch {
            NSSound.beep()
        }
    }

    private func stopSound() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func setupKeyboardShortcuts() {
        guard settings.keyboardShortcutsEnabled else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.isShowingAlert == true,
                  let binding = AlertKeyBinding.from(keyCode: event.keyCode)
            else { return event }

            switch binding {
            case .join:   self?.handleJoin()
            case .snooze: self?.snoozeRequested = true
            case .skip:   self?.skipRequested = true
            }
            return nil
        }
    }

    private func removeKeyboardShortcuts() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func setupNotificationObservers() {
        showAlertObserver = NotificationCenter.default.addObserver(
            forName: .showMeetingAlert,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let userInfo = notification.userInfo,
                      let event = userInfo["event"] as? CalendarEvent,
                      let timing = userInfo["timing"] as? AlertTiming else {
                    return
                }
                self.showAlert(for: event, timing: timing)
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenConfigurationChange()
            }
        }
    }

    private func handleScreenConfigurationChange() {
        guard isShowingAlert,
              let event = currentEvent,
              let timing = currentTiming else { return }

        // Close all existing windows immediately
        for window in windows {
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    window.close()
                }
            } else {
                window.close()
            }
        }
        windows.removeAll()

        // Recreate for current screen configuration
        let popupMode = settings.popupMode
        let screens: [NSScreen] = if popupMode == .banner {
            [NSScreen.main].compactMap { $0 }
        } else {
            screensForDisplay()
        }

        for screen in screens {
            let window = createWindow(for: screen, event: event, timing: timing, mode: popupMode)
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
            if popupMode == .nativeFullScreen {
                window.toggleFullScreen(nil)
            }
        }
    }
}
