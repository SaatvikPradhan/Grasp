import Foundation

/// Stand-in for the three probe cups before the hardware works, shaped like the research
/// demo: A warm, B at room temperature, C cold, each drifting toward the room.
public struct SimulatedBench: Sendable {
    public struct CupSetup: Sendable {
        public var start: Double
        /// Seconds for the gap to the room to shrink by about two thirds.
        public var tau: Double

        public init(start: Double, tau: Double) {
            self.start = start
            self.tau = tau
        }
    }

    public var ambient: Double
    public var cups: [Cup: CupSetup]
    /// Each reading is off by up to this much, like a real probe.
    public var noise: Double

    public init(
        ambient: Double = 21,
        cups: [Cup: CupSetup] = [
            .a: CupSetup(start: 40, tau: 900),
            .b: CupSetup(start: 21.5, tau: 1_200),
            .c: CupSetup(start: 6, tau: 1_200),
        ],
        noise: Double = 0.05
    ) {
        self.ambient = ambient
        self.cups = cups
        self.noise = noise
    }

    /// The temperature of `cup` after `seconds`, noise included.
    public func celsius(_ cup: Cup, after seconds: Double) -> Double {
        let setup = cups[cup] ?? CupSetup(start: ambient, tau: 1)
        let exact = NewtonCooling.temperature(start: setup.start, ambient: ambient, tau: setup.tau, after: seconds)
        return noise > 0 ? exact + Double.random(in: -noise...noise) : exact
    }
}
