import AppKit
import Carbon
import Combine
import LookshiftCore

/// A global keyboard shortcut, stored with Carbon key codes and modifiers.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_H),
                                    modifiers: UInt32(controlKey | optionKey | cmdKey), display: "⌃⌥⌘H")

    /// nil unless the event has ⌘, ⌃ or ⌥, so plain typing can never be a global shortcut.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var carbon = 0, symbols = ""
        if flags.contains(.control) { carbon |= controlKey; symbols += "⌃" }
        if flags.contains(.option) { carbon |= optionKey; symbols += "⌥" }
        if flags.contains(.shift) { carbon |= shiftKey; symbols += "⇧" }
        if flags.contains(.command) { carbon |= cmdKey; symbols += "⌘" }
        let key = Self.keyNames[Int(event.keyCode)]
            ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        self.init(keyCode: UInt32(event.keyCode), modifiers: UInt32(carbon), display: symbols + key)
    }

    init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    private static let keyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// User preferences and the saved calibration, stored in UserDefaults on this Mac.
/// The Settings window binds to it directly; every change is saved immediately.
@MainActor
final class Settings: ObservableObject {
    private enum Key {
        static let paused = "paused"
        static let dwell = "dwell"
        static let hysteresis = "hysteresis"
        static let moveCursor = "moveCursor"
        static let typingGuard = "typingGuard"
        static let typingPause = "typingPause"
        static let idleLimit = "idleLimit"
        static let showGazeDot = "showGazeDot"
        static let windowFocus = "windowFocus"
        static let regionDelay = "regionDelay"
        static let pointCalibrations = "pointCalibrations"
        static let shortcut = "shortcut"
        static let calibration = "calibration.v2"
        static let completedSetup = "completedSetup"
    }

    @Published var paused: Bool { didSet { save(paused, Key.paused) } }
    /// Seconds the gaze must stay on a new screen before switching.
    @Published var dwell: Double { didSet { save(dwell, Key.dwell) } }
    /// Margin past the midpoint before switching; shown to users as a switch point.
    @Published var hysteresis: Double { didSet { save(hysteresis, Key.hysteresis) } }
    @Published var moveCursor: Bool { didSet { save(moveCursor, Key.moveCursor) } }
    @Published var typingGuard: Bool { didSet { save(typingGuard, Key.typingGuard) } }
    /// Seconds after the last keystroke during which switches wait.
    @Published var typingPause: Double { didSet { save(typingPause, Key.typingPause) } }
    /// Seconds without input before the camera turns off; 0 means only when no face is seen.
    @Published var idleLimit: Double { didSet { save(idleLimit, Key.idleLimit) } }
    @Published var showGazeDot: Bool { didSet { save(showGazeDot, Key.showGazeDot) } }
    /// Focus the window or pane being looked at, within a screen.
    @Published var windowFocus: Bool { didSet { save(windowFocus, Key.windowFocus) } }
    /// Seconds the gaze must stay on another window or pane before it gets focus.
    @Published var regionDelay: Double { didSet { save(regionDelay, Key.regionDelay) } }
    /// One 9-dot calibration per display, for window focus.
    @Published var pointCalibrations: [PointCalibration] {
        didSet { save(try? JSONEncoder().encode(pointCalibrations), Key.pointCalibrations) }
    }
    @Published var shortcut: Shortcut { didSet { save(try? JSONEncoder().encode(shortcut), Key.shortcut) } }
    @Published var calibration: CalibrationData? {
        didSet { save(calibration.flatMap { try? JSONEncoder().encode($0) }, Key.calibration) }
    }
    @Published var hasCompletedSetup: Bool { didSet { save(hasCompletedSetup, Key.completedSetup) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.dwell: 0.4, Key.hysteresis: 0.2, Key.moveCursor: true, Key.typingGuard: true,
            Key.typingPause: 1.0, Key.idleLimit: 120.0, Key.windowFocus: true, Key.regionDelay: 0.4,
        ])
        Self.migrateFromPrototype(into: defaults)
        paused = defaults.bool(forKey: Key.paused)
        dwell = defaults.double(forKey: Key.dwell)
        hysteresis = defaults.double(forKey: Key.hysteresis)
        moveCursor = defaults.bool(forKey: Key.moveCursor)
        typingGuard = defaults.bool(forKey: Key.typingGuard)
        typingPause = defaults.double(forKey: Key.typingPause)
        idleLimit = defaults.double(forKey: Key.idleLimit)
        showGazeDot = defaults.bool(forKey: Key.showGazeDot)
        windowFocus = defaults.bool(forKey: Key.windowFocus)
        regionDelay = defaults.double(forKey: Key.regionDelay)
        pointCalibrations = defaults.data(forKey: Key.pointCalibrations)
            .flatMap { try? JSONDecoder().decode([PointCalibration].self, from: $0) } ?? []
        shortcut = defaults.data(forKey: Key.shortcut).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .default
        calibration = defaults.data(forKey: Key.calibration).flatMap { try? JSONDecoder().decode(CalibrationData.self, from: $0) }
        hasCompletedSetup = defaults.bool(forKey: Key.completedSetup)
    }

    private func save(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
    }

    /// Carries settings and calibration over from builds named HeadFocus, which
    /// used another bundle identifier, the first time Lookshift starts.
    private static func migrateFromPrototype(into defaults: UserDefaults) {
        guard defaults.object(forKey: Key.completedSetup) == nil,
              let old = UserDefaults(suiteName: "local.headfocus"),
              old.object(forKey: Key.completedSetup) != nil || old.data(forKey: Key.calibration) != nil
        else { return }
        let keys = [Key.paused, Key.dwell, Key.hysteresis, Key.moveCursor, Key.typingGuard, Key.typingPause,
                    Key.idleLimit, Key.showGazeDot, Key.windowFocus, Key.regionDelay, Key.pointCalibrations,
                    Key.shortcut, Key.calibration, Key.completedSetup]
        for key in keys {
            if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
        }
        Log.app.info("Carried settings over from HeadFocus")
    }
}
