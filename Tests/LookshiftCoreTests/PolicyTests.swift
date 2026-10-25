import Testing
@testable import LookshiftCore

@Suite struct CameraPolicyTests {
    private let ready = CameraConditions(displayCount: 2, calibrated: true, accessibilityGranted: true)

    @Test func tracksWhenEverythingIsReady() {
        #expect(CameraPolicy.state(for: ready) == .tracking)
        #expect(CameraState.tracking.wantsCamera)
    }

    @Test func calibrationAlwaysGetsTheCamera() {
        var c = ready
        c.calibrating = true
        c.paused = true
        #expect(CameraPolicy.state(for: c) == .calibrating)
        #expect(CameraState.calibrating.wantsCamera)
    }

    enum Blocker: CaseIterable, Sendable {
        case paused, away, notCalibrated, noAccessibility

        func apply(to c: inout CameraConditions) -> CameraState {
            switch self {
            case .paused: c.paused = true; return .paused
            case .away: c.away = true; return .away
            case .notCalibrated: c.calibrated = false; return .notCalibrated
            case .noAccessibility: c.accessibilityGranted = false; return .needsAccessibility
            }
        }
    }

    @Test(arguments: Blocker.allCases)
    func eachBlockerTurnsTheCameraOff(_ blocker: Blocker) {
        var c = ready
        let expected = blocker.apply(to: &c)
        #expect(CameraPolicy.state(for: c) == expected)
        #expect(!expected.wantsCamera)
    }

    @Test func singleDisplayIsIdle() {
        var c = ready
        c.displayCount = 1
        #expect(CameraPolicy.state(for: c) == .singleDisplay)
    }

    @Test func pauseWinsOverAway() {
        var c = ready
        c.paused = true
        c.away = true
        #expect(CameraPolicy.state(for: c) == .paused)
    }
}

@Suite struct PresencePolicyTests {
    @Test func idleTooLongIsAway() {
        let p = PresencePolicy(idleLimit: 120)
        #expect(!p.isAway(secondsSinceInput: 60, secondsWithoutFace: 0))
        #expect(p.isAway(secondsSinceInput: 121, secondsWithoutFace: 0))
    }

    @Test func zeroIdleLimitOnlyUsesTheFaceRule() {
        let p = PresencePolicy(idleLimit: 0)
        #expect(!p.isAway(secondsSinceInput: 10_000, secondsWithoutFace: 0))
        #expect(p.isAway(secondsSinceInput: 11, secondsWithoutFace: 21))
    }

    @Test func noFaceWhileTypingIsNotAway() {
        // Someone typing with their face out of frame is still at the Mac.
        #expect(!PresencePolicy().isAway(secondsSinceInput: 1, secondsWithoutFace: 60))
    }

    @Test func anyRecentInputResumes() {
        #expect(PresencePolicy().shouldResume(secondsSinceInput: 1))
        #expect(!PresencePolicy().shouldResume(secondsSinceInput: 5))
    }
}
