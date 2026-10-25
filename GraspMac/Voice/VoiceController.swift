import AppKit
import GraspKit
import Observation

/// Talk to Grasp: make a fist (like gripping a mic), speak, open your hand. Holding Space
/// works too. Gemini turns the words into a command, which runs on the canvas.
@MainActor @Observable
final class VoiceController {
    enum Phase: Equatable {
        case idle
        case listening
        case thinking(heard: String)
        case done(heard: String, result: String)
        case failed(String)
    }

    private(set) var phase = Phase.idle
    let listener = SpeechListener()

    @ObservationIgnored private let canvas: CanvasModel
    @ObservationIgnored private let money: MoneyMode
    @ObservationIgnored private let asker: Asker
    @ObservationIgnored private let researcher: Researcher
    @ObservationIgnored private let lab: LabSession
    @ObservationIgnored private let guide: ProtocolGuide
    @ObservationIgnored private let disputer: Disputer
    @ObservationIgnored private let diver: DeepDiver
    @ObservationIgnored private let planner: PagePlanner
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var clearTask: Task<Void, Never>?
    /// Listening because a hand is making a fist, so opening it sends.
    @ObservationIgnored private var talkingByFist = false
    /// While lab notes record, the words heard before the fist or Space, as the lab's listener has the mic.
    @ObservationIgnored private var labWordsBefore: Int?

    init(canvas: CanvasModel, money: MoneyMode, asker: Asker, researcher: Researcher, lab: LabSession, guide: ProtocolGuide,
         disputer: Disputer, diver: DeepDiver, planner: PagePlanner) {
        self.canvas = canvas
        self.money = money
        self.asker = asker
        self.researcher = researcher
        self.lab = lab
        self.guide = guide
        self.disputer = disputer
        self.diver = diver
        self.planner = planner
        lab.ignoresCommands = { [weak self] in self.map { $0.isWorking || $0.money.voiceOut.isSpeaking } ?? true }
        lab.onCommand = { [weak self] command, heard in self?.benchCommand(command, heard: heard) }
    }

    /// Hearing or working out a command, so the conversation listener should ignore the words.
    var isBusy: Bool {
        switch phase {
        case .listening, .thinking: true
        default: false
        }
    }

    /// Working out a command, so words at the bench shouldn't start another.
    private var isWorking: Bool {
        if case .thinking = phase { true } else { false }
    }

    func start() async {
        installPushToTalk()
        await listener.prepare()
    }

    /// Space with no modifier keys is the talk key, anywhere in the app.
    private func installPushToTalk() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            // Leave Space alone in dialogs such as the ⌘O file picker.
            // and in a note being typed on the canvas.
            guard event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  !(event.window is NSPanel), !((event.window?.firstResponder as? NSTextView)?.isEditable ?? false) else { return event }
            MainActor.assumeIsolated {
                if event.type == .keyDown, !event.isARepeat {
                    self?.beginTalking()
                } else if event.type == .keyUp {
                    self?.endTalking()
                }
            }
            return nil
        }
    }

    /// Every camera frame: a fist starts listening, opening it (or the hand leaving) sends.
    func handsChanged(_ hands: [TrackedHand]) {
        // At the bench a hand around a cup or kettle looks like a fist, and "done" needs no fist.
        let fist = hands.contains(where: \.isFist) && !lab.isRecording
        if fist, !talkingByFist, phase != .listening {
            talkingByFist = true
            beginTalking()
        } else if !fist, talkingByFist {
            talkingByFist = false
            endTalking()
        }
    }

    func beginTalking() {
        clearTask?.cancel()
        // Lab notes already have the mic: a second recognizer would cut them off.
        if lab.isRecording {
            labWordsBefore = lab.wordsHeard()
            phase = .listening
            return
        }
        switch listener.availability {
        case .ready:
            phase = .listening
            listener.start()
        case .unavailable(let reason):
            show(.failed(reason))
        case .unknown:
            show(.failed("Still asking for the microphone. Try again in a moment."))
        }
    }

    func endTalking() {
        if let before = labWordsBefore {
            labWordsBefore = nil
            // "Done" said while holding is already handled by the bench listener.
            guard phase == .listening else { return }
            Task { [weak self] in
                // The last words arrive a moment after they're said.
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, phase == .listening else { return }
                interpret(lab.words(since: before))
            }
            return
        }
        guard phase == .listening else { return }
        listener.stop { [weak self] words in
            self?.interpret(words)
        }
    }

    private func interpret(_ words: String) {
        let heard = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else {
            show(.failed("Didn't catch that. Keep holding Space while you talk."))
            return
        }
        guard let client = GeminiClient.fromAppKeys else {
            show(.failed(GeminiClient.Failure.missingKey.localizedDescription))
            return
        }
        phase = .thinking(heard: heard)
        let context = canvas.voiceContext
        Task {
            do {
                let command = try await VoiceCommander(client: client).interpret(heard, context: context)
                show(.done(heard: heard, result: await perform(command)))
            } catch {
                show(.failed(error.localizedDescription))
            }
        }
    }

    /// A command said at the bench while lab notes run, heard without a fist or Space. With no
    /// guided run, only "stop" means anything: "done" on its own might just be talk.
    private func benchCommand(_ command: BenchCommand, heard: String) {
        let voiceCommand: VoiceCommand = switch command {
        case .next: .protocolStep(.next)
        case .back: .protocolStep(.back)
        case .again: .protocolStep(.again)
        case .finish: .finishExperiment
        }
        guard guide.isRunning || command == .finish else { return }
        clearTask?.cancel()
        phase = .thinking(heard: heard)
        Task { show(.done(heard: heard, result: await perform(voiceCommand))) }
    }

    /// Runs a command and says what happened.
    private func perform(_ command: VoiceCommand) async -> String {
        switch command {
        case .setTerm(let months):
            guard let term = canvas.setTerm(months) else { return "There's no loan on the canvas yet" }
            return "Term set to \(term) months"
        case .setRate(let apr):
            return canvas.setRate(apr) ? "Rate set to \(apr.formatted())%" : "There's no loan on the canvas yet"
        case .compare:
            return canvas.compareLoans() ? "Comparing the two loans" : "Scan a second offer to compare, or press ⌘U for the demo quote"
        case .switchChart:
            canvas.toggleFrontStyle()
            return "Switched between bars and lines"
        case .showTemperatures(let show):
            if show != canvas.showsTemperatures { canvas.toggleTemperatures() }
            return show ? "Showing cup temperatures" : "Hid cup temperatures"
        case .reset:
            canvas.resetLayout()
            return "Canvas reset"
        case .whatToSay:
            return await money.whatToSay()
        case .listenToPitch(let on):
            return money.listenToPitch(on)
        case .summary:
            return await money.saveSummary()
        case .ask(let question):
            return await asker.ask(question)
        case .removeCard:
            return canvas.deleteFocusedCard() ? "Threw away the card in focus" : "There's nothing to throw away"
        case .clearCanvas:
            canvas.clearCanvas()
            return "Cleared the canvas"
        case .checkNotes:
            return await researcher.linkLatestNotes()
        case .labNotes(let on):
            if !on, guide.isRunning { return await guide.finish() }
            return on ? lab.start() : await lab.stop()
        case .startExperiment:
            // With a protocol on the canvas, guide it; otherwise just take notes.
            return guide.ready == nil ? lab.start() : guide.start()
        case .protocolStep(let move):
            switch move {
            case .next: return guide.next()
            case .back: return guide.back()
            case .again: return guide.again()
            }
        case .mapMethod:
            return await researcher.mapMethod()
        case .findRelatedWork:
            return await researcher.findRelatedWork()
        case .writeDispute:
            return await disputer.write()
        case .deepDive:
            return await diver.dive()
        case .whatToDo:
            return await planner.planFocusedPage()
        case .putAway:
            return canvas.putAway() ? "Put away" : "Nothing to put away"
        case .takeNote(let text):
            canvas.showNotePad(adding: text)
            return "Noted"
        case .finishExperiment:
            return guide.isRunning ? await guide.finish() : await lab.stop()
        case .saveNotebook:
            return await lab.save()
        case .comingSoon(let request):
            return "\"\(request.capitalized)\" isn't built yet"
        case .none:
            return "That didn't sound like a command"
        }
    }

    /// Shows a result for a few seconds, then goes quiet.
    private func show(_ phase: Phase) {
        self.phase = phase
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.phase = .idle
        }
    }
}
