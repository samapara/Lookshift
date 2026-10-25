import Foundation

public struct CalibrationEntry: Codable, Equatable, Sendable {
    public let displayID: DisplayID
    public let value: Double
    /// Standard deviation of the projected samples.
    public let spread: Double
    /// The display's horizontal center when it was calibrated.
    public let centerX: Double
    public let isBuiltin: Bool

    public init(displayID: DisplayID, value: Double, spread: Double, centerX: Double, isBuiltin: Bool) {
        self.displayID = displayID
        self.value = value
        self.spread = spread
        self.centerX = centerX
        self.isBuiltin = isBuiltin
    }
}

public struct CalibrationData: Codable, Equatable, Sendable {
    public let projection: Projection
    public let entries: [CalibrationEntry]
    public let usesEyes: Bool
}

/// Readings recorded while looking at one display.
public struct CalibrationSamples: Sendable {
    public let display: DisplayInfo
    /// Head turned naturally toward the display.
    public var natural: [Features] = []
    /// Head kept facing elsewhere, eyes on the display.
    public var eyesOnly: [Features] = []

    public init(display: DisplayInfo, natural: [Features] = [], eyesOnly: [Features] = []) {
        self.display = display
        self.natural = natural
        self.eyesOnly = eyesOnly
    }
}

public enum Calibration {
    /// Feature mask that keeps only the head-turn signal.
    public static let headOnly = [true, false, false]

    /// Learns a head + eyes gaze axis when that separates the displays cleanly,
    /// otherwise falls back to head turn alone. Returns nil if neither works.
    public static func build(_ samples: [CalibrationSamples]) -> CalibrationData? {
        guard let builtin = samples.first(where: { $0.display.isBuiltin }) else { return nil }
        let headCenter = { (features: [Features]) in
            features.map { $0[0] }.reduce(0, +) / Double(max(features.count, 1))
        }
        let laptopHead = headCenter(builtin.natural)
        // With several external displays, fit against the one farthest from the laptop.
        guard let far = samples.filter({ !$0.display.isBuiltin })
            .max(by: { abs(headCenter($0.natural) - laptopHead) < abs(headCenter($1.natural) - laptopHead) })
        else { return nil }

        if let p = Projection.fit(builtin.natural + builtin.eyesOnly, far.natural + far.eyesOnly) {
            let entries = samples.map { entry(for: $0.display, $0.natural + $0.eyesOnly, p) }
            if isUsable(entries) { return CalibrationData(projection: p, entries: entries, usesEyes: true) }
        }
        if let p = Projection.fit(builtin.natural, far.natural, use: headOnly) {
            let entries = samples.map { entry(for: $0.display, $0.natural, p) }
            if isUsable(entries) { return CalibrationData(projection: p, entries: entries, usesEyes: false) }
        }
        return nil
    }

    /// True when every pair of neighbouring displays is more than three times
    /// their average jitter apart.
    public static func isUsable(_ entries: [CalibrationEntry]) -> Bool {
        let sorted = entries.sorted { $0.value < $1.value }
        return zip(sorted, sorted.dropFirst()).allSatisfy { a, b in
            b.value - a.value > 3 * max((a.spread + b.spread) / 2, 0.005)
        }
    }

    /// Maps a saved calibration onto the current displays.
    ///
    /// The laptop camera is the reference point, so when an external display has
    /// moved to the other side of the laptop its value is mirrored around the
    /// laptop's. With exactly one external display then and now, a different
    /// monitor (say, at another desk) reuses the calibration too.
    public static func resolve(_ entries: [CalibrationEntry], for displays: [DisplayInfo]) -> [Target]? {
        guard displays.count >= 2 else { return nil }
        guard let calBuiltin = entries.first(where: \.isBuiltin),
              let curBuiltin = displays.first(where: \.isBuiltin) else {
            let matched = displays.compactMap { d in
                entries.first { $0.displayID == d.id }.map { Target(id: d.id, value: $0.value) }
            }
            return matched.count == displays.count ? matched : nil
        }
        let calExternals = entries.filter { !$0.isBuiltin }
        var targets: [Target] = []
        for display in displays {
            if display.isBuiltin {
                targets.append(Target(id: display.id, value: calBuiltin.value))
                continue
            }
            guard let entry = calExternals.first(where: { $0.displayID == display.id })
                ?? (calExternals.count == 1 && displays.count == 2 ? calExternals.first : nil)
            else { return nil }
            let wasLeft = entry.centerX < calBuiltin.centerX
            let isLeft = Double(display.bounds.midX) < Double(curBuiltin.bounds.midX)
            let value = wasLeft == isLeft ? entry.value : 2 * calBuiltin.value - entry.value
            targets.append(Target(id: display.id, value: value))
        }
        return targets
    }

    private static func entry(for display: DisplayInfo, _ samples: [Features], _ p: Projection) -> CalibrationEntry {
        let values = samples.map(p.apply)
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return CalibrationEntry(displayID: display.id, value: values.sorted()[values.count / 2],
                                spread: variance.squareRoot(), centerX: Double(display.bounds.midX),
                                isBuiltin: display.isBuiltin)
    }
}
