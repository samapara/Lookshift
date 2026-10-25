import Foundation

/// Everything that decides whether the camera should run.
public struct CameraConditions: Equatable, Sendable {
    public var calibrating = false
    public var paused = false
    public var away = false
    public var displayCount = 1
    /// Screen switching is calibrated for the current displays.
    public var calibrated = false
    public var windowFocusEnabled = false
    /// Window focus is calibrated for at least one current display.
    public var windowFocusCalibrated = false
    public var accessibilityGranted = false

    public init(calibrating: Bool = false, paused: Bool = false, away: Bool = false, displayCount: Int = 1,
                calibrated: Bool = false, windowFocusEnabled: Bool = false, windowFocusCalibrated: Bool = false,
                accessibilityGranted: Bool = false) {
        self.calibrating = calibrating
        self.paused = paused
        self.away = away
        self.displayCount = displayCount
        self.calibrated = calibrated
        self.windowFocusEnabled = windowFocusEnabled
        self.windowFocusCalibrated = windowFocusCalibrated
        self.accessibilityGranted = accessibilityGranted
    }

    /// Switching between screens can run.
    public var screensReady: Bool { displayCount >= 2 && calibrated }
    /// Focusing the window or pane looked at can run.
    public var windowsReady: Bool { windowFocusEnabled && windowFocusCalibrated }
}

public enum CameraState: Equatable, Sendable {
    case calibrating, paused, away, singleDisplay, notCalibrated, needsAccessibility, tracking

    /// The camera (and its green light) is on only while it is actually needed.
    public var wantsCamera: Bool { self == .calibrating || self == .tracking }
}

public enum CameraPolicy {
    /// The first matching rule wins.
    public static func state(for c: CameraConditions) -> CameraState {
        if c.calibrating { return .calibrating }
        if c.paused { return .paused }
        if c.away { return .away }
        if !c.screensReady && !c.windowsReady {
            // One screen and window focus off: there's nothing to do.
            return c.displayCount < 2 && !c.windowFocusEnabled ? .singleDisplay : .notCalibrated
        }
        if !c.accessibilityGranted { return .needsAccessibility }
        return .tracking
    }
}

/// When to turn the camera off because nobody is using the Mac.
public struct PresencePolicy: Equatable, Sendable {
    /// No keyboard or mouse input for this long means away. 0 turns this rule off.
    public var idleLimit: TimeInterval = 120
    /// No face for this long, with no input for `noFaceInputGrace`, means away.
    public var noFaceLimit: TimeInterval = 20
    public var noFaceInputGrace: TimeInterval = 10
    /// Any input within this many seconds brings the camera back.
    public var resumeWithin: TimeInterval = 2.5

    public init(idleLimit: TimeInterval = 120) {
        self.idleLimit = idleLimit
    }

    public func isAway(secondsSinceInput idle: TimeInterval, secondsWithoutFace noFace: TimeInterval) -> Bool {
        (idleLimit > 0 && idle > idleLimit) || (noFace > noFaceLimit && idle > noFaceInputGrace)
    }

    public func shouldResume(secondsSinceInput idle: TimeInterval) -> Bool {
        idle < resumeWithin
    }
}
