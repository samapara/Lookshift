import AppKit
import Combine
import LookshiftCore

/// Connects the camera, the decision logic and the UI, and decides when the camera runs.
@MainActor
final class AppController {
    private let settings = Settings()
    private let decider = Decider()
    private let regionDecider = RegionDecider()
    private let switcher = FocusSwitcher()
    private let windowFocuser = WindowFocuser()
    private let gazeDot = GazeDot()
    private let settingsContext = SettingsContext()
    private lazy var tracker = HeadTracker { [unowned self] in handle($0) }
    private lazy var presence = PresenceMonitor { [unowned self] in
        decider.reset()
        refresh()
    }
    private lazy var menu = StatusMenu(actions: menuActions)
    private lazy var hotkey = Hotkey { [unowned self] in togglePause() }
    private var setupWindow: SetupWindowController?
    private var settingsWindow: SettingsWindowController?
    private var calibrationFlow: CalibrationFlow?
    private var pointFlow: PointCalibrationFlow?
    private var displays: [DisplayInfo] = []
    /// Usable window-focus calibrations for the current displays.
    private var pointMaps: [DisplayID: PointCalibration] = [:]
    private var activeDisplayID: DisplayID?
    private var lastScreenSwitch: TimeInterval = -.infinity
    /// Permissions as last seen, to notice the moment one is granted.
    private var lastPermissions: (camera: Bool, accessibility: Bool)?
    private var focusedName: String?
    private var poll: Timer?
    private var subscriptions: Set<AnyCancellable> = []

    func start() {
        presence.start()
        tracker.onFailure = { [unowned self] in refresh() }
        registerShortcut(settings.shortcut)
        observeSettings()
        configureSettingsContext()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadDisplays() }
        }
        reloadDisplays()
        if !settings.hasCompletedSetup { showSetup() }
    }

    // MARK: - State

    private func reloadDisplays() {
        displays = Screens.active()
        decider.targets = settings.calibration.flatMap { Calibration.resolve($0.entries, for: displays) } ?? []
        pointMaps = [:]
        for display in displays {
            if let map = PointCalibration.resolve(settings.pointCalibrations, for: display, among: displays), map.isUsable {
                pointMaps[display.id] = map
            }
        }
        regionDecider.reset()
        focusedName = nil
        tracker.clearFailure()   // the lid may have just been opened
        refresh()
    }

    /// Re-evaluates everything and starts or stops the camera to match.
    private func refresh() {
        presence.policy.idleLimit = settings.idleLimit
        switcher.moveCursor = settings.moveCursor
        if !settings.windowFocus { regionDecider.reset() }

        let conditions = CameraConditions(
            calibrating: isCalibrating, paused: settings.paused, away: presence.isAway,
            displayCount: displays.count, calibrated: !decider.targets.isEmpty,
            windowFocusEnabled: settings.windowFocus, windowFocusCalibrated: !pointMaps.isEmpty,
            accessibilityGranted: Permissions.accessibility)
        let state = CameraPolicy.state(for: conditions)
        var status = describe(state)
        var problem = [.notCalibrated, .needsAccessibility].contains(state)

        if state.wantsCamera {
            switch Permissions.camera {
            case .authorized:
                if let failure = tracker.failure {
                    status = failure.message
                    problem = true
                } else {
                    tracker.start()
                }
            case .notDetermined:
                status = "Needs camera access"
                problem = true
            default:
                status = "Camera access is off"
                problem = true
            }
        }
        if !state.wantsCamera || !tracker.isRunning { tracker.stop() }
        presence.isTracking = tracker.isRunning && !isCalibrating
        if !tracker.isRunning {
            menu.setReading("Camera off")
            gazeDot.hide()
        }

        let symbol = switch state {
        case .paused: "eye.slash"
        case .away: "moon.zzz"
        default: problem ? "eye.trianglebadge.exclamationmark" : "eye"
        }
        menu.update(StatusMenu.Snapshot(
            status: status, symbol: symbol, dimmed: state == .singleDisplay || state == .away,
            needsSetup: !setupStatus.isComplete, paused: settings.paused, calibrating: isCalibrating,
            canCalibrateScreens: displays.count >= 2, shortcut: settings.shortcut))
        setupWindow?.update(setupStatus)
        bringSetupBackWhenGranted()
        updateSettingsContext()
        updatePolling()
    }

    /// Granting a permission happens in System Settings or a system prompt, which
    /// leaves the setup window behind. Bring it back so the new checkmark is seen.
    private func bringSetupBackWhenGranted() {
        let now = (camera: Permissions.camera == .authorized, accessibility: Permissions.accessibility)
        defer { lastPermissions = now }
        guard let before = lastPermissions, let setupWindow, setupWindow.isVisible else { return }
        if (now.camera && !before.camera) || (now.accessibility && !before.accessibility) {
            setupWindow.present()
        }
    }

    private func describe(_ state: CameraState) -> String {
        switch state {
        case .calibrating: "Calibrating…"
        case .paused: "Paused"
        case .away: "Away: camera off until you're back"
        case .singleDisplay: "Waiting for a second display"
        case .notCalibrated: "Not calibrated yet"
        case .needsAccessibility: "Needs Accessibility access"
        case .tracking:
            switch (screensReady, windowsReady) {
            case (true, true): "Following you across screens and windows" + (focusedName.map { " · \($0)" } ?? "")
            case (true, false): "Following you across screens" + (focusedName.map { " · \($0)" } ?? "")
            default: "Following you across windows"
            }
        }
    }

    private var isCalibrating: Bool { calibrationFlow != nil || pointFlow != nil }
    private var screensReady: Bool { displays.count >= 2 && !decider.targets.isEmpty }
    private var windowsReady: Bool { settings.windowFocus && !pointMaps.isEmpty }

    static func accuracyText(_ error: Double) -> String {
        let percent = Int((error * 100).rounded())
        return switch error {
        case ..<0.12: "Great accuracy, about ±\(percent)% of the screen. Even smaller panes should work."
        case ..<0.2: "Good accuracy, about ±\(percent)% of the screen. Side-by-side windows and split panes work well."
        default: "Rough accuracy, about ±\(percent)% of the screen. Big side-by-side windows work; calibrate again in better light for more."
        }
    }

    private var setupStatus: SetupStatus {
        let bundlePath = Bundle.main.bundleURL.path
        let applications = ["/Applications/", NSHomeDirectory() + "/Applications/"]
        let builtinMap = displays.first(where: \.isBuiltin).flatMap { pointMaps[$0.id] } ?? pointMaps.values.first
        return SetupStatus(
            camera: Permissions.camera, accessibility: Permissions.accessibility,
            hasBuiltinDisplay: displays.contains(where: \.isBuiltin),
            windowAccuracy: builtinMap.map { Self.accuracyText($0.error) },
            monitorName: displays.first { !$0.isBuiltin }?.name,
            screensCalibrated: !decider.targets.isEmpty,
            usesEyes: settings.calibration?.usesEyes ?? false,
            isInApplicationsFolder: applications.contains { bundlePath.hasPrefix($0) },
            shortcut: settings.shortcut.display)
    }

    /// Permissions are granted in System Settings while we run, with no
    /// notification; check every 1.5 s while one is missing or setup is open.
    private func updatePolling() {
        let needed = !Permissions.accessibility || setupWindow?.isVisible == true
        if needed, poll == nil {
            poll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        } else if !needed {
            poll?.invalidate()
            poll = nil
        }
    }

    // MARK: - Readings

    private func handle(_ reading: FaceReading?) {
        presence.faceSeen(reading != nil)
        if let calibrationFlow {
            calibrationFlow.feed(reading?.horizontal)
            menu.setReading(reading == nil ? "No face in view" : "Face in view")
            return
        }
        if let pointFlow {
            pointFlow.feed(reading)
            menu.setReading(reading == nil ? "No face in view" : "Following the dot")
            return
        }
        guard !settings.paused else {
            gazeDot.hide()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let typing = settings.typingGuard && InputActivity.secondsSinceKeyPress < settings.typingPause
        // While a Lookshift window is in use (setup, settings), gaze leaves focus alone.
        let usingLookshift = NSApp.isActive
        var readingText = reading == nil ? "No face in view" : "Face in view"

        // 1. Which screen.
        if screensReady, let projection = settings.calibration?.projection {
            decider.dwell = settings.dwell
            decider.hysteresis = settings.hysteresis
            let gaze = reading.map { projection.apply($0.horizontal) }
            if let gaze { readingText = String(format: "Gaze %+.2f", gaze) }
            if let id = decider.feed(gaze, at: now, blocked: typing || usingLookshift), let target = displays.first(where: { $0.id == id }) {
                switcher.focus(target, among: displays)
                focusedName = target.name
                lastScreenSwitch = now
                refresh()
            }
        }

        // 2. Which window or pane on that screen.
        var gazePoint: CGPoint?
        if settings.windowFocus, let display = activeDisplay(), let map = pointMaps[display.id] {
            if activeDisplayID != display.id {
                activeDisplayID = display.id
                regionDecider.reset()
            }
            regionDecider.dwell = settings.regionDelay
            regionDecider.margin = display.bounds.width * 0.04
            // Hands on the mouse means the user is choosing; a screen switch just moved focus already.
            let busy = typing || usingLookshift || InputActivity.secondsSinceMouse < 1
                || NSEvent.pressedMouseButtons != 0 || now - lastScreenSwitch < 0.6
            let raw = reading.map { map.point(for: $0.all, on: display) }
            let windowFocuser = windowFocuser
            if let region = regionDecider.feed(raw, at: now, blocked: busy, hitTest: { windowFocuser.region(at: $0) }) {
                windowFocuser.focus(region)
            }
            gazePoint = regionDecider.point
            if let p = gazePoint {
                readingText = String(format: "Looking at %.0f%% across, %.0f%% down",
                                     (p.x - display.bounds.minX) / display.bounds.width * 100,
                                     (p.y - display.bounds.minY) / display.bounds.height * 100)
            }
        }

        menu.setReading(readingText)
        updateGazeDot(point: gazePoint, typing: typing)
    }

    /// The display whose windows the gaze picks between: the one looked at when
    /// switching screens, otherwise the only one, otherwise the one with the cursor.
    private func activeDisplay() -> DisplayInfo? {
        if screensReady, let id = decider.current { return displays.first { $0.id == id } }
        if displays.count == 1 { return displays[0] }
        let mouse = CGEvent(source: nil)?.location ?? .zero
        return displays.first { $0.bounds.contains(mouse) }
    }

    private func updateGazeDot(point: CGPoint?, typing: Bool) {
        guard settings.showGazeDot else {
            gazeDot.hide()
            return
        }
        if let point {
            let state: GazeDot.State = regionDecider.pending == nil ? .steady : typing ? .waitingForTyping : .switching
            gazeDot.show(at: point, state: state)
        } else if screensReady, let smoothed = decider.smoothed {
            let state: GazeDot.State = decider.pending == nil ? .steady : typing ? .waitingForTyping : .switching
            gazeDot.show(at: GazeMap.point(for: smoothed, targets: decider.targets, displays: displays), state: state)
        } else {
            gazeDot.hide()
        }
    }

    // MARK: - Settings

    private func observeSettings() {
        // objectWillChange fires before the new value is stored, so apply on the next turn.
        settings.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } } }
            .store(in: &subscriptions)
        settings.$shortcut.dropFirst()
            .sink { [weak self] in self?.registerShortcut($0) }
            .store(in: &subscriptions)
    }

    private func registerShortcut(_ shortcut: Shortcut) {
        settingsContext.shortcutProblem = hotkey.register(shortcut)
            ? nil : "\(shortcut.display) is used by another app. Pick a different combination."
    }

    private func configureSettingsContext() {
        settingsContext.recalibrate = { [unowned self] in calibrateScreens() }
        settingsContext.recalibrateWindows = { [unowned self] in calibrateWindows() }
        settingsContext.setOpenAtLogin = { [unowned self] enabled in
            do {
                try LoginItem.setEnabled(enabled)
            } catch {
                alert("Couldn't change Open at Login", error.localizedDescription)
            }
            updateSettingsContext()
        }
        settingsContext.recordingShortcut = { [unowned self] recording in
            if recording { hotkey.register(nil) } else { registerShortcut(settings.shortcut) }
        }
    }

    private func updateSettingsContext() {
        let monitor = displays.first { !$0.isBuiltin }?.name
        let summary = switch (settings.calibration, monitor) {
        case (nil, _): "Not calibrated yet."
        case (let data?, let monitor?): "\(data.usesEyes ? "Head and eyes" : "Head only") · \(monitor)"
        case (let data?, nil): "\(data.usesEyes ? "Head and eyes" : "Head only") · connect your monitor to use it"
        }
        if settingsContext.calibrationSummary != summary { settingsContext.calibrationSummary = summary }
        let canCalibrate = displays.count >= 2 && displays.contains(where: \.isBuiltin) && !isCalibrating
        if settingsContext.canCalibrate != canCalibrate { settingsContext.canCalibrate = canCalibrate }
        let windowSummary = pointMaps.isEmpty ? "Not calibrated yet. Takes about 25 seconds."
            : displays.compactMap { d in pointMaps[d.id].map { "\(d.name): \(Self.accuracyText($0.error))" } }
                .joined(separator: "\n")
        if settingsContext.windowCalibrationSummary != windowSummary {
            settingsContext.windowCalibrationSummary = windowSummary
        }
        let canCalibrateWindows = displays.contains(where: \.isBuiltin) && !isCalibrating
        if settingsContext.canCalibrateWindows != canCalibrateWindows {
            settingsContext.canCalibrateWindows = canCalibrateWindows
        }
        if settingsContext.openAtLogin != LoginItem.isEnabled { settingsContext.openAtLogin = LoginItem.isEnabled }
    }

    // MARK: - Actions

    func showSetup() {
        if setupWindow == nil {
            let controller = SetupWindowController(actions: .init(
                allowCamera: { [unowned self] in requestCamera() },
                openCameraSettings: { Permissions.openCameraSettings() },
                allowAccessibility: { Permissions.requestAccessibility() },
                calibrateWindows: { [unowned self] in calibrateWindows() },
                calibrateScreens: { [unowned self] in calibrateScreens() },
                finish: { [unowned self] in
                    settings.hasCompletedSetup = true
                    setupWindow?.close()
                }))
            controller.onClose = { [unowned self] in
                settings.hasCompletedSetup = true
                updatePolling()
            }
            setupWindow = controller
        }
        setupWindow?.update(setupStatus)
        setupWindow?.present()
        updatePolling()
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings, context: settingsContext)
        }
        updateSettingsContext()
        settingsWindow?.present()
    }

    private func requestCamera() {
        Task {
            _ = await Permissions.requestCamera()
            refresh()
            setupWindow?.present()   // the system prompt took focus away
        }
    }

    private func togglePause() {
        settings.paused.toggle()
        decider.reset()
        refresh()
    }

    /// Checks the lid and camera access before any calibration; asks for access if needed.
    private func readyToCalibrate(then retry: @escaping () -> Void) -> Bool {
        guard !isCalibrating else { return false }
        guard displays.contains(where: \.isBuiltin) else {
            alert("Open your Mac's lid", "Lookshift uses the built-in camera, so the laptop needs to be open.")
            return false
        }
        switch Permissions.camera {
        case .authorized:
            tracker.clearFailure()
            gazeDot.hide()
            NSApp.activate()
            return true
        case .notDetermined:
            Task {
                if await Permissions.requestCamera() { retry() } else { refresh() }
            }
        default:
            alert("Camera access is off", "Turn on Lookshift under Camera in System Settings, then try again.",
                  button: "Open Settings", action: Permissions.openCameraSettings)
        }
        return false
    }

    private func calibrateWindows() {
        guard readyToCalibrate(then: { [unowned self] in calibrateWindows() }) else { return }
        let flow = PointCalibrationFlow(displays: displays) { [unowned self] in finishPointCalibration($0) }
        pointFlow = flow
        refresh()
        flow.start()
    }

    private func finishPointCalibration(_ outcome: PointCalibrationFlow.Outcome) {
        pointFlow = nil
        switch outcome {
        case .finished(let samplesByDisplay):
            let builtin = displays.first(where: \.isBuiltin)
            let fitted = displays.compactMap { display in
                samplesByDisplay[display.id].flatMap { PointCalibration.fit(display: display, builtin: builtin, samples: $0) }
            }
            let usable = fitted.filter(\.isUsable)
            if usable.isEmpty {
                let best = fitted.map(\.error).min().map { " (about ±\(Int(($0 * 100).rounded()))% of the screen)" } ?? ""
                alert("Not accurate enough yet",
                      "Lookshift couldn't pin down where you were looking\(best). Face the camera in even light, keep glasses free of glare, and try again.")
            } else {
                let replaced = Set(usable.map(\.displayID))
                settings.pointCalibrations = settings.pointCalibrations.filter {
                    !replaced.contains($0.displayID) && !($0.isBuiltin && usable.contains(where: \.isBuiltin))
                } + usable
                settings.windowFocus = true
                settings.paused = false
                if setupWindow?.isVisible != true {
                    let summary = usable.map { Self.accuracyText($0.error) }.joined(separator: "\n")
                    alert("Window focus is on", "\(summary)\n\nTry it: look at another window for a moment. Turn on the gaze dot in Settings to see what Lookshift sees.")
                }
            }
        case .noFace:
            alert("Couldn't see your face", "Make sure your face is lit and in view of the laptop camera, then try again.")
        case .cancelled:
            break
        }
        reloadDisplays()
    }

    private func calibrateScreens() {
        guard displays.count >= 2 else {
            return alert("Connect a monitor first", "Place it to the left or right of your Mac, then calibrate.")
        }
        guard readyToCalibrate(then: { [unowned self] in calibrateScreens() }) else { return }
        let flow = CalibrationFlow(displays: displays) { [unowned self] in finishCalibration($0) }
        calibrationFlow = flow
        refresh()
        flow.start()
    }

    private func finishCalibration(_ outcome: CalibrationFlow.Outcome) {
        calibrationFlow = nil
        switch outcome {
        case .finished(let samples):
            if let data = Calibration.build(samples) {
                settings.calibration = data
                settings.paused = false
                if setupWindow?.isVisible != true {
                    alert(data.usesEyes ? "Calibrated" : "Calibrated for head movement",
                          data.usesEyes
                            ? "Focus now follows your head and eyes. Pause any time with \(settings.shortcut.display)."
                            : "Eye movement couldn't be told apart reliably (glare on glasses or dim light can cause this), so focus follows your head. Calibrate again in better light to retry eyes.")
                }
            } else {
                alert("Couldn't tell the screens apart", "Your head and eyes barely moved between screens. Turn toward each screen when the card asks, then try again.")
            }
        case .noFace:
            alert("Couldn't see your face", "Make sure your face is lit and in view of the laptop camera, then try again.")
        case .cancelled:
            break
        }
        reloadDisplays()
    }

    private func alert(_ title: String, _ text: String, button: String? = nil, action: (() -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        if let button {
            alert.addButton(withTitle: button)
            alert.addButton(withTitle: "Cancel")
        }
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn, button != nil { action?() }
    }

    private var menuActions: StatusMenu.Actions {
        .init(
            togglePause: { [unowned self] in togglePause() },
            calibrateWindows: { [unowned self] in calibrateWindows() },
            calibrateScreens: { [unowned self] in calibrateScreens() },
            cancelCalibration: { [unowned self] in
                calibrationFlow?.cancel()
                pointFlow?.cancel()
            },
            showSetup: { [unowned self] in showSetup() },
            showSettings: { [unowned self] in showSettings() },
            willOpen: { [unowned self] in refresh() })
    }
}
