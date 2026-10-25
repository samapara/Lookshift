import CoreGraphics
import Testing
@testable import LookshiftCore

/// Deterministic noise so the tests never flake.
private struct Noise {
    var seed: UInt64 = 42

    mutating func next(_ amplitude: Double) -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return (Double(seed >> 11) / Double(1 << 53) - 0.5) * 2 * amplitude
    }

    mutating func samples(_ n: Int, head: Double, eye: Double, eyeNoise: Double = 0.02) -> [Features] {
        (0..<n).map { _ in [head + next(0.02), eye + next(eyeNoise), eye + next(eyeNoise)] }
    }
}

private let laptop = DisplayInfo(id: 1, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982), isBuiltin: true, name: "Built-in")
private let rightMonitor = DisplayInfo(id: 7, bounds: CGRect(x: 1512, y: 0, width: 2560, height: 1440), isBuiltin: false, name: "R")
private let leftMonitor = DisplayInfo(id: 7, bounds: CGRect(x: -2560, y: 0, width: 2560, height: 1440), isBuiltin: false, name: "L")
private let otherMonitor = DisplayInfo(id: 9, bounds: CGRect(x: -1920, y: 0, width: 1920, height: 1080), isBuiltin: false, name: "O")

private let saved = [
    CalibrationEntry(displayID: 1, value: 0.1, spread: 0.02, centerX: 756, isBuiltin: true),
    CalibrationEntry(displayID: 7, value: 0.6, spread: 0.03, centerX: 2792, isBuiltin: false),
]

@Suite struct ResolveTests {
    @Test func sameArrangementUsesSavedValues() {
        #expect(Calibration.resolve(saved, for: [laptop, rightMonitor]) == [Target(id: 1, value: 0.1), Target(id: 7, value: 0.6)])
    }

    @Test func monitorMovedToOtherSideIsMirrored() throws {
        let targets = try #require(Calibration.resolve(saved, for: [laptop, leftMonitor]))
        #expect(targets[0].value == 0.1)
        #expect(abs(targets[1].value - -0.4) < 1e-9)
    }

    @Test func differentSingleMonitorReusesCalibration() throws {
        let targets = try #require(Calibration.resolve(saved, for: [laptop, otherMonitor]))
        #expect(abs(targets[1].value - -0.4) < 1e-9)
    }

    @Test func oneDisplayHasNothingToResolve() {
        #expect(Calibration.resolve(saved, for: [laptop]) == nil)
    }

    @Test func usabilityNeedsThreeTimesTheJitter() {
        #expect(Calibration.isUsable(saved))
        #expect(!Calibration.isUsable([
            CalibrationEntry(displayID: 1, value: 0.1, spread: 0.05, centerX: 0, isBuiltin: true),
            CalibrationEntry(displayID: 7, value: 0.15, spread: 0.05, centerX: 1, isBuiltin: false),
        ]))
    }
}

@Suite struct FitTests {
    @Test func cleanEyesAreUsedAndCatchEyeOnlyGlances() throws {
        var noise = Noise()
        // Natural look: head turns a lot, eyes a bit. Eyes only: head stays, eyes move a lot.
        let data = try #require(Calibration.build([
            CalibrationSamples(display: laptop, natural: noise.samples(24, head: 0, eye: 0),
                               eyesOnly: noise.samples(24, head: 0.4, eye: -0.25)),
            CalibrationSamples(display: rightMonitor, natural: noise.samples(24, head: 0.4, eye: 0.05),
                               eyesOnly: noise.samples(24, head: 0, eye: 0.25)),
        ]))
        #expect(data.usesEyes)

        let decider = Decider()
        decider.targets = try #require(Calibration.resolve(data.entries, for: [laptop, rightMonitor]))
        var t = 0.0
        func look(head: Double, eye: Double) -> [DisplayID] {
            var switches: [DisplayID] = []
            for _ in 0..<12 {
                let x = noise.samples(1, head: head, eye: eye)[0]
                if let id = decider.feed(data.projection.apply(x), at: t) { switches.append(id) }
                t += 1.0 / 12
            }
            return switches
        }
        #expect(look(head: 0, eye: 0) == [1])
        #expect(look(head: 0, eye: 0.25) == [7], "eyes-only glance at the monitor")
        #expect(look(head: 0.4, eye: -0.25) == [1], "head on the monitor, eyes back on the laptop")
        #expect(look(head: 0.4, eye: 0.05) == [7], "natural head turn")
    }

    @Test func noisyEyesFallBackToHeadOnly() throws {
        var noise = Noise()
        let data = try #require(Calibration.build([
            CalibrationSamples(display: laptop, natural: noise.samples(24, head: 0, eye: 0, eyeNoise: 0.4),
                               eyesOnly: noise.samples(24, head: 0.4, eye: 0, eyeNoise: 0.4)),
            CalibrationSamples(display: rightMonitor, natural: noise.samples(24, head: 0.4, eye: 0, eyeNoise: 0.4),
                               eyesOnly: noise.samples(24, head: 0, eye: 0, eyeNoise: 0.4)),
        ]))
        #expect(!data.usesEyes)
        #expect(data.projection.weights[1] == 0 && data.projection.weights[2] == 0)
    }

    @Test func indistinguishableDisplaysFail() {
        var noise = Noise()
        #expect(Calibration.build([
            CalibrationSamples(display: laptop, natural: noise.samples(24, head: 0, eye: 0)),
            CalibrationSamples(display: rightMonitor, natural: noise.samples(24, head: 0, eye: 0)),
        ]) == nil)
    }

    @Test func projectionPlacesClassMeansOneApart() throws {
        var noise = Noise()
        let a = noise.samples(30, head: 0, eye: 0), b = noise.samples(30, head: 0.5, eye: 0.3)
        let p = try #require(Projection.fit(a, b))
        let gap = p.apply(Projection.centroid(b)) - p.apply(Projection.centroid(a))
        #expect(abs(gap - 1) < 1e-9)
    }

    @Test func calibrationRoundTripsThroughJSON() throws {
        var noise = Noise()
        let data = try #require(Calibration.build([
            CalibrationSamples(display: laptop, natural: noise.samples(24, head: 0, eye: 0)),
            CalibrationSamples(display: rightMonitor, natural: noise.samples(24, head: 0.4, eye: 0.1)),
        ]))
        let decoded = try JSONDecoder().decode(CalibrationData.self, from: JSONEncoder().encode(data))
        #expect(decoded == data)
    }
}

import Foundation
