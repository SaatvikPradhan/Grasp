import Foundation

/// One temperature from one cup.
public struct Reading: Codable, Equatable, Sendable {
    public var cup: Cup
    public var celsius: Double
    /// When the Mac received it, in seconds on the Mac's uptime clock.
    public var time: Double

    public init(cup: Cup, celsius: Double, time: Double) {
        self.cup = cup
        self.celsius = celsius
        self.time = time
    }
}
