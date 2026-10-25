import Foundation

/// One camera reading: head turn, eye offset from Vision's pupils, eye offset from the dark-pupil search.
public typealias Features = [Double]

/// A linear projection of `Features` onto one "gaze" axis, learned with Fisher's
/// linear discriminant. Each signal is weighted by how well it separates the
/// displays relative to its own noise, so an unreliable signal ends up mattering little.
public struct Projection: Codable, Equatable, Sendable {
    public var mean: [Double]
    public var scale: [Double]
    public var weights: [Double]

    public func apply(_ x: Features) -> Double {
        var sum = 0.0
        for i in x.indices { sum += (x[i] - mean[i]) / scale[i] * weights[i] }
        return sum
    }

    /// Fits an axis pointing from class `a` to class `b`, normalised so the class
    /// means project exactly 1 apart. `use` limits which features may get weight.
    public static func fit(_ a: [Features], _ b: [Features], use: [Bool]? = nil) -> Projection? {
        guard let d = a.first?.count, a.count >= 2, b.count >= 2 else { return nil }
        let all = a + b
        let use = use ?? Array(repeating: true, count: d)
        let mean = centroid(all)
        let scale = (0..<d).map { i -> Double in
            let variance = all.map { ($0[i] - mean[i]) * ($0[i] - mean[i]) }.reduce(0, +) / Double(all.count)
            return variance > 1e-18 ? variance.squareRoot() : 1
        }
        let standardise: ([Features]) -> [Features] = { points in
            points.map { x in (0..<d).map { use[$0] ? (x[$0] - mean[$0]) / scale[$0] : 0 } }
        }
        let za = standardise(a), zb = standardise(b)
        let ma = centroid(za), mb = centroid(zb)

        // Pooled within-class scatter, plus a small ridge so it is always invertible.
        var scatter = Array(repeating: Array(repeating: 0.0, count: d), count: d)
        for (points, m) in [(za, ma), (zb, mb)] {
            for p in points {
                for i in 0..<d {
                    for j in 0..<d { scatter[i][j] += (p[i] - m[i]) * (p[j] - m[j]) / Double(all.count) }
                }
            }
        }
        for i in 0..<d { scatter[i][i] += 0.01 }

        guard var w = LinearAlgebra.solve(scatter, zip(mb, ma).map { $0 - $1 }) else { return nil }
        for i in 0..<d where !use[i] { w[i] = 0 }
        var projection = Projection(mean: mean, scale: scale, weights: w)
        let gap = projection.apply(centroid(b)) - projection.apply(centroid(a))
        guard abs(gap) > 1e-9 else { return nil }
        projection.weights = w.map { $0 / gap }
        return projection
    }

    static func centroid(_ points: [Features]) -> Features {
        (0..<points[0].count).map { i in points.map { $0[i] }.reduce(0, +) / Double(points.count) }
    }
}
