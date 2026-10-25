import CoreGraphics
import GraspKit
import Observation

/// Dives into the thing pointed at: two hands zoom into it (or ⌘⇧D, or "look this up"), a card
/// beside its page searches the web, and fills in with findings, each with the pages behind it.
@MainActor @Observable
final class DeepDiver {
    private(set) var isDiving = false

    @ObservationIgnored private let canvas: CanvasModel
    @ObservationIgnored private let voiceOut: VoiceOut

    init(canvas: CanvasModel, voiceOut: VoiceOut) {
        self.canvas = canvas
        self.voiceOut = voiceOut
    }

    /// Dives into what's at `point`, or what's hovered, or the card in focus. Returns a line for the voice bar.
    @discardableResult
    func dive(at point: CGPoint? = nil) async -> String {
        guard let client = GeminiClient.fromAppKeys else { return GeminiClient.Failure.missingKey.localizedDescription }
        guard let (subject, documentID) = canvas.deepDiveSubject(at: point) else { return "Point at something to dive into" }
        let cardID = canvas.showDeepDive(DeepDiveCard(documentID: documentID, subject: subject))
        isDiving = true
        defer { isDiving = false }
        do {
            let dive = try await DeepDiveFinder(client: client).dive(subject)
            canvas.updateDeepDive(cardID) { $0.dive = dive }
            if let bottomLine = dive.bottomLine { Task { await voiceOut.say(bottomLine) } }
            return "\(dive.findings.count) findings from \(dive.sources.count) sources"
        } catch {
            canvas.updateDeepDive(cardID) { $0.failure = "Couldn't search: \(error.localizedDescription)" }
            return "Couldn't search the web"
        }
    }
}
