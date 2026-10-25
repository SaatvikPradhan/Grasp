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
        case .temperatures, .scan, .advice, .pitch:
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
        case .temperatures, .scan, .advice, .pitch:
            return false
        }
        return true
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
