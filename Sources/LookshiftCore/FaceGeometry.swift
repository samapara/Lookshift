import CoreGraphics

/// Head and eye measurements from face landmark points.
public enum FaceGeometry {
    /// How far the head is turned: the nose's offset from the midpoint between
    /// the eyes, in eye-distances. The nose sticks out, so it swings sideways
    /// more than the eyes when the head turns; dividing by the eye distance
    /// cancels out how close the user sits.
    public static func headTurn(nose: [CGPoint], leftEye: [CGPoint], rightEye: [CGPoint]) -> Double? {
        guard let n = centroid(nose), let l = centroid(leftEye), let r = centroid(rightEye) else { return nil }
        let eyeDistance = abs(r.x - l.x)
        guard eyeDistance > 0.01 else { return nil }
        return Double((n.x - (l.x + r.x) / 2) / eyeDistance)
    }

    /// How far the head is tilted up or down: the nose's vertical offset from the
    /// eyes, in eye-distances. Same idea as `headTurn`, on the other axis.
    public static func headTilt(nose: [CGPoint], leftEye: [CGPoint], rightEye: [CGPoint]) -> Double? {
        guard let n = centroid(nose), let l = centroid(leftEye), let r = centroid(rightEye) else { return nil }
        let eyeDistance = abs(r.x - l.x)
        guard eyeDistance > 0.01 else { return nil }
        return Double((n.y - (l.y + r.y) / 2) / eyeDistance)
    }

    /// The pupil's vertical offset from the eye's center, in eye-heights (−0.5 to +0.5).
    public static func pupilOffsetY(eye: [CGPoint], pupil: CGPoint?) -> Double? {
        guard let pupil, let minY = eye.map(\.y).min(), let maxY = eye.map(\.y).max(),
              maxY - minY > 0.001 else { return nil }
        return Double((pupil.y - minY) / (maxY - minY)) - 0.5
    }

    /// The pupil's offset from the eye's center, in eye-widths (−0.5 to +0.5).
    public static func pupilOffset(eye: [CGPoint], pupil: CGPoint?) -> Double? {
        guard let pupil, let minX = eye.map(\.x).min(), let maxX = eye.map(\.x).max(),
              maxX - minX > 0.001 else { return nil }
        return Double((pupil.x - minX) / (maxX - minX)) - 0.5
    }

    /// Averages a left and right eye measurement; nil if either is missing.
    public static func average(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return (a + b) / 2
    }

    static func centroid(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}

/// A read-only grayscale image, addressed in pixels from the top-left.
public struct LumaPlane {
    public let width: Int
    public let height: Int
    private let read: (Int, Int) -> UInt8

    public init(width: Int, height: Int, read: @escaping (_ x: Int, _ y: Int) -> UInt8) {
        self.width = width
        self.height = height
        self.read = read
    }

    public subscript(x: Int, y: Int) -> UInt8 { read(x, y) }
}

/// Finds the pupil as the darkest pixels inside the eye. Independent of
/// Vision's own pupil estimate, so calibration can weigh the two against each other.
public enum PupilFinder {
    /// Share of the darkest pixels treated as pupil.
    static let darkShare = 0.15
    /// Minimum brightness gap between the median and the threshold; below it
    /// the eye is closed or the image too flat to trust.
    static let minContrast = 12

    /// The pupil's offset from the eye's center in eye-widths, or nil when no
    /// distinct pupil is visible. `eye` is the eye outline in pixel coordinates.
    public static func offset(eye: [CGPoint], in plane: LumaPlane) -> Double? {
        guard let minX = eye.map(\.x).min(), let maxX = eye.map(\.x).max(),
              let minY = eye.map(\.y).min(), let maxY = eye.map(\.y).max(),
              maxX - minX >= 12, maxY - minY >= 3 else { return nil }

        // Middle band of the eye: skips lashes and lids at the top and bottom.
        let midY = (minY + maxY) / 2, halfBand = max((maxY - minY) * 0.35, 2)
        let x0 = max(0, Int(minX)), x1 = min(plane.width - 1, Int(maxX))
        let y0 = max(0, Int(midY - halfBand)), y1 = min(plane.height - 1, Int(midY + halfBand))
        guard x1 > x0, y1 >= y0 else { return nil }

        var pixels: [(x: Int, luma: UInt8)] = []
        pixels.reserveCapacity((x1 - x0 + 1) * (y1 - y0 + 1))
        for y in y0...y1 {
            for x in x0...x1 { pixels.append((x, plane[x, y])) }
        }
        guard pixels.count >= 30 else { return nil }

        let sorted = pixels.map(\.luma).sorted()
        let threshold = sorted[Int(Double(pixels.count) * darkShare)]
        guard Int(sorted[pixels.count / 2]) - Int(threshold) > minContrast else { return nil }

        var sum = 0.0, weight = 0.0
        for pixel in pixels where pixel.luma <= threshold {
            let w = Double(Int(threshold) - Int(pixel.luma) + 1)   // darker pixels count more
            sum += Double(pixel.x) * w
            weight += w
        }
        guard weight > 0 else { return nil }
        return (sum / weight - Double(minX)) / Double(maxX - minX) - 0.5
    }

    /// The pupil's vertical offset from the eye's center in eye-heights, from the
    /// darkest pixels across the whole eye box. Eyelids hide much of the up–down
    /// movement, so this is weak on its own; calibration decides how much it counts.
    public static func verticalOffset(eye: [CGPoint], in plane: LumaPlane) -> Double? {
        guard let minX = eye.map(\.x).min(), let maxX = eye.map(\.x).max(),
              let minY = eye.map(\.y).min(), let maxY = eye.map(\.y).max(),
              maxX - minX >= 12, maxY - minY >= 3 else { return nil }
        let x0 = max(0, Int(minX)), x1 = min(plane.width - 1, Int(maxX))
        let y0 = max(0, Int(minY)), y1 = min(plane.height - 1, Int(maxY))
        guard x1 > x0, y1 > y0 else { return nil }

        var pixels: [(y: Int, luma: UInt8)] = []
        for y in y0...y1 {
            for x in x0...x1 { pixels.append((y, plane[x, y])) }
        }
        guard pixels.count >= 30 else { return nil }
        let sorted = pixels.map(\.luma).sorted()
        let threshold = sorted[Int(Double(pixels.count) * darkShare)]
        guard Int(sorted[pixels.count / 2]) - Int(threshold) > minContrast else { return nil }

        var sum = 0.0, weight = 0.0
        for pixel in pixels where pixel.luma <= threshold {
            let w = Double(Int(threshold) - Int(pixel.luma) + 1)
            sum += Double(pixel.y) * w
            weight += w
        }
        guard weight > 0 else { return nil }
        return (sum / weight - Double(minY)) / Double(maxY - minY) - 0.5
    }
}
