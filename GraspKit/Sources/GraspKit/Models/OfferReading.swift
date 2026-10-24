import Foundation

/// What Gemini read off a car contract, window sticker or loan quote. Only what is printed;
/// every number we show is computed from these in Swift.
public struct OfferReading: Codable, Sendable, Equatable {
    public enum DocumentType: String, Codable, Sendable {
        case loanContract = "loan_contract"
        case windowSticker = "window_sticker"
        case loanQuote = "loan_quote"
        case other
    }

    public struct Fee: Codable, Sendable, Equatable {
        public var name: String
        public var amount: Double
        /// An optional dealer extra (protection package, nitrogen tires, etching), as opposed
        /// to tax, title and required fees.
        public var isAddon: Bool

        public init(name: String, amount: Double, isAddon: Bool) {
            self.name = name
            self.amount = amount
            self.isAddon = isAddon
        }
    }

    public var documentType: DocumentType
    public var cashPrice: Double?
    public var fees: [Fee]
    public var downPayment: Double?
    public var amountFinanced: Double?
    /// As printed: 8.9 for 8.9%.
    public var aprPercent: Double?
    public var termMonths: Int?
    public var monthlyPayment: Double?

    public init(documentType: DocumentType, cashPrice: Double? = nil, fees: [Fee] = [], downPayment: Double? = nil,
                amountFinanced: Double? = nil, aprPercent: Double? = nil, termMonths: Int? = nil, monthlyPayment: Double? = nil) {
        self.documentType = documentType
        self.cashPrice = cashPrice
        self.fees = fees
        self.downPayment = downPayment
        self.amountFinanced = amountFinanced
        self.aprPercent = aprPercent
        self.termMonths = termMonths
        self.monthlyPayment = monthlyPayment
    }

    /// The loan, when the paper states enough to model one.
    public var loan: LoanTerms? {
        guard let amountFinanced, let aprPercent, let termMonths, termMonths > 0 else { return nil }
        return LoanTerms(principal: amountFinanced, apr: aprPercent / 100, termMonths: termMonths)
    }

    public var addOns: [Fee] { fees.filter(\.isAddon) }

    public var addOnTotal: Double { addOns.reduce(0) { $0 + $1.amount } }

    /// Places where the paper disagrees with its own numbers.
    public var discrepancies: [String] {
        var found: [String] = []
        if let loan, let monthlyPayment, abs(loan.monthlyPayment - monthlyPayment) > 1 {
            found.append("The printed payment of \(dollars(monthlyPayment)) doesn't match \(dollars(loan.monthlyPayment)) for this rate and term.")
        }
        if let cashPrice, let amountFinanced {
            let itemized = cashPrice + fees.reduce(0) { $0 + $1.amount } - (downPayment ?? 0)
            if abs(itemized - amountFinanced) > 1 {
                found.append("The items add up to \(dollars(itemized)), but the amount financed is \(dollars(amountFinanced)).")
            }
        }
        return found
    }

    private func dollars(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }
}
