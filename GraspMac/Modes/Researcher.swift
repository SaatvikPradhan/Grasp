import AppKit
import GraspKit
import Observation

/// The research side of the one engine: notes on a paper, linked to the passages they're about.
/// Hand Grasp a paper, then a page of notes, and the notes check themselves against the paper.
@MainActor @Observable
final class Researcher {
    private(set) var isLinking = false

    @ObservationIgnored private let canvas: CanvasModel

    init(canvas: CanvasModel) {
        self.canvas = canvas
    }

    /// Every page read comes here: a page of notes links itself to the paper on the canvas, and
    /// a paper with a model Swift can run becomes a live model beside it.
    func pageRead(_ document: PageDocument) {
        if Self.isNotes(document) {
            guard paper(besides: document) != nil else { return }
            Task { await link(notes: document.text.joined(separator: "\n"), from: document) }
        } else if Self.isPaper(document), !document.reading.kind.lowercased().contains("protocol") {
            Task { await runModel(of: document) }
        }
    }

    /// The paper the person is working on: the page in focus, or the newest paper on the canvas.
    var currentPaper: PageDocument? {
        if let focused = canvas.focusedDocument, !Self.isNotes(focused) { return focused }
        return canvas.cards.compactMap { canvas.document(for: $0) }.filter { Self.isPaper($0) }.max { $0.readAt < $1.readAt }
    }

    /// Maps the paper's method: what was varied, measured, held the same and left uncontrolled.
    @discardableResult
    func mapMethod() async -> String {
        guard let client = GeminiClient.fromAppKeys else { return GeminiClient.Failure.missingKey.localizedDescription }
        guard let paper = currentPaper else { return "Hand Grasp a paper first" }
        isLinking = true
        defer { isLinking = false }
        do {
            let map = try await MethodReader(client: client).read(paper: paper.text)
            canvas.showMethod(MethodCard(paperID: paper.id, paperTitle: paper.reading.title, map: map))
            return "Mapped the method: \(map.notControlled.count) things it didn't control"
        } catch {
            return "Couldn't map the method: \(error.localizedDescription)"
        }
    }

    /// Papers close to this one from OpenAlex, and whether each direction is already studied: the
    /// directions from linked notes when there are some, otherwise ones grown from the paper.
    @discardableResult
    func findRelatedWork() async -> String {
        guard let client = GeminiClient.fromAppKeys else { return GeminiClient.Failure.missingKey.localizedDescription }
        guard let paper = currentPaper else { return "Hand Grasp a paper first" }
        let given = canvas.cards.compactMap { card -> [RelatedWorkFinder.Given]? in
            guard case .notes(let notes) = card.kind, notes.paperID == paper.id else { return nil }
            return notes.linked.directions.map { RelatedWorkFinder.Given(title: $0.title, why: $0.why, cited: Cited(quote: $0.quote, location: $0.location)) }
        }.first ?? []
        isLinking = true
        defer { isLinking = false }
        do {
            let result = try await RelatedWorkFinder(client: client).find(paper: paper.text, title: paper.reading.title, directions: given)
            canvas.showRelated(RelatedCard(paperID: paper.id, paperTitle: paper.reading.title, result: result))
            let open = result.directions.filter { $0.verdict == .open }.count
            return "Found \(result.related.count) related papers; \(open) of \(result.directions.count) directions look open"
        } catch {
            return "Couldn't search the literature: \(error.localizedDescription)"
        }
    }

    /// Reads the paper's model and shows it running beside the paper.
    @discardableResult
    func runModel(of paper: PageDocument) async -> String {
        guard let client = GeminiClient.fromAppKeys else { return GeminiClient.Failure.missingKey.localizedDescription }
        isLinking = true
        defer { isLinking = false }
        do {
            guard let model = try await ModelReader(client: client).read(paper: paper.text) else {
                return "No model in \(paper.reading.title) that Grasp can run"
            }
            canvas.showModel(ModelCard(paperID: paper.id, paperTitle: paper.reading.title, model: model))
            let wrong = model.mismatches.count
            return wrong == 0 ? "The paper's model is running; its results follow from its equation"
                : "The paper's model is running; \(wrong) reported result\(wrong == 1 ? " doesn't" : "s don't") follow from its own equation"
        } catch {
            return "Couldn't read the paper's model: \(error.localizedDescription)"
        }
    }

    /// Links notes to the paper: the page in focus, or the newest page that isn't notes.
    /// `page` is the notes' own page when they were read from one; its card becomes the notes card.
    /// Returns a line for the voice bar.
    @discardableResult
    func link(notes: String, from page: PageDocument? = nil) async -> String {
        guard let client = GeminiClient.fromAppKeys else { return GeminiClient.Failure.missingKey.localizedDescription }
        guard let paper = paper(besides: page) else { return "Hand Grasp the paper first, then your notes" }
        isLinking = true
        defer { isLinking = false }
        do {
            let linked = try await NoteLinker(client: client).link(notes: notes, paper: paper.text, title: paper.reading.title)
            let card = NotesCard(paperID: paper.id, paperTitle: paper.reading.title, linked: linked)
            let pageCard = page.flatMap { page in canvas.cards.first { canvas.document(for: $0)?.id == page.id }?.id }
            canvas.showNotes(card, replacing: pageCard)
            let differing = linked.notes.filter { $0.status == .differs }.count
            return "Linked \(linked.notes.count) notes; \(differing) differ from the paper"
        } catch {
            return "Couldn't link the notes: \(error.localizedDescription)"
        }
    }

    /// Links the newest page of notes, or asks for notes to be typed, for voice: "these are my notes".
    func linkLatestNotes() async -> String {
        let pages = canvas.documents.values.sorted { $0.readAt > $1.readAt }
        if let notes = pages.first(where: Self.isNotes) {
            return await link(notes: notes.text.joined(separator: "\n"), from: notes)
        }
        linkNotesByTyping()
        return "Type or paste your notes"
    }

    /// Notes typed or pasted in.
    func linkNotesByTyping() {
        let alert = NSAlert()
        alert.messageText = "Your notes on the paper"
        alert.informativeText = "One note per line. Grasp finds where each one is in the paper and checks it."
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 420, height: 180)
        let field = scroll.documentView as? NSTextView
        field?.font = .systemFont(ofSize: 13)
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Check My Notes")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let notes = (field?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return }
        Task { await link(notes: notes) }
    }

    /// The paper the notes are about: the page in focus if it isn't notes, or the newest page that isn't.
    private func paper(besides notes: PageDocument?) -> PageDocument? {
        if let focused = canvas.focusedDocument, focused.id != notes?.id, !Self.isNotes(focused) { return focused }
        let onCanvas = canvas.cards.compactMap { canvas.document(for: $0) }
        return onCanvas.filter { $0.id != notes?.id && !Self.isNotes($0) }.max { $0.readAt < $1.readAt }
    }

    /// A paper, study or report: worth looking for a model in.
    static func isPaper(_ document: PageDocument) -> Bool {
        let words = (document.reading.kind + " " + document.reading.title).lowercased()
        return ["paper", "study", "article", "journal", "research", "experiment", "report"].contains { words.contains($0) }
    }

    private static func isNotes(_ document: PageDocument) -> Bool {
        let words = (document.reading.kind + " " + document.reading.title).lowercased()
        return words.contains("note")
    }
}
