import AppKit
import GraspKit

/// A loan as a card shows it, measured against the salesperson's pitch.
struct LoanCard: Equatable {
    enum Role: Equatable {
        /// The dealer's financing, from the contract.
        case dealer
        /// Another lender's offer, such as a credit union pre-approval.
        case quote
    }

    static let termRange = 24...84
    static let termStep = 12

    var role: Role
    var loan: LoanTerms
    /// The dealer's offer as pitched. Every option is compared with this.
    var pitch: LoanTerms
    /// Where the numbers came from, shown under the chart.
    var source: String
    /// The paper it was read from (fees, cash price), when there is one.
    var reading: OfferReading?
    /// The page in `CanvasModel.documents` this came from, for showing where each number is.
    var documentID: UUID?

    var title: String {
        switch role {
        case .dealer: "Dealer financing"
        case .quote: "Credit union quote"
        }
    }

    /// Positive when this option costs less in total than the pitch. Taken from the totals
    /// as shown (whole dollars), so the numbers on screen add up: $27,956 − $25,752 = $2,204.
    var savedVersusPitch: Double { pitch.totalPaid.rounded() - loan.totalPaid.rounded() }

    static let demo = LoanCard(role: .dealer, loan: .demoContract, pitch: .demoContract, source: "Demo numbers", reading: .demoContract)
}

/// Two loans pushed together, sharing one term so they compare like for like.
struct Comparison: Equatable {
    var dealer: LoanCard
    var other: LoanCard

    var termMonths: Int { dealer.loan.termMonths }
}

/// Any page Grasp has read: the photo, what Gemini found on it, and where on the photo each
/// fact and catch is, so every number can show where it came from.
struct PageDocument: Equatable, Identifiable {
    let id: UUID
    var image: NSImage
    var reading: PageReading
    /// Where each fact (by key) is on the photo: normalized, origin at the top left.
    var factBoxes: [String: CGRect]
    /// Where each catch (by title) is on the photo.
    var catchBoxes: [String: CGRect]
    /// Every line of text on the page, for answering questions about it…
    var text: [String]
    /// …and where each line is on the photo (normalized, top left), for pointing at answers.
    var lineBoxes: [CGRect]
    /// The phone capture it came from, so the phone can show it again.
    var captureID: UUID?
    var readAt: Date
    /// The dial for its model: months to count.
    var months: Int?

    var model: PageModel {
        switch reading.resolvedModel {
        case .loan(let loan): .loan(months.map { loan.with(termMonths: $0) } ?? loan)
        case .recurring(let cost): .recurring(months.map { cost.with(months: $0) } ?? cost)
        case let other: other
        }
    }

    /// Facts worth showing as chips: everything except what the model line already says.
    var shownFacts: [PageReading.Fact] { Array(reading.facts.prefix(8)) }
    var shownCatches: [PageReading.Catch] { Array(reading.allCatches.prefix(4)) }
}

/// A question and Grasp's answer, with the words on the pages that back it.
struct AnswerCard: Equatable {
    struct Source: Equatable, Identifiable {
        var documentID: UUID
        var documentTitle: String
        var quote: String
        /// Where the words are on the photo, when Vision found them.
        var box: CGRect?
        var id: String { quote }
    }

    var question: String
    var answer: GroundedAnswer
    var sources: [Source]
    /// The question this one follows on from, if it does.
    var followsOn: String?
}

/// Someone's notes on a paper, each tied to the passage it's about, and where the research could go.
struct NotesCard: Equatable {
    /// The paper's document.
    var paperID: UUID
    var paperTitle: String
    var linked: LinkedNotes
}

/// The model a paper describes, running: each condition's curve, the paper's own results checked
/// against its equation, and, once pushed into the cup chart, your cups against its prediction.
struct ModelCard: Equatable {
    var paperID: UUID
    var paperTitle: String
    var model: PaperModel
    /// The condition the dial turns and the card draws boldest.
    var selected = 0
    /// k as twisted, per time unit; nil while it's the paper's.
    var twistedK: Double?
    /// Showing the cups on the bench against the paper.
    var comparesCups = false

    var condition: PaperModel.Condition { model.conditions[min(selected, model.conditions.count - 1)] }
    var k: Double { twistedK ?? condition.k.value }
}

/// A lab session written up, with the frames it was written from.
struct NotebookCard: Equatable {
    var notebook: LabNotebook
    var frames: [LabRecording.Frame]
    /// The scripted session with simulated probes, not a real one.
    var isRehearsal: Bool
    var date: Date

    static func == (lhs: NotebookCard, rhs: NotebookCard) -> Bool {
        lhs.notebook == rhs.notebook && lhs.date == rhs.date
    }

    /// The frame nearest a moment, within a few seconds.
    func frame(at seconds: Double) -> NSImage? {
        frames.filter { abs($0.seconds - seconds) <= 6 }
            .min { abs($0.seconds - seconds) < abs($1.seconds - seconds) }
            .flatMap { NSImage(data: $0.jpeg) }
    }
}

/// A photo from the phone (or a dropped file), shown while Gemini reads it.
struct Scan: Equatable {
    enum Status: Equatable {
        case reading
        /// Read, but not something that becomes a loan chart (a window sticker, say).
        case read(OfferReading)
        case failed(String)
    }

    var image: NSImage
    var status: Status
}

/// The value a twist turns.
struct Dial: Equatable {
    var value: Int
    var range: ClosedRange<Int>
    var step: Int
    var unit: String

    /// How to show the value when it isn't a plain count, such as "k 0.019 per min".
    var display: String?

    var fraction: Double { Double(value - range.lowerBound) / Double(range.upperBound - range.lowerBound) }
    var label: String { display ?? "\(value) \(unit)" }

    func clamped(_ proposed: Int) -> Int {
        min(max(proposed, range.lowerBound), range.upperBound)
    }
}

/// Anything on the canvas a hand can grab.
struct Card: Identifiable, Equatable {
    enum Kind: Equatable {
        case loan(LoanCard)
        case comparison(Comparison)
        case temperatures
        case scan(Scan)
        /// What to say to the dealer.
        case advice(Advice)
        /// What the salesperson said, checked against the paper.
        case pitch([PitchCheck])
        /// Any other page: what it is, its numbers with their sources, its catches, its model.
        case document(PageDocument)
        /// A question answered from the pages, with its sources.
        case answer(AnswerCard)
        /// Notes on a paper, linked to its passages.
        case notes(NotesCard)
        /// A lab session written up.
        case notebook(NotebookCard)
        /// A paper's model, running.
        case model(ModelCard)
    }

    /// Swipe flips a card between its two ways of drawing the same numbers (bars and lines).
    enum Style: Equatable {
        case primary, alternate

        mutating func toggle() {
            self = self == .primary ? .alternate : .primary
        }
    }

    let id: UUID
    var center: CGPoint
    var kind: Kind
    var style = Style.primary
    /// True while flying in from the phone, for a slower, bouncier spring.
    var isArriving = false
    /// A page out of focus, shrunk to a chip: its title and what's wrong with it.
    var isFolded = false

    static let chipSize = CGSize(width: 260, height: 66)

    init(id: UUID = UUID(), center: CGPoint, kind: Kind) {
        self.id = id
        self.center = center
        self.kind = kind
    }

    var size: CGSize {
        if isFolded { return Self.chipSize }
        return switch kind {
        case .loan: CGSize(width: 460, height: 310)
        case .comparison: CGSize(width: 540, height: 340)
        case .temperatures: CGSize(width: 420, height: 290)
        case .scan(let scan): CGSize(width: 300, height: Self.photoHeight(scan.image) + Self.scanFooter(scan.status))
        case .advice(let advice): CGSize(width: 500, height: 96 + Double(advice.lines.count) * 58)
        case .pitch(let checks): CGSize(width: 460, height: 70 + Double(min(checks.count, 3)) * 74)
        case .document(let document): CGSize(width: Self.documentWidth, height: Self.documentHeight(document))
        case .answer(let answer): CGSize(width: Self.answerWidth, height: Self.answerHeight(answer))
        case .notes(let notes): CGSize(width: Self.notesWidth, height: Self.notesHeight(notes))
        case .notebook(let notebook): CGSize(width: Self.notebookWidth, height: Self.notebookHeight(notebook))
        case .model(let model): CGSize(width: 600, height: model.comparesCups ? 470 : 500)
        }
    }

    var frame: CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    var loanCard: LoanCard? {
        if case .loan(let card) = kind { return card }
        return nil
    }

    var dial: Dial? {
        guard !isFolded else { return nil }
        return switch kind {
        case .loan(let card):
            Dial(value: card.loan.termMonths, range: LoanCard.termRange, step: LoanCard.termStep, unit: "mo")
        case .comparison(let comparison):
            Dial(value: comparison.termMonths, range: LoanCard.termRange, step: LoanCard.termStep, unit: "mo")
        case .document(let document):
            switch document.model {
            case .loan(let loan):
                Dial(value: loan.termMonths, range: 12...max(120, loan.termMonths * 2), step: 12, unit: "mo")
            case .recurring(let cost):
                Dial(value: cost.months, range: 6...60, step: 6, unit: "mo")
            case .breakdown, .none:
                nil
            }
        case .model(let card):
            // k in thousandths: 0.019 per minute is 19.
            Dial(value: Int((card.k * 1000).rounded()), range: 1...100, step: 1, unit: "",
                 display: String(format: "k %.3f per %@", card.k, card.model.timeUnit))
        case .temperatures, .scan, .advice, .pitch, .answer, .notes, .notebook:
            nil
        }
    }

    /// Sets the dial, clamped to its range. Returns false when nothing changed.
    @discardableResult
    mutating func setDial(_ proposed: Int) -> Bool {
        guard let dial else { return false }
        let value = dial.clamped(proposed)
        guard value != dial.value else { return false }
        switch kind {
        case .loan(var card):
            card.loan.termMonths = value
            kind = .loan(card)
        case .comparison(var comparison):
            comparison.dealer.loan.termMonths = value
            comparison.other.loan.termMonths = value
            kind = .comparison(comparison)
        case .document(var document):
            document.months = value
            kind = .document(document)
        case .model(var card):
            card.twistedK = Double(value) / 1000
            kind = .model(card)
        case .temperatures, .scan, .advice, .pitch, .answer, .notes, .notebook:
            return false
        }
        return true
    }

    // MARK: Answer layout

    /// Narrow enough that chips, the page in focus and an answer fit side by side at 1280 points.
    static let answerWidth = 440.0
    static let documentWidth = 480.0

    static func answerHeight(_ card: AnswerCard) -> Double {
        let answerLines = ceil(Double(card.answer.answer.count) / 42)
        return 40 + 46 + (card.followsOn == nil ? 0 : 16) + answerLines * 23 + 30
            + (card.sources.isEmpty ? 0 : 22 + Double(card.sources.count) * 40)
            + (card.answer.calculations.isEmpty ? 0 : 20 + Double(card.answer.calculations.count) * 18)
    }

    // MARK: Notes layout

    static let notesWidth = 520.0

    static func notesHeight(_ card: NotesCard) -> Double {
        let notes = card.linked.notes.reduce(0.0) { total, note in total + (note.paperSays == nil ? 30 : 48) }
        let directions = card.linked.directions.isEmpty ? 0 : 28 + Double(card.linked.directions.count) * 46
        return 40 + 62 + notes + directions + 8
    }

    // MARK: Notebook layout

    /// Steps on the left, what they show and what to try next on the right.
    static let notebookWidth = 820.0
    static let notebookStepsWidth = 470.0

    static func notebookHeight(_ card: NotebookCard) -> Double {
        let notebook = card.notebook
        let steps = 22 + notebook.steps.reduce(0.0) { total, step in total + (step.said == nil ? 24 : 38) }
        let observations = notebook.observations.isEmpty ? 0 : 24 + Double(notebook.observations.count) * 56
        let next = notebook.next.isEmpty ? 0 : 24 + Double(notebook.next.count) * 38
        return 40 + 66 + 10 + max(steps, observations + next) + 10 + 22
    }

    // MARK: Document layout

    static func documentHeight(_ document: PageDocument) -> Double {
        var height = 40.0 + 64       // padding, header and summary
        switch document.model {
        case .loan, .recurring: height += 118
        case .breakdown: height += 30
        case .none: break
        }
        height += Double((document.shownFacts.count + 1) / 2) * 24 + 26
        if !document.shownCatches.isEmpty {
            height += 22 + Double(document.shownCatches.count) * 44
        }
        return height + 22
    }

    // MARK: Scan layout

    static let scanWidth = 300.0

    static func photoHeight(_ image: NSImage) -> Double {
        let aspect = image.size.width > 0 ? image.size.height / image.size.width : 1.3
        return min((scanWidth - 32) * aspect, 300)
    }

    static func scanFooter(_ status: Scan.Status) -> Double {
        if case .read(let reading) = status, !reading.addOns.isEmpty {
            return 92 + Double(reading.addOns.count) * 18
        }
        return 88
    }
}
