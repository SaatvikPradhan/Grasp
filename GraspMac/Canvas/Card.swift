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
    var shownCatches: [PageReading.Catch] { Array(reading.catches.prefix(4)) }
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

    var fraction: Double { Double(value - range.lowerBound) / Double(range.upperBound - range.lowerBound) }
    var label: String { "\(value) \(unit)" }

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

    init(id: UUID = UUID(), center: CGPoint, kind: Kind) {
        self.id = id
        self.center = center
        self.kind = kind
    }

    var size: CGSize {
        switch kind {
        case .loan: CGSize(width: 460, height: 310)
        case .comparison: CGSize(width: 540, height: 340)
        case .temperatures: CGSize(width: 420, height: 290)
        case .scan(let scan): CGSize(width: 300, height: Self.photoHeight(scan.image) + Self.scanFooter(scan.status))
        case .advice(let advice): CGSize(width: 500, height: 96 + Double(advice.lines.count) * 58)
        case .pitch(let checks): CGSize(width: 460, height: 70 + Double(min(checks.count, 3)) * 74)
        case .document(let document): CGSize(width: 520, height: Self.documentHeight(document))
        case .answer(let answer): CGSize(width: 520, height: Self.answerHeight(answer))
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
        switch kind {
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
        case .temperatures, .scan, .advice, .pitch, .answer:
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
        case .temperatures, .scan, .advice, .pitch, .answer:
            return false
        }
        return true
    }

    // MARK: Answer layout

    static func answerHeight(_ card: AnswerCard) -> Double {
        let answerLines = ceil(Double(card.answer.answer.count) / 52)
        return 40 + 46 + answerLines * 23 + 30
            + (card.sources.isEmpty ? 0 : 22 + Double(card.sources.count) * 40)
            + (card.answer.calculations.isEmpty ? 0 : 20 + Double(card.answer.calculations.count) * 18)
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
