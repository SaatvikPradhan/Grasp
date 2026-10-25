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
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var clearTask: Task<Void, Never>?
    /// Listening because a hand is making a fist, so opening it sends.
    @ObservationIgnored private var talkingByFist = false

    init(canvas: CanvasModel, money: MoneyMode, asker: Asker) {
        self.canvas = canvas
        self.money = money
        self.asker = asker
    }

    /// Hearing or working out a command, so the conversation listener should ignore the words.
    var isBusy: Bool {
        switch phase {
        case .listening, .thinking: true
        default: false
        }
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
            guard event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  !(event.window is NSPanel) else { return event }
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
        let fist = hands.contains(where: \.isFist)
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
            return canvas.deleteFrontCard() ? "Threw away the card in front" : "There's nothing to throw away"
        case .clearCanvas:
            canvas.clearCanvas()
            return "Cleared the canvas"
        case .comingSoon(let request):
            return "\"\(request.capitalized)\" comes with Research mode"
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
