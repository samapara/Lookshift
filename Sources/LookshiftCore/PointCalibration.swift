import CoreGraphics
import Foundation

/// One camera reading, split by what it's used for.
public struct FaceReading: Equatable, Sendable {
    /// Head turn and two eye estimates, all left–right. Enough to tell screens apart.
    public var horizontal: Features
    /// Every signal, including up–down and where the face sits in the camera frame.
    /// Needed to find a point within one screen.
    public var all: Features

    public init(horizontal: Features, all: Features) {
        self.horizontal = horizontal
        self.all = all
    }
}

/// A reading taken while looking at a known spot, as a fraction of the screen (0…1, top-left origin).
public struct PointSample: Sendable {
    public let target: CGPoint
    public let features: Features

    public init(target: CGPoint, features: Features) {
        self.target = target
        self.features = features
    }
}

/// Maps readings to a point on one display, learned from the 9-dot calibration
/// with ridge regression (one linear model each for x and y).
public struct PointCalibration: Codable, Equatable, Sendable {
    public let displayID: DisplayID
    public let isBuiltin: Bool
    /// Display center and the built-in display's center at calibration time, to notice a moved monitor.
    public let centerX: Double
    public let builtinCenterX: Double?
    public let mean: [Double]
    public let scale: [Double]
    /// Bias first, then one weight per standardised feature.
    public let weightsX: [Double]
    public let weightsY: [Double]
    /// Typical miss, as a fraction of the screen, measured by predicting each
    /// dot from a model that never saw it.
    public let error: Double

    /// Below this, windows covering about a third of the screen can be told apart.
    public static let usableError = 0.3

    public var isUsable: Bool { error < Self.usableError }

    /// The predicted gaze point as a fraction of the display, clamped to it.
    public func predict(_ features: Features) -> CGPoint {
        let raw = Self.predict(features, mean: mean, scale: scale, wx: weightsX, wy: weightsY)
        return CGPoint(x: min(max(raw.x, 0), 1), y: min(max(raw.y, 0), 1))
    }

    /// The predicted gaze point in global coordinates on `display`.
    public func point(for features: Features, on display: DisplayInfo) -> CGPoint {
        let f = predict(features)
        return CGPoint(x: display.bounds.minX + f.x * display.bounds.width,
                       y: display.bounds.minY + f.y * display.bounds.height)
    }

    public static func fit(display: DisplayInfo, builtin: DisplayInfo?, samples: [PointSample],
                           ridge: Double = 1) -> PointCalibration? {
        let groups = Dictionary(grouping: samples) { "\($0.target.x),\($0.target.y)" }.values.filter { $0.count >= 3 }
        guard groups.count >= 6, let d = samples.first?.features.count else { return nil }

        let all = groups.flatMap { $0 }
        let mean = (0..<d).map { i in all.map { $0.features[i] }.reduce(0, +) / Double(all.count) }
        let scale = (0..<d).map { i -> Double in
            let variance = all.map { ($0.features[i] - mean[i]) * ($0.features[i] - mean[i]) }.reduce(0, +) / Double(all.count)
            return variance > 1e-18 ? variance.squareRoot() : 1
        }

        // Leave one dot out: how far off is the prediction for a dot the model never saw?
        var squaredMisses: [Double] = []
        for (k, held) in groups.enumerated() {
            let training = groups.enumerated().filter { $0.offset != k }.flatMap { $0.element }
            guard let (wx, wy) = solve(training, mean: mean, scale: scale, ridge: ridge) else { return nil }
            let predictions = held.map { predict($0.features, mean: mean, scale: scale, wx: wx, wy: wy) }
            let px = predictions.map(\.x).reduce(0, +) / CGFloat(predictions.count)
            let py = predictions.map(\.y).reduce(0, +) / CGFloat(predictions.count)
            let target = held[0].target
            squaredMisses.append(Double((px - target.x) * (px - target.x) + (py - target.y) * (py - target.y)))
        }
        guard let (wx, wy) = solve(all, mean: mean, scale: scale, ridge: ridge) else { return nil }
        let error = (squaredMisses.reduce(0, +) / Double(squaredMisses.count)).squareRoot()
        return PointCalibration(displayID: display.id, isBuiltin: display.isBuiltin, centerX: Double(display.bounds.midX),
                                builtinCenterX: builtin.map { Double($0.bounds.midX) }, mean: mean, scale: scale,
                                weightsX: wx, weightsY: wy, error: error)
    }

    /// The calibration that still fits `display` in the current arrangement, if any.
    /// A monitor moved to the other side of the laptop sees the user's face from a
    /// different angle, so its calibration no longer applies.
    public static func resolve(_ calibrations: [PointCalibration], for display: DisplayInfo,
                               among displays: [DisplayInfo]) -> PointCalibration? {
        if display.isBuiltin { return calibrations.first(where: \.isBuiltin) }
        guard let calibration = calibrations.first(where: { $0.displayID == display.id }) else { return nil }
        guard let builtin = displays.first(where: \.isBuiltin), let oldBuiltin = calibration.builtinCenterX else {
            return calibration
        }
        let wasLeft = calibration.centerX < oldBuiltin
        let isLeft = Double(display.bounds.midX) < Double(builtin.bounds.midX)
        return wasLeft == isLeft ? calibration : nil
    }

    private static func solve(_ samples: [PointSample], mean: [Double], scale: [Double],
                              ridge: Double) -> ([Double], [Double])? {
        let n = mean.count + 1
        var gram = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        var bx = Array(repeating: 0.0, count: n), by = Array(repeating: 0.0, count: n)
        for sample in samples {
            let phi = [1] + zip(sample.features, zip(mean, scale)).map { ($0 - $1.0) / $1.1 }
            for i in 0..<n {
                for j in 0..<n { gram[i][j] += phi[i] * phi[j] }
                bx[i] += phi[i] * Double(sample.target.x)
                by[i] += phi[i] * Double(sample.target.y)
            }
        }
        for i in 1..<n { gram[i][i] += ridge }   // the bias is not penalised
        guard let wx = LinearAlgebra.solve(gram, bx), let wy = LinearAlgebra.solve(gram, by) else { return nil }
        return (wx, wy)
    }

    private static func predict(_ f: Features, mean: [Double], scale: [Double], wx: [Double], wy: [Double]) -> CGPoint {
        var x = wx[0], y = wy[0]
        for i in f.indices {
            let z = (f[i] - mean[i]) / scale[i]
            x += wx[i + 1] * z
            y += wy[i + 1] * z
        }
        return CGPoint(x: x, y: y)
    }

    /// The 3×3 grid the user follows, centre first, then around the edge.
    public static let grid: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.9, y: 0.1),
        CGPoint(x: 0.9, y: 0.5), CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.5, y: 0.9), CGPoint(x: 0.1, y: 0.9),
        CGPoint(x: 0.1, y: 0.5),
    ]
}

enum LinearAlgebra {
    /// Solves `m · x = v` by Gaussian elimination with partial pivoting.
    static func solve(_ m: [[Double]], _ v: [Double]) -> [Double]? {
        let n = v.count
        var a = zip(m, v).map { $0 + [$1] }
        for col in 0..<n {
            guard let pivot = (col..<n).max(by: { abs(a[$0][col]) < abs(a[$1][col]) }),
                  abs(a[pivot][col]) > 1e-12 else { return nil }
            a.swapAt(col, pivot)
            for row in 0..<n where row != col {
                let factor = a[row][col] / a[col][col]
                for k in col...n { a[row][k] -= factor * a[col][k] }
            }
        }
        return (0..<n).map { a[$0][n] / a[$0][$0] }
    }
}
