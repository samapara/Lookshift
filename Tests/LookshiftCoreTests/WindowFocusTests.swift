import CoreGraphics
import Foundation
import Testing
@testable import LookshiftCore

private let laptop = DisplayInfo(id: 1, bounds: CGRect(x: 0, y: 0, width: 1000, height: 600), isBuiltin: true, name: "B")

/// Readings that depend linearly on the dot, plus noise and an irrelevant signal.
private func samples(noise: Double, perDot: Int = 15, seed: UInt64 = 7) -> [PointSample] {
    var state = seed
    func rand() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53) - 0.5
    }
    return PointCalibration.grid.flatMap { dot in
        (0..<perDot).map { _ in
            let x = Double(dot.x), y = Double(dot.y)
            return PointSample(target: dot, features: [
                0.4 * x + noise * rand(),          // head turn
                0.3 * x + noise * rand(),          // eyes, horizontal
                0.2 * y + noise * rand(),          // head tilt
                0.15 * y + noise * rand(),         // eyes, vertical
                rand(),                            // unrelated signal
            ])
        }
    }
}

@Suite struct PointCalibrationTests {
    @Test func cleanReadingsGiveAnAccurateMap() throws {
        let calibration = try #require(PointCalibration.fit(display: laptop, builtin: laptop, samples: samples(noise: 0.01)))
        #expect(calibration.isUsable)
        #expect(calibration.error < 0.05)
        let corner = calibration.predict([0.4 * 0.9, 0.3 * 0.9, 0.2 * 0.1, 0.15 * 0.1, 0])
        #expect(abs(corner.x - 0.9) < 0.05 && abs(corner.y - 0.1) < 0.05)
    }

    @Test func noisyReadingsAreRejected() throws {
        let calibration = try #require(PointCalibration.fit(display: laptop, builtin: laptop, samples: samples(noise: 2)))
        #expect(!calibration.isUsable)
    }

    @Test func predictionsStayOnScreen() throws {
        let calibration = try #require(PointCalibration.fit(display: laptop, builtin: laptop, samples: samples(noise: 0.01)))
        let far = calibration.point(for: [5, 5, 5, 5, 0], on: laptop)
        #expect(laptop.bounds.contains(far) || far == CGPoint(x: 1000, y: 600))
    }

    @Test func needsMostOfTheDots() {
        let few = samples(noise: 0.01).filter { $0.target.x == 0.5 }
        #expect(PointCalibration.fit(display: laptop, builtin: laptop, samples: few) == nil)
    }

    @Test func movedMonitorNeedsRecalibrating() throws {
        let right = DisplayInfo(id: 2, bounds: CGRect(x: 1000, y: 0, width: 1920, height: 1080), isBuiltin: false, name: "M")
        let left = DisplayInfo(id: 2, bounds: CGRect(x: -1920, y: 0, width: 1920, height: 1080), isBuiltin: false, name: "M")
        let calibration = try #require(PointCalibration.fit(display: right, builtin: laptop, samples: samples(noise: 0.01)))
        #expect(PointCalibration.resolve([calibration], for: right, among: [laptop, right]) != nil)
        #expect(PointCalibration.resolve([calibration], for: left, among: [laptop, left]) == nil)
    }
}

@Suite struct RegionDeciderTests {
    private let left = Region(id: "left", frame: CGRect(x: 0, y: 0, width: 500, height: 600))
    private let right = Region(id: "right", frame: CGRect(x: 500, y: 0, width: 500, height: 600))
    private func hit(_ p: CGPoint) -> Region? { left.frame.contains(p) ? left : right.frame.contains(p) ? right : nil }

    private func run(_ decider: RegionDecider, _ point: CGPoint?, from t: inout Double, for seconds: Double,
                     blocked: Bool = false) -> [String] {
        var focused: [String] = []
        let end = t + seconds
        while t < end {
            if let region = decider.feed(point, at: t, blocked: blocked, hitTest: hit) { focused.append(region.id) }
            t += 1.0 / 12
        }
        return focused
    }

    @Test func settlesOnTheRegionLookedAt() {
        let decider = RegionDecider()
        var t = 0.0
        #expect(run(decider, CGPoint(x: 200, y: 300), from: &t, for: 1) == ["left"])
    }

    @Test func glancesAreIgnored() {
        let decider = RegionDecider()
        var t = 0.0
        _ = run(decider, CGPoint(x: 200, y: 300), from: &t, for: 1)
        #expect(run(decider, CGPoint(x: 800, y: 300), from: &t, for: 0.25).isEmpty)
    }

    @Test func wobbleNearTheEdgeKeepsFocus() {
        let decider = RegionDecider()
        decider.smoothing = 1
        var t = 0.0
        _ = run(decider, CGPoint(x: 200, y: 300), from: &t, for: 1)
        #expect(run(decider, CGPoint(x: 530, y: 300), from: &t, for: 2).isEmpty, "30 pt past the edge is inside the margin")
        #expect(run(decider, CGPoint(x: 800, y: 300), from: &t, for: 1) == ["right"])
    }

    @Test func blockedSwitchWaitsWithoutBeingLost() {
        let decider = RegionDecider()
        var t = 0.0
        _ = run(decider, CGPoint(x: 200, y: 300), from: &t, for: 1)
        #expect(run(decider, CGPoint(x: 800, y: 300), from: &t, for: 2, blocked: true).isEmpty)
        #expect(run(decider, CGPoint(x: 800, y: 300), from: &t, for: 0.2) == ["right"])
    }

    @Test func hitTestRunsOnlyAfterLeavingTheCurrentRegion() {
        let decider = RegionDecider()
        var calls = 0
        for i in 0..<24 {
            _ = decider.feed(CGPoint(x: 200, y: 300), at: Double(i) / 12) { p in
                calls += 1
                return hit(p)
            }
        }
        #expect(calls <= 6, "only until the region is adopted, then never")
    }
}

@Suite struct SingleScreenPolicyTests {
    @Test func windowFocusRunsOnOneScreen() {
        let c = CameraConditions(displayCount: 1, windowFocusEnabled: true, windowFocusCalibrated: true,
                                 accessibilityGranted: true)
        #expect(CameraPolicy.state(for: c) == .tracking)
    }

    @Test func windowFocusWithoutCalibrationAsksForIt() {
        let c = CameraConditions(displayCount: 1, windowFocusEnabled: true, accessibilityGranted: true)
        #expect(CameraPolicy.state(for: c) == .notCalibrated)
    }

    @Test func eitherFeatureIsEnough() {
        let screensOnly = CameraConditions(displayCount: 2, calibrated: true, windowFocusEnabled: true,
                                           accessibilityGranted: true)
        #expect(CameraPolicy.state(for: screensOnly) == .tracking)
    }
}
