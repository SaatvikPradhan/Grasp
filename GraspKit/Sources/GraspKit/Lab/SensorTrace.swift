import Foundation

/// What the probes did during a session, worked out in Swift: each cup's range, and the moments
/// a temperature jumped (hot water poured, ice dropped in) or its cooling changed pace (a lid on).
public struct SensorTrace: Equatable, Sendable {
    public struct CupSummary: Equatable, Sendable {
        public var cup: Cup
        public var start: Double
        public var end: Double
        public var low: Double
        public var high: Double
    }

    public struct Event: Equatable, Sendable, Identifiable {
        public enum Kind: String, Sendable {
            case rose, dropped
            /// Cooling changed pace: `from` and `to` are rates in °C a second.
            case slowed
            case spedUp = "sped up"
        }

        public var cup: Cup
        public var kind: Kind
        public var seconds: Double
        /// °C before and after a jump; °C a second before and after a change of pace.
        public var from: Double
        public var to: Double

        public var id: String { "\(cup.rawValue) \(kind.rawValue) \(Int(seconds))" }

        /// "1:28 C dropped from 64.2 to 41.0 °C"
        public var description: String {
            switch kind {
            case .rose, .dropped:
                "\(clockTime(seconds)) \(cup.rawValue) \(kind.rawValue) from \(Self.one(from)) to \(Self.one(to)) °C"
            case .slowed, .spedUp:
                "\(clockTime(seconds)) \(cup.rawValue) cooling \(kind.rawValue), from \(Self.two(-from)) to \(Self.two(-to)) °C lost a second"
            }
        }

        static func one(_ value: Double) -> String { String(format: "%.1f", value) }
        static func two(_ value: Double) -> String { String(format: "%.2f", value) }
    }

    public var cups: [CupSummary]
    public var events: [Event]
    /// One reading a second per cup, smoothed: what the events and summaries come from.
    private var series: [Cup: [Double]]

    /// A jump is at least this fast, °C a second; plain cooling is far slower.
    static let jumpRate = 0.5
    /// A change of pace at least halves or doubles the cooling rate.
    static let paceRatio = 2.0

    public init(readings: [Reading]) {
        var series: [Cup: [Double]] = [:]
        for cup in Cup.allCases {
            let points = readings.filter { $0.cup == cup }.sorted { $0.time < $1.time }
            guard let last = points.last, points.count >= 2 else { continue }
            series[cup] = Self.smoothed(Self.resampled(points, through: last.time))
        }
        self.series = series
        cups = Cup.allCases.compactMap { cup in
            guard let values = series[cup], let first = values.first, let last = values.last else { return nil }
            return CupSummary(cup: cup, start: first, end: last, low: values.min() ?? first, high: values.max() ?? first)
        }
        events = Cup.allCases.flatMap { cup in series[cup].map { Self.events(cup, $0) } ?? [] }
            .sorted { $0.seconds < $1.seconds }
    }

    /// The smoothed temperature of a cup at a moment, if the probe was reading then.
    public func celsius(_ cup: Cup, at seconds: Double) -> Double? {
        guard let values = series[cup], !values.isEmpty else { return nil }
        let index = Int(seconds.rounded())
        guard index >= 0, index < values.count else { return nil }
        return values[index]
    }

    /// The probe summary as Gemini sees it.
    public var text: String {
        let ranges = cups.map { cup in
            "Cup \(cup.cup.rawValue): \(Event.one(cup.start)) °C at the start, \(Event.one(cup.end)) °C at the end, "
                + "lowest \(Event.one(cup.low)), highest \(Event.one(cup.high))."
        }
        let moments = events.isEmpty ? ["No jumps or changes of pace."] : events.map(\.description)
        return (ranges + ["What the probes did:"] + moments).joined(separator: "\n")
    }

    // MARK: Working it out

    /// Linear interpolation onto whole seconds from 0.
    private static func resampled(_ points: [Reading], through end: Double) -> [Double] {
        var values: [Double] = []
        var index = 0
        for second in 0...Int(end) {
            let t = Double(second)
            while index + 1 < points.count, points[index + 1].time < t { index += 1 }
            let a = points[index], b = points[min(index + 1, points.count - 1)]
            if t <= a.time || b.time <= a.time {
                values.append(a.celsius)
            } else {
                let fraction = min(1, (t - a.time) / (b.time - a.time))
                values.append(a.celsius + (b.celsius - a.celsius) * fraction)
            }
        }
        return values
    }

    /// A 3-second moving average, to keep probe noise from looking like events.
    private static func smoothed(_ values: [Double]) -> [Double] {
        values.indices.map { index in
            let window = values[max(0, index - 1)...min(values.count - 1, index + 1)]
            return window.reduce(0, +) / Double(window.count)
        }
    }

    private static func events(_ cup: Cup, _ values: [Double]) -> [Event] {
        var events: [Event] = []
        // Jumps: four-second stretches changing faster than `jumpRate`, merged while they last.
        let step = 4
        var jumping: [Int] = []
        if values.count > step {
            for start in 0..<(values.count - step) {
                if abs(values[start + step] - values[start]) / Double(step) >= jumpRate { jumping.append(start) }
            }
        }
        var runs: [[Int]] = []
        for index in jumping {
            if let last = runs.last?.last, index - last <= 2 { runs[runs.count - 1].append(index) } else { runs.append([index]) }
        }
        for run in runs {
            guard let first = run.first, let last = run.last else { continue }
            let end = min(last + step, values.count - 1)
            // When it really started: the first second that moved fast.
            let start = (first..<end).first { abs(values[$0 + 1] - values[$0]) >= jumpRate } ?? first
            let from = values[start], to = values[end]
            events.append(Event(cup: cup, kind: to > from ? .rose : .dropped, seconds: Double(start), from: from, to: to))
        }

        // Changes of pace: the cooling rate over the 20 s before and after each moment, away from jumps.
        let span = 20
        let quiet = { (range: ClosedRange<Int>) in runs.allSatisfy { run in
            guard let first = run.first, let last = run.last else { return true }
            return last + step < range.lowerBound - 2 || first > range.upperBound + 2
        } }
        var best: (seconds: Int, ratio: Double, before: Double, after: Double)?
        func flush() {
            if let found = best {
                events.append(Event(cup: cup, kind: abs(found.after) < abs(found.before) ? .slowed : .spedUp,
                                    seconds: Double(found.seconds), from: found.before, to: found.after))
            }
            best = nil
        }
        if values.count > 2 * span {
            for t in stride(from: span, through: values.count - 1 - span, by: 2) {
                guard quiet((t - span)...(t + span)) else { flush(); continue }
                let before = (values[t] - values[t - span]) / Double(span)
                let after = (values[t + span] - values[t]) / Double(span)
                guard before < 0, after < 0, max(abs(before), abs(after)) > 0.01 else { flush(); continue }
                let ratio = max(abs(before), abs(after)) / max(min(abs(before), abs(after)), 0.001)
                if ratio >= paceRatio {
                    if best == nil || ratio > best!.ratio { best = (t, ratio, before, after) }
                } else {
                    flush()
                }
            }
            flush()
        }
        return events
    }
}
