import CoreGraphics

/// Turns the one-dimensional gaze value into something a person can picture.
public enum GazeMap {
    /// A point on screen for a gaze value: interpolated between the centers of
    /// the two displays whose calibrated values surround it. The gaze is one
    /// number (which screen, and how far toward the next), so the point only
    /// moves along the line between screen centers. It is held a little past
    /// the outermost screens instead of running off them.
    public static func point(for gaze: Double, targets: [Target], displays: [DisplayInfo]) -> CGPoint? {
        let anchors = targets
            .compactMap { t in displays.first { $0.id == t.id }.map { (value: t.value, center: $0.bounds.center) } }
            .sorted { $0.value < $1.value }
        guard anchors.count >= 2 else { return nil }

        var lower = anchors[0], upper = anchors[1]
        for (a, b) in zip(anchors, anchors.dropFirst()) where gaze >= a.value {
            lower = a
            upper = b
        }
        let span = upper.value - lower.value
        guard span > 1e-9 else { return lower.center }
        let t = min(max((gaze - lower.value) / span, -0.3), 1.3)
        return CGPoint(x: lower.center.x + CGFloat(t) * (upper.center.x - lower.center.x),
                       y: lower.center.y + CGFloat(t) * (upper.center.y - lower.center.y))
    }

    /// The "how far to look" setting, as a share of the way from one screen to
    /// the next (0.5 = halfway), converted to the decider's hysteresis margin.
    public static func hysteresis(forSwitchPoint point: Double) -> Double {
        min(max(2 * point - 1, 0), 0.98)
    }

    public static func switchPoint(forHysteresis hysteresis: Double) -> Double {
        (1 + hysteresis) / 2
    }
}
