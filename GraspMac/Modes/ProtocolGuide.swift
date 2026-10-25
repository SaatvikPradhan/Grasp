import Foundation
import GraspKit
import Observation

/// Walks someone through a protocol at the bench. Hand Grasp the protocol page, say "I'm starting
/// the experiment", and it reads each step aloud, watches the probes to know when a step is done
/// (a pour shows as a jump, a wait as a temperature reached), times everything, notes anything
/// done differently from the page, and writes the notebook at the end. "Done" or the board's
/// button moves on when the probes can't tell.
@MainActor @Observable
final class ProtocolGuide {
    private(set) var run: ProtocolRun?
    /// The last run, once it's finished, so its steps and times stay on the card.
    private(set) var lastRun: ProtocolRun?
    private(set) var elapsed = 0.0
    private(set) var isReading = false
    /// What the bench camera sees now, for the card.
    private(set) var seeing: String?
    /// The protocol on the canvas, ready to run.
    private(set) var ready: (lab: LabProtocol, documentID: UUID)?

    var isRunning: Bool { run != nil && !(run?.isFinished ?? true) }

    @ObservationIgnored private let canvas: CanvasModel
    @ObservationIgnored private let probes: ProbeHub
    @ObservationIgnored private let lab: LabSession
    @ObservationIgnored private let voiceOut: VoiceOut
    @ObservationIgnored private var started = Date()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var watcher: Task<Void, Never>?
    /// The last look: which step it was on, the frame it looked at, and what it said, so a step
    /// finishes, or a mistake is spoken, only when two looks in a row agree.
    @ObservationIgnored private var lastLook: (step: Int, frame: Double, done: Bool, differs: String?)?

    init(canvas: CanvasModel, probes: ProbeHub, lab: LabSession, voiceOut: VoiceOut) {
        self.canvas = canvas
        self.probes = probes
        self.lab = lab
        self.voiceOut = voiceOut
    }

    /// Every page read comes here: a protocol becomes steps, shown beside its page.
    func pageRead(_ document: PageDocument) {
        guard Self.isProtocol(document) else { return }
        Task { await read(document) }
    }

    private func read(_ document: PageDocument) async {
        guard let client = GeminiClient.fromAppKeys else { return }
        isReading = true
        defer { isReading = false }
        guard let lab = try? await ProtocolReader(client: client).read(page: document.text, title: document.reading.title) else { return }
        ready = (lab, document.id)
        run = nil
        canvas.showGuide(GuideCard(documentID: document.id, lab: lab))
    }

    // MARK: Running

    /// "I'm starting the experiment": starts the lab notes and the first step.
    @discardableResult
    func start() -> String {
        guard let ready else { return "Hand Grasp the protocol first" }
        guard !isRunning else { return "Already on step \((run?.current ?? 0) + 1)" }
        _ = lab.start()
        started = Date()
        elapsed = 0
        run = ProtocolRun(ready.lab, at: 0, celsius: celsius)
        lastRun = nil
        canvas.showGuide(GuideCard(documentID: ready.documentID, lab: ready.lab))
        canvas.layOutGuidedRun()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        seeing = nil
        lastLook = nil
        watcher?.cancel()
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.lookEvery))
                await self?.look()
            }
        }
        announce()
        return "Guiding \(ready.lab.title): \(ready.lab.steps.count) steps"
    }

    /// "Done" or "next", or the board's button. On simulated probes, the step's pours, lids and
    /// ice happen on the bench, and the probes confirm it as they would a real pour.
    @discardableResult
    func next() -> String {
        guard var run, let step = run.step else { return start() }
        let simulated = step.actions.allSatisfy { act($0) } && !step.actions.isEmpty
        switch step.check {
        case .rises where simulated, .drops where simulated:
            return "Watching the probe"
        default:
            break
        }
        if let done = run.sayDone(at: now, celsius: celsius) {
            self.run = run
            finished(done)
        }
        return run.isFinished ? "Every step is done" : "Step \(run.current + 1)"
    }

    /// "Go back".
    @discardableResult
    func back() -> String {
        guard var run else { return "Nothing to go back to" }
        run.back(at: now, celsius: celsius)
        self.run = run
        announce()
        return "Back to step \(run.current + 1)"
    }

    /// "Say that again".
    @discardableResult
    func again() -> String {
        announce()
        return "Step \((run?.current ?? 0) + 1)"
    }

    /// "We're done": stops and writes the notebook with the protocol in it.
    @discardableResult
    func finish() async -> String {
        guard let run else { return await lab.stop() }
        ticker?.cancel()
        ticker = nil
        watcher?.cancel()
        watcher = nil
        seeing = nil
        let record = ProtocolRecord(run)
        lastRun = run
        self.run = nil
        return await lab.stop(protocol: record)
    }

    // MARK: Watching

    /// Seconds between looks at the bench.
    static let lookEvery = 5.0

    /// Looks at the newest bench frame against the current step. A step the probes can't check
    /// finishes when two looks in a row see it done; something done differently from the page is
    /// said out loud and noted when two looks in a row see it.
    private func look() async {
        guard let run, let step = run.step, let frame = lab.latestFrame, frame.seconds != lastLook?.frame,
              let client = GeminiClient.fromAppKeys else { return }
        let index = run.current
        let next = run.lab.steps.indices.contains(index + 1) ? run.lab.steps[index + 1] : nil
        guard let seen = try? await BenchWatcher(client: client).look(at: frame.jpeg, step: step, next: next),
              var current = self.run, current.current == index else { return }
        seeing = seen.seeing
        let agreed = lastLook.map { $0.step == index } ?? false
        let differs = agreed && seen.differs != nil && seen.differs == lastLook?.differs ? seen.differs : nil
        let done = agreed && seen.stepDone && lastLook?.done == true
        lastLook = (index, frame.seconds, seen.stepDone, seen.differs)
        let before = current.deviations.count
        let finishedStep = current.cameraSaw(seen.seeing, stepDone: done, differs: differs, at: now, celsius: celsius)
        self.run = current
        if current.deviations.count > before, let differs {
            Task { await voiceOut.say("Heads up: \(differs)") }
        }
        if let finishedStep { finished(finishedStep) }
    }

    // MARK: Working

    private var now: Double { Date().timeIntervalSince(started) }

    private var celsius: [Cup: Double] {
        probes.latest.filter { !probes.isStale($0.key) }.mapValues(\.celsius)
    }

    private func tick() {
        elapsed = now
        guard var run, !run.isFinished else { return }
        let before = run.deviations.count
        if let done = run.update(celsius, at: now) {
            self.run = run
            finished(done)
        } else if run.deviations.count != before {
            self.run = run
        }
    }

    /// A step is done: mark the chart, flash the cup that changed, and say the next step.
    private func finished(_ done: ProtocolRun.Done) {
        guard let run else { return }
        let step = run.lab.steps[done.step]
        probes.mark("step \(step.number) ✓")
        switch step.check {
        case .rises(let cup), .drops(let cup):
            let (r, g, b) = Self.color(cup)
            probes.send(ProbeProtocol.flash(r: r, g: g, b: b, ms: 600))
        default:
            break
        }
        if run.isFinished {
            Task { await voiceOut.say("That's every step. Writing up your notes.") }
            Task { await finish() }
        } else {
            announce()
        }
    }

    private func announce() {
        guard let run, let step = run.step else { return }
        Task { await voiceOut.say("Step \(step.number) of \(run.lab.steps.count). \(step.instruction)") }
    }

    /// Does a step's action to the simulated bench. False on real probes: real hands do it.
    private func act(_ action: LabProtocol.Step.Action) -> Bool {
        switch action {
        case .pour(let cup): probes.simulate(.pour(cup, celsius: 88))
        case .lid(let cup): probes.simulate(.lid(cup, on: true))
        case .ice(let cup): probes.simulate(.ice(cup))
        }
    }

    static func color(_ cup: Cup) -> (Int, Int, Int) {
        switch cup {
        case .a: (242, 122, 94)
        case .b: (56, 194, 168)
        case .c: (90, 169, 240)
        }
    }

    private static func isProtocol(_ document: PageDocument) -> Bool {
        let words = (document.reading.kind + " " + document.reading.title).lowercased()
        return ["protocol", "procedure", "lab instructions", "lab handout", "lab sheet"].contains { words.contains($0) }
    }
}
