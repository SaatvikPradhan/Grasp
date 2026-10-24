import CoreGraphics
import Foundation

/// One Euro filter (Casiez, Roussel and Vogel, CHI 2012): heavy smoothing when a value
/// is still, light smoothing when it moves fast, so a hand cursor neither jitters nor lags.
///
/// `minCutoff` (Hz) sets how smooth a still value is; lower is smoother.
/// `beta` sets how quickly smoothing drops as speed rises; higher means less lag.
/// Both depend on the units of the value, so tune them in the units you filter.
public struct OneEuroFilter: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var derivativeCutoff: Double

    private var value: Double?
    private var derivative: Double = 0
    private var lastTime: Double?

    public init(minCutoff: Double = 1.0, beta: Double = 0.0, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    /// Feeds a sample taken at `time` (seconds) and returns the smoothed value.
    public mutating func filter(_ x: Double, at time: Double) -> Double {
        guard let previous = value, let last = lastTime else {
            value = x
            lastTime = time
            return x
        }
        let dt = time - last
        guard dt > 0 else { return previous }
        lastTime = time

        let rawDerivative = (x - previous) / dt
        derivative += Self.alpha(cutoff: derivativeCutoff, dt: dt) * (rawDerivative - derivative)
        let cutoff = minCutoff + beta * abs(derivative)
        let smoothed = previous + Self.alpha(cutoff: cutoff, dt: dt) * (x - previous)
        value = smoothed
        return smoothed
    }

    public mutating func reset() {
        value = nil
        lastTime = nil
        derivative = 0
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}

/// A One Euro filter for each axis of a point.
public struct PointFilter: Sendable {
    private var x: OneEuroFilter
    private var y: OneEuroFilter

    public init(minCutoff: Double, beta: Double) {
        x = OneEuroFilter(minCutoff: minCutoff, beta: beta)
        y = OneEuroFilter(minCutoff: minCutoff, beta: beta)
    }

    public mutating func tune(minCutoff: Double, beta: Double) {
        x.minCutoff = minCutoff
        x.beta = beta
        y.minCutoff = minCutoff
        y.beta = beta
    }

    public mutating func filter(_ point: CGPoint, at time: Double) -> CGPoint {
        CGPoint(x: x.filter(point.x, at: time), y: y.filter(point.y, at: time))
    }
}
