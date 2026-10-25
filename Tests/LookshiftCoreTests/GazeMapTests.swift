import CoreGraphics
import Testing
@testable import LookshiftCore

@Suite struct GazeMapTests {
    private let laptop = DisplayInfo(id: 1, bounds: CGRect(x: 0, y: 0, width: 1000, height: 600), isBuiltin: true, name: "B")
    private let monitor = DisplayInfo(id: 2, bounds: CGRect(x: 1000, y: 0, width: 2000, height: 1200), isBuiltin: false, name: "M")
    private var targets: [Target] { [Target(id: 1, value: -0.5), Target(id: 2, value: 0.5)] }

    @Test func calibratedValuesLandOnScreenCenters() {
        #expect(GazeMap.point(for: -0.5, targets: targets, displays: [laptop, monitor]) == CGPoint(x: 500, y: 300))
        #expect(GazeMap.point(for: 0.5, targets: targets, displays: [laptop, monitor]) == CGPoint(x: 2000, y: 600))
    }

    @Test func halfwayIsBetweenTheCenters() {
        #expect(GazeMap.point(for: 0, targets: targets, displays: [laptop, monitor]) == CGPoint(x: 1250, y: 450))
    }

    @Test func farOffValuesAreHeldNearTheOuterScreen() throws {
        let point = try #require(GazeMap.point(for: 5, targets: targets, displays: [laptop, monitor]))
        #expect(point.x == 500 + 1.3 * 1500)
    }

    @Test func needsTwoKnownDisplays() {
        #expect(GazeMap.point(for: 0, targets: targets, displays: [laptop]) == nil)
    }

    @Test func switchPointAndHysteresisRoundTrip() {
        #expect(GazeMap.hysteresis(forSwitchPoint: 0.5) == 0)
        #expect(abs(GazeMap.hysteresis(forSwitchPoint: 0.6) - 0.2) < 1e-9)
        #expect(abs(GazeMap.switchPoint(forHysteresis: 0.2) - 0.6) < 1e-9)
    }

    @Test func switchPointMatchesTheDecider() {
        // With "switch at 70%", 0.68 of the way across stays put and 0.72 switches.
        let decider = Decider()
        decider.targets = [Target(id: 1, value: 0), Target(id: 2, value: 1)]
        decider.hysteresis = GazeMap.hysteresis(forSwitchPoint: 0.7)
        decider.smoothing = 1
        decider.dwell = 0
        _ = decider.feed(0, at: 0)
        #expect(decider.feed(0.68, at: 1) == nil)
        #expect(decider.feed(0.72, at: 2) == 2)
    }
}
