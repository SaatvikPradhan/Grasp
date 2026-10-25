import AppKit
import GraspKit
import Observation

/// From a bill to a letter that gets money back: what's wrong, each amount worked out in Swift
/// from the bill's own numbers, and the wording around them, ready to copy and send.
@MainActor @Observable
final class Disputer {
    private(set) var isWriting = false

    @ObservationIgnored private let canvas: CanvasModel

    init(canvas: CanvasModel) {
        self.canvas = canvas
    }

    /// Writes the dispute for the page in focus, or the newest page with something wrong on it.
    @discardableResult
    func write() async -> String {
        guard let client = GeminiClient.fromAppKeys else { return GeminiClient.Failure.missingKey.localizedDescription }
        let pages = canvas.cards.compactMap { canvas.document(for: $0) }
        guard let bill = canvas.focusedDocument ?? pages.filter({ !$0.reading.allCatches.isEmpty }).max(by: { $0.readAt < $1.readAt }) else {
            return "Hand Grasp the bill first"
        }
        isWriting = true
        defer { isWriting = false }
        do {
            guard let letter = try await DisputeWriter(client: client).write(bill.reading) else {
                return "Nothing on \(bill.reading.title) to dispute"
            }
            canvas.showLetter(LetterCard(documentID: bill.id, letter: letter))
            return "Wrote the dispute: \(letter.total.formatted(.currency(code: "USD"))) to get back"
        } catch {
            return "Couldn't write the dispute: \(error.localizedDescription)"
        }
    }

    /// Puts the newest letter on the clipboard, ready to paste into an email or a chat with the company.
    @discardableResult
    func copy() -> String {
        guard let card = canvas.cards.last(where: { if case .letter = $0.kind { true } else { false } }),
              case .letter(let letter) = card.kind else { return "Write the dispute first" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(letter.letter.text, forType: .string)
        return "Copied the letter"
    }
}
