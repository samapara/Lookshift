import CoreGraphics
import Testing
@testable import LookshiftCore

@Suite struct HeadTurnTests {
    private let left = [CGPoint(x: 0.25, y: 0.6), CGPoint(x: 0.35, y: 0.6)]
    private let right = [CGPoint(x: 0.65, y: 0.6), CGPoint(x: 0.75, y: 0.6)]

    @Test func facingForwardIsZero() throws {
        let turn = try #require(FaceGeometry.headTurn(nose: [CGPoint(x: 0.5, y: 0.4)], leftEye: left, rightEye: right))
        #expect(abs(turn) < 1e-9)
    }

    @Test func noseOffsetIsMeasuredInEyeDistances() throws {
        let turn = try #require(FaceGeometry.headTurn(nose: [CGPoint(x: 0.6, y: 0.4)], leftEye: left, rightEye: right))
        #expect(abs(turn - 0.25) < 1e-9)
    }

    @Test func missingLandmarksGiveNothing() {
        #expect(FaceGeometry.headTurn(nose: [], leftEye: left, rightEye: right) == nil)
        #expect(FaceGeometry.pupilOffset(eye: left, pupil: nil) == nil)
    }

    @Test func pupilOffsetSpansTheEye() {
        let eye = [CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0)]
        #expect(FaceGeometry.pupilOffset(eye: eye, pupil: CGPoint(x: 15, y: 0)) == 0)
        #expect(FaceGeometry.pupilOffset(eye: eye, pupil: CGPoint(x: 20, y: 0)) == 0.5)
    }
}

@Suite struct PupilFinderTests {
    /// A 60×20 eye: bright sclera with a dark pupil at `pupilX`.
    private func eye(pupilX: Double?, flat: Bool = false) -> LumaPlane {
        LumaPlane(width: 60, height: 20) { x, y in
            if flat { return 120 }
            guard let pupilX else { return 200 }
            let d = ((Double(x) - pupilX) * (Double(x) - pupilX) + Double((y - 10) * (y - 10))).squareRoot()
            return d < 3 ? 25 : d < 6 ? 90 : 210
        }
    }
    private let outline = [CGPoint(x: 0, y: 5), CGPoint(x: 59, y: 5), CGPoint(x: 30, y: 15)]

    @Test func findsACenteredPupil() throws {
        let offset = try #require(PupilFinder.offset(eye: outline, in: eye(pupilX: 29.5)))
        #expect(abs(offset) < 0.02)
    }

    @Test func followsThePupilSideways() throws {
        let right = try #require(PupilFinder.offset(eye: outline, in: eye(pupilX: 45)))
        let left = try #require(PupilFinder.offset(eye: outline, in: eye(pupilX: 14)))
        #expect(right > 0.2)
        #expect(left < -0.2)
    }

    @Test func skipsClosedOrFlatEyes() {
        #expect(PupilFinder.offset(eye: outline, in: eye(pupilX: nil, flat: true)) == nil)
    }

    @Test func rejectsTinyEyes() {
        let tiny = [CGPoint(x: 0, y: 5), CGPoint(x: 8, y: 5), CGPoint(x: 4, y: 9)]
        #expect(PupilFinder.offset(eye: tiny, in: eye(pupilX: 4)) == nil)
    }
}
