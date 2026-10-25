import Foundation

/// A display and the gaze value measured while looking at it during calibration.
public struct Target: Equatable, Sendable {
    public let id: DisplayID
    public let value: Double

    public init(id: DisplayID, value: Double) {
        self.id = id
        self.value = value
    }
}

/// Turns a noisy stream of gaze values into "switch to display X" decisions.
///
/// Each value is smoothed, matched to the nearest display, and only accepted as
/// a switch once it is past the midpoint by a margin (hysteresis) and has stayed
/// there for `dwell` seconds. Quick glances and jitter never move focus.
public final class Decider {
    public var targets: [Target] = [] {
        didSet {
            let sorted = targets.map(\.value).sorted()
            minGap = zip(sorted, sorted.dropFirst()).map { $1 - $0 }.min() ?? 0
            reset()
        }
    }

    /// How long the gaze must stay on a new display before switching.
    public var dwell: TimeInterval = 0.4
    /// Exponential smoothing factor: the share of each new reading that is taken in.
    public var smoothing = 0.4
    /// Margin past the midpoint, as a fraction of the smallest gap between displays.
    public var hysteresis = 0.2
    /// After this long without a face, smoothing starts over.
    public var lostTimeout: TimeInterval = 0.6

    public private(set) var current: DisplayID?
    public private(set) var smoothed: Double?
    public private(set) var pending: DisplayID?
    public private(set) var pendingSince: TimeInterval = 0

    private var minGap = 0.0
    private var lastSeen: TimeInterval = -.infinity

    public init() {}

    public func reset() {
        current = nil
        smoothed = nil
        pending = nil
    }

    /// Feeds one gaze reading (nil when no face was found) taken at time `t`.
    /// Returns a display id when focus should move there.
    /// While `blocked` (the user is typing) a switch is held back, not forgotten.
    public func feed(_ value: Double?, at t: TimeInterval, blocked: Bool = false) -> DisplayID? {
        guard targets.count >= 2 else { return nil }
        guard let value else {
            if t - lastSeen > lostTimeout {
                smoothed = nil
                pending = nil
            }
            return nil
        }
        lastSeen = t
        let s = smoothed.map { $0 + smoothing * (value - $0) } ?? value
        smoothed = s

        let choice = choose(for: s)
        if choice == current {
            pending = nil
            return nil
        }
        if pending != choice {
            pending = choice
            pendingSince = t
        }
        guard t - pendingSince >= dwell, !blocked else { return nil }
        current = choice
        pending = nil
        return choice
    }

    private func choose(for s: Double) -> DisplayID {
        var nearest = targets[0]
        for target in targets.dropFirst() where abs(target.value - s) < abs(nearest.value - s) {
            nearest = target
        }
        guard let current, current != nearest.id,
              let currentTarget = targets.first(where: { $0.id == current }) else { return nearest.id }
        let advantage = abs(currentTarget.value - s) - abs(nearest.value - s)
        return advantage < hysteresis * minGap ? current : nearest.id
    }
}
