import Foundation

/// A lab protocol as steps Grasp can follow: each step's words from the page, and how Grasp
/// will know it's done, from the probes where it can (a pour shows as a jump, a wait as a
/// temperature reached) and otherwise when you say so.
public struct LabProtocol: Equatable, Sendable {
    public struct Step: Equatable, Sendable, Identifiable {
        public enum Check: Equatable, Sendable {
            /// You say "done" or "next".
            case sayDone
            /// The cup's probe jumps up: something hot poured in.
            case rises(Cup)
            /// The cup's probe jumps down: ice dropped in.
            case drops(Cup)
            /// Wait until the cup is under this temperature.
            case below(Cup, Double)
            /// Wait until the cup is over this temperature.
            case above(Cup, Double)
            /// A timer, in seconds.
            case wait(Double)
        }

        /// What the step does to the bench, for the simulated probes to act out.
        public enum Action: Equatable, Sendable {
            case pour(Cup)
            case lid(Cup)
            case ice(Cup)
        }

        public var number: Int
        /// Short and imperative: "Pour hot water into cup B and put the lid on".
        public var instruction: String
        public var cited: Cited
        public var check: Check
        public var actions: [Action]

        public var id: Int { number }

        public init(number: Int, instruction: String, cited: Cited, check: Check, actions: [Action] = []) {
            self.number = number
            self.instruction = instruction
            self.cited = cited
            self.check = check
            self.actions = actions
        }
    }

    public var title: String
    public var steps: [Step]

    public init(title: String, steps: [Step]) {
        self.title = title
        self.steps = steps
    }
}

/// A protocol as it was followed, for the notebook: each step, when it was done and how Grasp knew.
public struct ProtocolRecord: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public var number: Int
        public var instruction: String
        /// Seconds into the run, when it was done; nil if the run stopped first.
        public var finished: Double?
        /// "probe B rose from 21.5 to 88.0 °C", "timer", "you said done".
        public var how: String?
    }

    public var title: String
    public var steps: [Step]
    public var deviations: [ProtocolRun.Deviation]

    public init(_ run: ProtocolRun) {
        title = run.lab.title
        steps = run.lab.steps.enumerated().map { index, step in
            let done = run.done.first { $0.step == index }
            let how: String? = switch done?.how {
            case .probe(let text): text
            case .timer: "timer"
            case .said: "you said done"
            case nil: nil
            }
            return Step(number: step.number, instruction: step.instruction, finished: done?.finished, how: how)
        }
        deviations = run.deviations
    }

    /// The log as the notebook writer reads it.
    public var text: String {
        let lines = steps.map { step in
            step.finished.map { "\(clockTime($0)) step \(step.number) done (\(step.how ?? "")): \(step.instruction)" }
                ?? "step \(step.number) not reached: \(step.instruction)"
        }
        let off = deviations.map { "\(clockTime($0.seconds)) differed from the protocol: \($0.text)" }
        return ([title] + lines + off).joined(separator: "\n")
    }
}

/// A protocol being followed: which step it's on, when each step was done and how Grasp knows,
/// and anything that went differently from the page (a step done early, cut short, or said done
/// without the probe seeing it). Fed the latest readings once a second.
public struct ProtocolRun: Equatable, Sendable {
    public enum How: Equatable, Sendable {
        /// The probe saw it: "probe A rose from 21.6 to 87.9 °C".
        case probe(String)
        case timer
        /// You said it was done.
        case said
    }

    public struct Done: Equatable, Sendable {
        /// Index into the protocol's steps.
        public var step: Int
        public var started: Double
        public var finished: Double
        public var how: How
        public var celsius: [Cup: Double]
    }

    /// Something that went differently from the page.
    public struct Deviation: Equatable, Sendable {
        public var seconds: Double
        public var text: String
    }

    /// A jump this big, in °C, is a pour or ice.
    public static let jump = 5.0

    public let lab: LabProtocol
    public private(set) var current = 0
    public private(set) var stepStarted: Double
    public private(set) var done: [Done] = []
    public private(set) var deviations: [Deviation] = []
    /// Each cup's temperature when the current step started.
    private var baseline: [Cup: Double] = [:]
    /// Later steps a probe already saw happen, and how.
    private var early: [Int: Seen] = [:]

    private struct Seen: Equatable, Sendable {
        var seconds: Double
        var how: How
    }

    public init(_ lab: LabProtocol, at seconds: Double, celsius: [Cup: Double] = [:]) {
        self.lab = lab
        stepStarted = seconds
        baseline = celsius
    }

    public var isFinished: Bool { current >= lab.steps.count }
    public var step: LabProtocol.Step? { lab.steps.indices.contains(current) ? lab.steps[current] : nil }

    /// Takes the latest reading of each cup. Returns the step it finished, if one finished.
    public mutating func update(_ celsius: [Cup: Double], at seconds: Double) -> Done? {
        for (cup, value) in celsius where baseline[cup] == nil { baseline[cup] = value }
        watchAhead(celsius, at: seconds)
        guard let step else { return nil }
        if let seen = early[current] { return finish(at: seen.seconds, how: seen.how, celsius: celsius) }
        switch step.check {
        case .sayDone:
            return nil
        case .rises(let cup):
            guard let now = celsius[cup], let before = baseline[cup], now - before >= Self.jump else { return nil }
            return finish(at: seconds, how: .probe("probe \(cup.rawValue) rose from \(Self.one(before)) to \(Self.one(now)) °C"), celsius: celsius)
        case .drops(let cup):
            guard let now = celsius[cup], let before = baseline[cup], before - now >= Self.jump else { return nil }
            return finish(at: seconds, how: .probe("probe \(cup.rawValue) dropped from \(Self.one(before)) to \(Self.one(now)) °C"), celsius: celsius)
        case .below(let cup, let limit):
            guard let now = celsius[cup], now < limit else { return nil }
            return finish(at: seconds, how: .probe("probe \(cup.rawValue) read \(Self.one(now)) °C, below \(Self.one(limit))"), celsius: celsius)
        case .above(let cup, let limit):
            guard let now = celsius[cup], now > limit else { return nil }
            return finish(at: seconds, how: .probe("probe \(cup.rawValue) read \(Self.one(now)) °C, above \(Self.one(limit))"), celsius: celsius)
        case .wait(let length):
            guard seconds - stepStarted >= length else { return nil }
            return finish(at: seconds, how: .timer, celsius: celsius)
        }
    }

    /// "Done" or "next": finishes the current step on your word, noting when the page asked for
    /// something the probes didn't see or a wait that was cut short.
    public mutating func sayDone(at seconds: Double, celsius: [Cup: Double]) -> Done? {
        guard let step else { return nil }
        if let seen = early[current] { return finish(at: seen.seconds, how: seen.how, celsius: celsius) }
        let number = step.number
        switch step.check {
        case .sayDone:
            break
        case .rises(let cup), .drops(let cup):
            note(seconds, "Step \(number): you said done, but probe \(cup.rawValue) didn't see it")
        case .below(let cup, let limit):
            note(seconds, "Step \(number): moved on with cup \(cup.rawValue) at \(celsius[cup].map(Self.one) ?? "?") °C, before it was below \(Self.one(limit))")
        case .above(let cup, let limit):
            note(seconds, "Step \(number): moved on with cup \(cup.rawValue) at \(celsius[cup].map(Self.one) ?? "?") °C, before it was above \(Self.one(limit))")
        case .wait(let length):
            note(seconds, "Step \(number): the \(clockTime(length)) wait ended after \(clockTime(seconds - stepStarted))")
        }
        return finish(at: seconds, how: .said, celsius: celsius)
    }

    /// Goes back a step, for "go back".
    public mutating func back(at seconds: Double, celsius: [Cup: Double]) {
        guard current > 0 else { return }
        current -= 1
        done.removeAll { $0.step >= current }
        stepStarted = seconds
        baseline = celsius
    }

    /// What the current step is waiting on, in words, and how far along it is (0 to 1) when that's measurable.
    public func waiting(_ celsius: [Cup: Double], at seconds: Double) -> (text: String, fraction: Double?) {
        guard let step else { return ("Every step is done", 1) }
        switch step.check {
        case .sayDone:
            return ("Say “done” when it's done", nil)
        case .rises(let cup):
            return ("Watching probe \(cup.rawValue) for the pour", rise(cup, celsius, up: true))
        case .drops(let cup):
            return ("Watching probe \(cup.rawValue) for the drop", rise(cup, celsius, up: false))
        case .below(let cup, let limit), .above(let cup, let limit):
            guard let now = celsius[cup], let start = baseline[cup] else { return ("Waiting for probe \(cup.rawValue)", nil) }
            let fraction = start == limit ? 1 : min(max((start - now) / (start - limit), 0), 1)
            return ("Cup \(cup.rawValue) at \(Self.one(now)) °C, waiting for \(Self.one(limit))", fraction)
        case .wait(let length):
            let left = max(length - (seconds - stepStarted), 0)
            return ("\(clockTime(left)) left", min((seconds - stepStarted) / length, 1))
        }
    }

    // MARK: Working

    private mutating func finish(at seconds: Double, how: How, celsius: [Cup: Double]) -> Done {
        let record = Done(step: current, started: stepStarted, finished: seconds, how: how, celsius: celsius)
        done.append(record)
        early[current] = nil
        current += 1
        stepStarted = seconds
        baseline = celsius
        return record
    }

    /// A pour or ice that belongs to a later step, seen now: it happened early.
    private mutating func watchAhead(_ celsius: [Cup: Double], at seconds: Double) {
        for index in lab.steps.indices where index > current && early[index] == nil {
            let later = lab.steps[index]
            let (cup, up): (Cup, Bool)
            switch later.check {
            case .rises(let c): (cup, up) = (c, true)
            case .drops(let c): (cup, up) = (c, false)
            default: continue
            }
            // Only if no step before it watches the same cup.
            let watchedSooner = lab.steps[current..<index].contains { step in
                switch step.check {
                case .rises(let c), .drops(let c), .below(let c, _), .above(let c, _): c == cup
                default: false
                }
            }
            guard !watchedSooner, let now = celsius[cup], let before = baseline[cup],
                  up ? now - before >= Self.jump : before - now >= Self.jump else { continue }
            let what = "probe \(cup.rawValue) \(up ? "rose" : "dropped") from \(Self.one(before)) to \(Self.one(now)) °C"
            early[index] = Seen(seconds: seconds, how: .probe(what))
            note(seconds, "Step \(later.number) happened early: \(what) while step \(lab.steps[current].number) was still open")
            baseline[cup] = now
        }
    }

    private func rise(_ cup: Cup, _ celsius: [Cup: Double], up: Bool) -> Double? {
        guard let now = celsius[cup], let before = baseline[cup] else { return nil }
        return min(max((up ? now - before : before - now) / Self.jump, 0), 1)
    }

    private mutating func note(_ seconds: Double, _ text: String) {
        deviations.append(Deviation(seconds: seconds, text: text))
    }

    static func one(_ value: Double) -> String { String(format: "%.1f", value) }
}
