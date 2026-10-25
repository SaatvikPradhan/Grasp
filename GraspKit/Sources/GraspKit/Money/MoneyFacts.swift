import Foundation

/// Everything Grasp knows about a car deal, with the numbers worked out in Swift.
/// "What to say" and the decision summary are built from this, never from the AI's arithmetic.
public struct MoneyFacts: Equatable, Sendable {
    /// An optional extra to refuse, and where it was seen.
    public struct AddOn: Equatable, Sendable {
        public var name: String
        public var amount: Double
        public var onContract: Bool
        public var onSticker: Bool
    }

    /// The dealer's offer as written.
    public var pitch: LoanTerms
    /// The dealer's loan at the term on screen (after twisting).
    public var chosen: LoanTerms
    /// Another lender's offer at the same term, once it's been pushed in.
    public var quote: LoanTerms?
    /// The contract as read: cash price, fees, down payment.
    public var contract: OfferReading?
    /// Window stickers as read.
    public var stickers: [OfferReading]
    /// What the salesperson said, checked against the paper.
    public var pitchChecks: [PitchCheck]

    public init(pitch: LoanTerms, chosen: LoanTerms, quote: LoanTerms? = nil, contract: OfferReading? = nil,
                stickers: [OfferReading] = [], pitchChecks: [PitchCheck] = []) {
        self.pitch = pitch
        self.chosen = chosen
        self.quote = quote
        self.contract = contract
        self.stickers = stickers
        self.pitchChecks = pitchChecks
    }

    // MARK: Derived

    /// Optional extras from the contract and the stickers, each once, biggest first.
    public var addOns: [AddOn] {
        var merged: [String: AddOn] = [:]
        var order: [String] = []
        func add(_ fee: OfferReading.Fee, contract: Bool) {
            let key = Self.key(fee.name)
            if var existing = merged[key] {
                existing.onContract = existing.onContract || contract
                existing.onSticker = existing.onSticker || !contract
                merged[key] = existing
            } else {
                merged[key] = AddOn(name: fee.name, amount: fee.amount, onContract: contract, onSticker: !contract)
                order.append(key)
            }
        }
        contract?.addOns.forEach { add($0, contract: true) }
        stickers.flatMap(\.addOns).forEach { add($0, contract: false) }
        return order.compactMap { merged[$0] }.sorted { $0.amount > $1.amount }
    }

    public var addOnTotal: Double { addOns.reduce(0) { $0 + $1.amount } }

    /// Fees that aren't optional but can be argued down, such as the documentary fee.
    public var negotiableFees: [OfferReading.Fee] {
        (contract?.fees ?? []).filter { !$0.isAddon && $0.name.lowercased().contains("doc") }
    }

    /// The price before the down payment: cash price plus every fee on the contract.
    public var outTheDoor: Double? {
        guard let contract, let cash = contract.cashPrice else { return nil }
        return cash + contract.fees.reduce(0) { $0 + $1.amount }
    }

    /// From the totals as shown (whole dollars), so the numbers on screen add up.
    public var savedByTerm: Double { pitch.totalPaid.rounded() - chosen.totalPaid.rounded() }
    public var savedByQuote: Double? { quote.map { pitch.totalPaid.rounded() - $0.totalPaid.rounded() } }
    public var quoteVersusDealer: Double? { quote.map { chosen.totalPaid.rounded() - $0.totalPaid.rounded() } }

    // MARK: What to say

    /// Up to four things to say to the dealer, most valuable first. Plain sentences built from
    /// the numbers above, so they're right even when the AI isn't available.
    public func talkingPoints() -> [String] {
        var points: [String] = []
        if let quote, let saved = savedByQuote, saved > 0 {
            points.append("My credit union approved me at \(percent(quote.apr)). Can you match it? That's \(money(saved)) less than your offer.")
        }
        if chosen.termMonths < pitch.termMonths, savedByTerm > 0 {
            points.append("I'd like \(chosen.termMonths) months instead of \(pitch.termMonths): \(money(chosen.monthlyPayment)) a month, and \(money(savedByTerm)) less in total.")
        }
        if !addOns.isEmpty {
            points.append("Please take off the \(list(addOns.map { $0.name.lowercased() })). That's \(money(addOnTotal)) I didn't ask for.")
        }
        if let check = pitchChecks.first(where: { $0.verdict == .catch }) {
            points.append("You said \(check.heard), but \(check.note.prefix(1).lowercased() + check.note.dropFirst())")
        }
        if let outTheDoor {
            points.append("What's the out-the-door price? The contract adds up to \(money(outTheDoor)) before my down payment.")
        }
        if let fee = negotiableFees.first {
            points.append("Can you lower the \(fee.name.lowercased()) of \(money(fee.amount))?")
        }
        return Array(points.prefix(4))
    }

    /// The facts as lines of text, for the AI to phrase from.
    public var factSheet: String {
        var lines = [
            "Dealer's offer: \(money(pitch.principal)) financed at \(percent(pitch.apr)) for \(pitch.termMonths) months, \(money(pitch.monthlyPayment)) a month, \(money(pitch.totalPaid)) in total.",
        ]
        if chosen.termMonths != pitch.termMonths {
            lines.append("At \(chosen.termMonths) months instead: \(money(chosen.monthlyPayment)) a month, \(money(chosen.totalPaid)) in total, saving \(money(savedByTerm)).")
        }
        if let quote, let saved = savedByQuote, let versusDealer = quoteVersusDealer {
            lines.append("Credit union quote: \(percent(quote.apr)) for \(quote.termMonths) months, \(money(quote.monthlyPayment)) a month, \(money(quote.totalPaid)) in total, \(money(saved)) less than the dealer's offer and \(money(versusDealer)) less than the dealer at the same term.")
        }
        for addOn in addOns {
            lines.append("Optional add-on: \(addOn.name), \(money(addOn.amount)).")
        }
        for fee in negotiableFees {
            lines.append("Negotiable fee: \(fee.name), \(money(fee.amount)).")
        }
        if let outTheDoor {
            lines.append("Out-the-door price before the down payment: \(money(outTheDoor)).")
        }
        for check in pitchChecks {
            lines.append("The salesperson said \"\(check.heard)\": \(check.note)")
        }
        return lines.joined(separator: "\n")
    }

    /// Every number the facts contain, as digits, so AI wording can be checked against them.
    public var knownNumbers: Set<String> {
        Set(Self.numbers(in: factSheet + "\n" + talkingPoints().joined(separator: "\n")))
    }

    /// The digits of every number in `text`: "$2,204" and "2204" are both "2204".
    public static func numbers(in text: String) -> [String] {
        let pattern = #/\d[\d,]*(?:\.\d+)?/#
        return text.matches(of: pattern).map { match in
            var digits = String(match.output).replacingOccurrences(of: ",", with: "")
            if digits.contains(".") {
                while digits.hasSuffix("0") { digits.removeLast() }
                if digits.hasSuffix(".") { digits.removeLast() }
            }
            return digits
        }
    }

    // MARK: Formatting

    private static func key(_ name: String) -> String {
        let skip: Set<String> = ["and", "the", "a", "of", "dealer", "added", "filled"]
        let words = name.lowercased().split { !$0.isLetter }.map(String.init).filter { !skip.contains($0) }
        return words.first ?? name.lowercased()
    }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    private func percent(_ apr: Double) -> String {
        (apr * 100).formatted(.number.precision(.fractionLength(1))) + "%"
    }

    private func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }
}
