import CoreGraphics
import Foundation

/// A window or pane that can take focus, in global coordinates.
public struct Region: Equatable, Sendable {
    public let id: String
    public let frame: CGRect

    public init(id: String, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

/// Decides when the gaze has settled on a different window or pane.
///
/// The gaze point is smoothed; the current region keeps focus while the point
/// stays inside it plus a margin, so wobble near an edge doesn't flip focus; and
/// a new region must hold the gaze for `dwell` seconds before it takes over.
public final class RegionDecider {
    public var dwell: TimeInterval = 0.4
    /// Share of each new point that is taken in. Lower is steadier and slower.
    public var smoothing = 0.3
    /// How far outside the current region (in points) the gaze may wander before it counts as leaving.
    public var margin: CGFloat = 40
    public var lostTimeout: TimeInterval = 0.6

    public private(set) var current: Region?
    public private(set) var pending: Region?
    public private(set) var pendingSince: TimeInterval = 0
    public private(set) var point: CGPoint?

    private var lastSeen: TimeInterval = -.infinity

    public init() {}

    public func reset() {
        current = nil
        pending = nil
        point = nil
    }

    /// Feeds a raw gaze point. `hitTest` finds the region under a point and is only
    /// called when the gaze has left the current region, since it can be slow.
    /// Returns a region when focus should move there.
    public func feed(_ raw: CGPoint?, at t: TimeInterval, blocked: Bool = false,
                     hitTest: (CGPoint) -> Region?) -> Region? {
        guard let raw else {
            if t - lastSeen > lostTimeout {
                point = nil
                pending = nil
            }
            return nil
        }
        lastSeen = t
        let p = point.map { CGPoint(x: $0.x + smoothing * (raw.x - $0.x), y: $0.y + smoothing * (raw.y - $0.y)) } ?? raw
        point = p

        if let current, current.frame.insetBy(dx: -margin, dy: -margin).contains(p) {
            pending = nil
            return nil
        }
        guard let hit = hitTest(p) else {
            pending = nil
            return nil
        }
        if hit.id == current?.id {
            current = hit
            pending = nil
            return nil
        }
        if pending?.id != hit.id {
            pending = hit
            pendingSince = t
        }
        guard t - pendingSince >= dwell, !blocked else { return nil }
        current = hit
        pending = nil
        return hit
    }

    /// Tells the decider which region has focus now, e.g. after the user clicked somewhere.
    public func adopt(_ region: Region?) {
        current = region
        pending = nil
    }
}
