import AppKit
import GraspKit
import Observation

/// The car deal: what to say, the salesperson's pitch checked, and the one-page summary.
@MainActor @Observable
final class MoneyMode {
    private(set) var isWritingAdvice = false
    /// Everything the salesperson said that Grasp caught, oldest first.
    private(set) var pitchChecks: [PitchCheck] = []

    let conversation = ConversationListener()
    let voiceOut = VoiceOut()
    /// True while someone is giving Grasp a command, so those words aren't taken for the pitch.
    @ObservationIgnored var isTakingCommand: () -> Bool = { false }

    @ObservationIgnored private let canvas: CanvasModel

    init(canvas: CanvasModel) {
        self.canvas = canvas
        conversation.onText = { [weak self] text in
            self?.heard(text)
        }
    }

    // MARK: What to say

    /// Phrases the talking points, puts them on the canvas and reads them out.
    /// Returns a line for the voice bar.
    @discardableResult
    func whatToSay() async -> String {
        guard let facts = canvas.moneyFacts(pitchChecks: pitchChecks) else {
            return "Scan the contract first, then ask again"
        }
        isWritingAdvice = true
        defer { isWritingAdvice = false }
        let advice = await AdviceWriter(client: GeminiClient.fromAppKeys).write(for: facts)
        canvas.showAdvice(advice)
        Task { await voiceOut.say(advice.spoken) }
        return "Here's what to say"
    }

    // MARK: The pitch

    /// Turns listening to the salesperson on or off. Asks first: Pennsylvania requires everyone's
    /// consent to record a conversation. Returns a line for the voice bar.
    @discardableResult
    func listenToPitch(_ on: Bool) -> String {
        guard on else {
            conversation.stop()
            return "Stopped listening to the conversation"
        }
        guard !conversation.isOn else { return "Already listening to the conversation" }
        let alert = NSAlert()
        alert.messageText = "Has everyone here agreed to be listened to?"
        alert.informativeText = "Grasp will transcribe the conversation to check what's said against the paper. Pennsylvania requires everyone's consent. Nothing is saved."
        alert.addButton(withTitle: "Everyone agreed")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return "Not listening: no consent" }
        if let problem = conversation.start() { return problem }
        return "Listening to the conversation, with consent"
    }

    private func heard(_ text: String) {
        // Grasp's own voice and the user's commands aren't the salesperson.
        guard !voiceOut.isSpeaking, !isTakingCommand() else { return }
        let offer = canvas.moneyFacts()?.pitch ?? LoanTerms.demoContract
        let new = PitchChecker.checks(in: text, against: offer).filter { check in
            !pitchChecks.contains { $0.id == check.id }
        }
        guard !new.isEmpty else { return }
        pitchChecks += new
        canvas.showPitchChecks(pitchChecks)
    }

    // MARK: Summary

    /// Saves the one-page decision summary (to the Desktop unless told otherwise) and opens it.
    /// Returns a line for the voice bar.
    @discardableResult
    func saveSummary(to destination: URL = DecisionSummary.defaultURL, open: Bool = true) async -> String {
        guard let facts = canvas.moneyFacts(pitchChecks: pitchChecks) else {
            return "Scan the contract first, then ask for the summary"
        }
        let advice = canvas.cards.lazy.compactMap { card -> Advice? in
            if case .advice(let advice) = card.kind { return advice }
            return nil
        }.first
        let lines = advice?.lines ?? Array(facts.talkingPoints().prefix(3))
        guard let url = DecisionSummary.save(facts: facts, whatToSay: lines, to: destination) else {
            return "Couldn't save the summary"
        }
        if open { NSWorkspace.shared.open(url) }
        return "Saved the decision summary to your Desktop"
    }
}
