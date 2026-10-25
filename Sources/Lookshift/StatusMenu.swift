import AppKit

/// The eye icon in the menu bar and its menu. Preferences live in the Settings window.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    struct Actions {
        var togglePause: () -> Void
        var calibrateWindows: () -> Void
        var calibrateScreens: () -> Void
        var cancelCalibration: () -> Void
        var showSetup: () -> Void
        var showSettings: () -> Void
        var willOpen: () -> Void
    }

    struct Snapshot {
        var status: String
        var symbol: String
        var dimmed: Bool
        var needsSetup: Bool
        var paused: Bool
        var calibrating: Bool
        var canCalibrateScreens: Bool
        var shortcut: Shortcut
    }

    private let actions: Actions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusLine = NSMenuItem()
    private let readingLine = NSMenuItem()
    private let setupItem = NSMenuItem()
    private let pauseItem = NSMenuItem()
    private let calibrateWindowsItem = NSMenuItem()
    private let calibrateScreensItem = NSMenuItem()
    private let cancelItem = NSMenuItem()

    init(actions: Actions) {
        self.actions = actions
        super.init()
        build()
    }

    func update(_ s: Snapshot) {
        statusItem.button?.image = NSImage(systemSymbolName: s.symbol, accessibilityDescription: "Lookshift")
        statusItem.button?.appearsDisabled = s.dimmed
        statusItem.button?.toolTip = "Lookshift: \(s.status)"
        statusLine.title = s.status
        setupItem.isHidden = !s.needsSetup
        pauseItem.title = "\(s.paused ? "Resume" : "Pause")    \(s.shortcut.display)"
        cancelItem.isHidden = !s.calibrating
        calibrateWindowsItem.isHidden = s.calibrating
        calibrateScreensItem.isHidden = s.calibrating || !s.canCalibrateScreens
    }

    /// Updated every frame, so it touches only one item.
    func setReading(_ text: String) {
        readingLine.title = text
    }

    func menuWillOpen(_ menu: NSMenu) {
        actions.willOpen()
    }

    private func build() {
        statusLine.isEnabled = false
        readingLine.isEnabled = false
        readingLine.title = "Camera off"
        menu.addItem(statusLine)
        menu.addItem(readingLine)
        add(setupItem, "Finish Setup…", #selector(showSetup))
        menu.addItem(.separator())
        add(pauseItem, "Pause", #selector(togglePause))
        add(calibrateWindowsItem, "Calibrate Window Focus…", #selector(calibrateWindows))
        add(calibrateScreensItem, "Calibrate Screens…", #selector(calibrateScreens))
        add(cancelItem, "Cancel Calibration", #selector(cancelCalibration))
        menu.addItem(.separator())
        add(NSMenuItem(), "Settings…", #selector(showSettings), key: ",")
        add(NSMenuItem(), "Setup Guide…", #selector(showSetup))
        add(NSMenuItem(), "About Lookshift", #selector(showAbout))
        menu.addItem(NSMenuItem(title: "Quit Lookshift", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
    }

    private func add(_ item: NSMenuItem, _ title: String, _ action: Selector, key: String = "") {
        item.title = title
        item.action = action
        item.keyEquivalent = key
        item.target = self
        menu.addItem(item)
    }

    @objc private func togglePause() { actions.togglePause() }
    @objc private func calibrateWindows() { actions.calibrateWindows() }
    @objc private func calibrateScreens() { actions.calibrateScreens() }
    @objc private func cancelCalibration() { actions.cancelCalibration() }
    @objc private func showSetup() { actions.showSetup() }
    @objc private func showSettings() { actions.showSettings() }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Focus follows your eyes to the window, pane or screen you look at. Runs entirely on this Mac."),
        ])
    }
}
