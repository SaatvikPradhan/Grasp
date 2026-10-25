import AppKit
import GraspKit
import Observation

/// Answers any question about the pages on the canvas: the answer goes on a card with the
/// words that back it, is read aloud, and the phone shows the page with the sentence boxed.
@MainActor @Observable
final class Asker {
    private(set) var isAnswering = false

    /// Called with a phone capture and a box to show on it.
    @ObservationIgnored var onPointAt: ((UUID, LinkHighlight) -> Void)?

    @ObservationIgnored private let canvas: CanvasModel
    @ObservationIgnored private let voiceOut: VoiceOut
    /// The last few questions and answers, so "and without the late fee?" makes sense.
    @ObservationIgnored private var conversation: [Exchange] = []

    init(canvas: CanvasModel, voiceOut: VoiceOut) {
        self.canvas = canvas
        self.voiceOut = voiceOut
    }

    /// Returns a line for the voice bar.
    @discardableResult
    func ask(_ question: String) async -> String {
        guard let client = GeminiClient.fromAppKeys else { return GeminiClient.Failure.missingKey.localizedDescription }
        // The pages on the canvas, the one in focus first, then newest first; every page read if none are showing.
        let onCanvas = canvas.cards.reversed().compactMap { canvas.document(for: $0) }
        let focused = canvas.focusedDocument
        let documents = [focused].compactMap { $0 }
            + (onCanvas.isEmpty ? canvas.documents.values.sorted { $0.readAt > $1.readAt } : onCanvas).filter { $0.id != focused?.id }
        // A cleared canvas starts a new conversation.
        if canvas.cards.isEmpty { conversation = [] }
        isAnswering = true
        defer { isAnswering = false }
        do {
            let answer = try await QuestionAnswerer(client: client).answer(
                question,
                documents: documents.map { AskedDocument($0.reading, text: $0.text) } + canvas.notebookPages,
                canvas: canvas.voiceContext,
                earlier: conversation,
                focus: focused.map { $0.reading.title }
            )
            let sources = answer.quotes.compactMap { source(for: $0, in: documents) }
            canvas.showAnswer(AnswerCard(question: question, answer: answer, sources: sources,
                                         followsOn: conversation.last?.question))
            conversation = Array((conversation + [Exchange(question: question, answer: answer)]).suffix(4))
            if let first = sources.first(where: { $0.box != nil }),
               let capture = canvas.documents[first.documentID]?.captureID, let box = first.box {
                onPointAt?(capture, LinkHighlight(text: first.quote, rect: box, kind: .term))
            }
            Task { await voiceOut.say(answer.spoken) }
            return answer.numbersChecked ? "Answered, every number checked" : "Answered; check the numbers marked"
        } catch {
            return "Couldn't answer: \(error.localizedDescription)"
        }
    }

    /// Asks with a typed question, for when it's too loud to talk.
    func askByTyping() {
        let alert = NSAlert()
        alert.messageText = "Ask Grasp anything"
        alert.informativeText = "About the pages on the canvas: what, how much, can I, what if."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "Can I cancel early?"
        alert.accessoryView = field
        alert.addButton(withTitle: "Ask")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let question = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        Task { await ask(question) }
    }

    /// Finds a quote on one of the pages, and where it is on the photo.
    private func source(for quote: String, in documents: [PageDocument]) -> AnswerCard.Source? {
        for document in documents {
            guard let found = SourceLocator.locate(printed: nil, quote: quote, in: document.text) else { continue }
            let lines = document.lineBoxes[found.line...min(found.line + found.extraLines, document.lineBoxes.count - 1)]
            let box = lines.dropFirst().reduce(lines.first) { $0?.union($1) }
            return AnswerCard.Source(documentID: document.id, documentTitle: document.reading.title, quote: quote,
                                     box: box.flatMap { $0 == .zero ? nil : $0 })
        }
        // Not found on any page: keep it, unboxed, but only if it really is in a page's words.
        guard let document = documents.first(where: { $0.text.joined(separator: " ").localizedCaseInsensitiveContains(quote) }) else { return nil }
        return AnswerCard.Source(documentID: document.id, documentTitle: document.reading.title, quote: quote, box: nil)
    }
}
