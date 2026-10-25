import Foundation

/// Words or a number copied from a page, with where they are on it.
public struct Cited: Equatable, Sendable {
    public var quote: String
    public var location: SourceLocator.Location?

    public init(quote: String, location: SourceLocator.Location?) {
        self.quote = quote
        self.location = location
    }
}

/// The model a paper describes, as a simulation Swift can run: its equation, its constants and
/// each condition's rate, every number copied from the page and found on it. Swift re-derives
/// the results the paper reports from its own equation, so a result that doesn't follow shows up.
public struct PaperModel: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// T(t) = room + (start − room)·e^(−kt)
        case newtonCooling = "newton_cooling"
        /// y(t) = start·e^(−kt)
        case exponential
    }

    /// A number from the page.
    public struct Number: Equatable, Sendable {
        public var value: Double
        public var cited: Cited
    }

    /// One of the paper's conditions (no lid, lid, ceramic…) and its rate.
    public struct Condition: Equatable, Sendable, Identifiable {
        public var name: String
        /// Per `timeUnit`.
        public var k: Number
        /// The paper's ± on k, if it gives one.
        public var spread: Double?
        public var reported: [Reported]

        public var id: String { name }
    }

    /// A result the paper reports for a condition, which its equation should reproduce.
    public struct Reported: Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            /// How long until the value reaches `at`.
            case timeTo = "time_to"
            /// The value after `at` time units.
            case valueAt = "value_at"
        }

        public var kind: Kind
        public var at: Double
        public var value: Number
    }

    /// A reported result, worked out again from the paper's own equation.
    public struct Check: Equatable, Sendable {
        public var condition: String
        public var reported: Reported
        public var expected: Double
        public var matches: Bool
    }

    public var kind: Kind
    public var equation: Cited
    /// "min", "s" or "h".
    public var timeUnit: String
    public var start: Number
    /// The room temperature, for cooling.
    public var room: Number?
    public var conditions: [Condition]

    // MARK: Running it

    public func value(after time: Double, k: Double) -> Double {
        switch kind {
        case .newtonCooling:
            let room = room?.value ?? 0
            return room + (start.value - room) * exp(-k * max(time, 0))
        case .exponential:
            return start.value * exp(-k * max(time, 0))
        }
    }

    /// When the value reaches `target`, or nil if it never does.
    public func time(to target: Double, k: Double) -> Double? {
        guard k > 0 else { return nil }
        let floor = kind == .newtonCooling ? (room?.value ?? 0) : 0
        let gap = start.value - floor, left = target - floor
        guard gap != 0, left / gap > 0, left / gap < 1 else { return nil }
        return log(gap / left) / k
    }

    /// Every reported result, worked out again. It matches when the printed result falls within
    /// what rounding k (half a unit in its last place) and rounding the result can explain.
    public var checks: [Check] {
        conditions.flatMap { condition in
            condition.reported.compactMap { reported -> Check? in
                func result(_ k: Double) -> Double? {
                    switch reported.kind {
                    case .timeTo: time(to: reported.at, k: k)
                    case .valueAt: value(after: reported.at, k: k)
                    }
                }
                let k = condition.k.value, slack = Self.halfUnit(k)
                guard let expected = result(k) else { return nil }
                let bounds = [result(k - slack), result(k + slack)].compactMap { $0 } + [expected]
                let margin = Self.halfUnit(reported.value.value) + 0.05
                let printed = reported.value.value
                let matches = printed >= (bounds.min() ?? expected) - margin && printed <= (bounds.max() ?? expected) + margin
                return Check(condition: condition.name, reported: reported, expected: expected, matches: matches)
            }
        }
    }

    public var mismatches: [Check] { checks.filter { !$0.matches } }

    /// Half a unit in the last printed place: 0.0005 for 0.031, 0.05 for 18.4.
    static func halfUnit(_ value: Double) -> Double {
        let text = String(value)
        guard let dot = text.firstIndex(of: "."), !text.hasSuffix(".0") else { return 0.5 }
        let decimals = text.distance(from: dot, to: text.endIndex) - 1
        return 0.5 * pow(10, -Double(decimals))
    }
}

/// A rate fitted from readings: k with its standard error.
public struct FittedRate: Equatable, Sendable {
    /// Per minute.
    public var k: Double
    public var standardError: Double
    public var points: Int
    /// Minutes of data it came from.
    public var minutes: Double

    /// Fits Newton's law of cooling to a cup's readings (`time` in seconds) in a room at `room`:
    /// ln(T − room) against time is a straight line with slope −k. Readings from after the last
    /// jump (a pour, ice) only; nil until there's enough of a slope to measure.
    public static func cooling(_ readings: [Reading], room: Double) -> FittedRate? {
        let points = segment(readings).filter { $0.celsius - room > 1 }
        guard points.count >= 20, let first = points.first, let last = points.last,
              last.time - first.time >= 20, first.celsius - last.celsius >= 0.3 else { return nil }
        let xs = points.map { ($0.time - first.time) / 60 }
        let ys = points.map { log($0.celsius - room) }
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard sxx > 0 else { return nil }
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) } / sxx
        let intercept = meanY - slope * meanX
        let residuals = zip(xs, ys).reduce(0) { total, point in
            let error = point.1 - (intercept + slope * point.0)
            return total + error * error
        }
        let standardError = n > 2 ? sqrt(residuals / (n - 2) / sxx) : 0
        return FittedRate(k: -slope, standardError: standardError, points: Int(n), minutes: (last.time - first.time) / 60)
    }

    /// The readings since the last jump (four seconds that changed more than 2 °C: a pour, ice),
    /// oldest first: one stretch of plain cooling.
    public static func segment(_ readings: [Reading]) -> [Reading] {
        let sorted = readings.sorted { $0.time < $1.time }
        var start = 0
        for index in sorted.indices.dropFirst() {
            var back = index - 1
            while back > 0, sorted[index].time - sorted[back].time < 4 { back -= 1 }
            if abs(sorted[index].celsius - sorted[back].celsius) > 2 { start = index }
        }
        return Array(sorted[start...].dropFirst(start == 0 ? 0 : 3))
    }

    /// Within two combined standard errors of the paper's value (using the paper's ± as its error).
    public func isConsistent(with k: Double, spread: Double?) -> Bool {
        let combined = sqrt(standardError * standardError + (spread ?? 0) * (spread ?? 0))
        return abs(self.k - k) <= max(2 * combined, 0.0005)
    }
}
