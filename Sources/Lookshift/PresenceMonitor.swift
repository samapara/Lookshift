import AppKit
import LookshiftCore

/// Notices when nobody is using the Mac (idle, no face, screen locked, asleep)
/// so the camera can be turned off, and when they come back.
@MainActor
final class PresenceMonitor {
    var policy = PresencePolicy()
    /// Away checks only run while tracking, so time spent paused or calibrating never counts.
    var isTracking = false
    private(set) var isAway = false

    private var idleAway = false
    private var locked = false
    private var noFaceSince: TimeInterval?
    private let onChange: () -> Void
    private var timer: Timer?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setIdleAway(true) }
            }
        }
        let distributed = DistributedNotificationCenter.default()
        for (name, isLocked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributed.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.locked = isLocked
                    self?.update()
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func faceSeen(_ seen: Bool) {
        noFaceSince = seen ? nil : (noFaceSince ?? ProcessInfo.processInfo.systemUptime)
    }

    private func check() {
        let idle = InputActivity.secondsSinceAnyInput
        if idleAway {
            if policy.shouldResume(secondsSinceInput: idle) { setIdleAway(false) }
            return
        }
        guard isTracking else { return }
        let noFace = noFaceSince.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
        if policy.isAway(secondsSinceInput: idle, secondsWithoutFace: noFace) { setIdleAway(true) }
    }

    private func setIdleAway(_ away: Bool) {
        idleAway = away
        noFaceSince = nil
        update()
    }

    private func update() {
        let away = idleAway || locked
        guard away != isAway else { return }
        isAway = away
        Log.app.info("Presence: \(away ? "away, camera off" : "back")")
        onChange()
    }
}
