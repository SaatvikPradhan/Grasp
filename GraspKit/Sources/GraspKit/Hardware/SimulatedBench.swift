import Foundation

/// Stand-in for the three probe cups before the hardware works. Each cup drifts toward the room,
/// and you can act on it like a real bench: pour hot water in, put a lid on, drop ice in. The
/// rates match the sample paper: k = 0.031 per minute open, 0.019 with a lid.
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

    /// Something done to a cup.
    public enum Action: Equatable, Sendable {
        case pour(Cup, celsius: Double)
        case lid(Cup, on: Bool)
        case ice(Cup)
    }

    /// An open cup of hot water: k = 0.031 per minute.
    public static let openTau = 60 / 0.031
    /// With a lid: k = 0.019 per minute.
    public static let lidTau = 60 / 0.019
    /// The water poured, as on the protocol page: the straw-sealed probes soften above 60 °C.
    public static let pourCelsius = 50.0
    /// Two ice cubes take about this much off.
    public static let iceDrop = 18.0

    /// Three empty cups with probes in, at room temperature: the bench before an experiment.
    public static func emptyCups(ambient: Double = 21) -> SimulatedBench {
        SimulatedBench(ambient: ambient, cups: Dictionary(uniqueKeysWithValues: Cup.allCases.map {
            ($0, CupSetup(start: ambient + 0.5, tau: openTau))
        }))
    }

    /// Where a cup's curve last restarted: its temperature then, when, and how fast it cools.
    struct State: Sendable {
        var celsius: Double
        var since: Double
        var tau: Double
        var lidded = false
    }

    public var ambient: Double
    /// Each reading is off by up to this much, like a real probe.
    public var noise: Double
    private var states: [Cup: State]

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
        self.noise = noise
        states = cups.mapValues { State(celsius: $0.start, since: 0, tau: $0.tau) }
    }

    /// The temperature of `cup` after `seconds`, noise included.
    public func celsius(_ cup: Cup, after seconds: Double) -> Double {
        let exact = exactCelsius(cup, after: seconds)
        return noise > 0 ? exact + Double.random(in: -noise...noise) : exact
    }

    /// Does something to a cup at `seconds`; the curve restarts from there.
    public mutating func apply(_ action: Action, at seconds: Double) {
        switch action {
        case .pour(let cup, let celsius):
            let lidded = states[cup]?.lidded ?? false
            states[cup] = State(celsius: celsius, since: seconds, tau: lidded ? Self.lidTau : Self.openTau, lidded: lidded)
        case .lid(let cup, let on):
            states[cup] = State(celsius: exactCelsius(cup, after: seconds), since: seconds, tau: on ? Self.lidTau : Self.openTau, lidded: on)
        case .ice(let cup):
            let state = states[cup]
            states[cup] = State(celsius: max(0, exactCelsius(cup, after: seconds) - Self.iceDrop), since: seconds,
                                tau: state?.tau ?? Self.openTau, lidded: state?.lidded ?? false)
        }
    }

    private func exactCelsius(_ cup: Cup, after seconds: Double) -> Double {
        guard let state = states[cup] else { return ambient }
        return NewtonCooling.temperature(start: state.celsius, ambient: ambient, tau: state.tau, after: seconds - state.since)
    }
}
