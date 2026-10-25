import Testing
@testable import LookshiftCore

private let laptop: DisplayID = 1
private let monitor: DisplayID = 2

/// Drives a decider with readings at 12 fps, the app's camera rate.
private struct Clock {
    var t = 0.0
    let decider: Decider

    init(targets: [Target] = [Target(id: laptop, value: 0), Target(id: monitor, value: 1)]) {
        decider = Decider()
        decider.targets = targets
    }

    mutating func run(_ value: Double?, for seconds: Double, blocked: Bool = false) -> [DisplayID] {
        var switches: [DisplayID] = []
        let end = t + seconds
        while t < end {
            if let id = decider.feed(value, at: t, blocked: blocked) { switches.append(id) }
            t += 1.0 / 12
        }
        return switches
    }
}

@Suite struct DeciderTests {
    @Test func settlesOnTheDisplayBeingLookedAt() {
        var clock = Clock()
        #expect(clock.run(0.05, for: 1) == [laptop])
    }

    @Test func shortGlanceDoesNotSwitch() {
        var clock = Clock()
        _ = clock.run(0.05, for: 1)
        #expect(clock.run(0.95, for: 0.2).isEmpty)
    }

    @Test func sustainedLookSwitchesExactlyOnce() {
        var clock = Clock()
        _ = clock.run(0.05, for: 1)
        #expect(clock.run(0.95, for: 1) == [monitor])
        #expect(clock.run(0.95, for: 2).isEmpty)
    }

    @Test func justPastTheMidpointStaysPut() {
        var clock = Clock()
        _ = clock.run(0, for: 1)
        #expect(clock.run(0.55, for: 2).isEmpty)
        #expect(clock.run(0.7, for: 2) == [monitor])
    }

    @Test func losingTheFaceChangesNothing() {
        var clock = Clock()
        _ = clock.run(0, for: 1)
        #expect(clock.run(nil, for: 3).isEmpty)
        #expect(clock.decider.current == laptop)
        #expect(clock.run(1, for: 1) == [monitor])
    }

    @Test func jitterBetweenDisplaysDoesNotFlap() {
        let decider = Decider()
        decider.targets = [Target(id: laptop, value: 0), Target(id: monitor, value: 1)]
        var switches = 0
        for i in 0..<60 where decider.feed(i % 2 == 0 ? 0 : 1, at: Double(i) / 12) != nil {
            switches += 1
        }
        #expect(switches <= 1)
    }

    @Test func typingHoldsASwitchWithoutLosingIt() {
        var clock = Clock()
        _ = clock.run(0, for: 1)
        #expect(clock.run(1, for: 3, blocked: true).isEmpty)
        #expect(clock.decider.feed(1, at: clock.t) == monitor)
    }

    @Test func needsAtLeastTwoDisplays() {
        var clock = Clock(targets: [Target(id: laptop, value: 0)])
        #expect(clock.run(0, for: 1).isEmpty)
    }
}
