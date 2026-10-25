import Foundation

/// What Gemini read off any page: what it is, the numbers that matter, the catches in the fine
/// print, and which model fits. Every fact and catch keeps the exact words it came from, so
/// Grasp can show where each number is on the page.
public struct PageReading: Codable, Sendable, Equatable {
    public struct Fact: Codable, Sendable, Equatable, Identifiable {
        public enum Unit: String, Codable, Sendable {
            case dollars, percent, months, years, days, count, number, date, text
        }

        /// A short snake_case name the model refers to, such as "apr".
        public var key: String
        public var label: String
        /// As printed on the page: "8.90 %", "$85.00".
        public var asPrinted: String
        public var value: Double?
        public var unit: Unit
        /// Words copied from the page that contain it, for finding it on the photo.
        public var quote: String

        public var id: String { key }

        public init(key: String, label: String, asPrinted: String, value: Double?, unit: Unit, quote: String) {
            self.key = key
            self.label = label
            self.asPrinted = asPrinted
            self.value = value
            self.unit = unit
            self.quote = quote
        }
    }

    /// Something in the fine print that could cost the reader or lock them in.
    public struct Catch: Codable, Sendable, Equatable, Identifiable {
        public enum Severity: String, Codable, Sendable {
            case high, medium, low
        }

        public var title: String
        /// One plain sentence.
        public var explanation: String
        public var quote: String
        public var severity: Severity
        /// Dollars at stake, when the page says.
        public var cost: Double?

        public var id: String { title }

        public init(title: String, explanation: String, quote: String, severity: Severity, cost: Double? = nil) {
            self.title = title
            self.explanation = explanation
            self.quote = quote
            self.severity = severity
            self.cost = cost
        }
    }

    /// Which model fits, with its inputs copied from the facts. Swift checks each input is
    /// really on the page, then does the math.
    public struct ModelHint: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable {
            case installmentLoan = "installment_loan"
            case recurringCost = "recurring_cost"
            case breakdown
            case none
        }

        public var type: Kind
        public var principal: Double?
        public var aprPercent: Double?
        /// Loan length or contract length, in months.
        public var months: Double?
        /// The regular monthly price.
        public var monthlyPrice: Double?
        public var promoPrice: Double?
        public var promoMonths: Double?
        /// Other monthly lines, such as a device payment (negative for a discount).
        public var extraMonthly: [Double]?
        /// One-time charges.
        public var upfront: [Double]?

        public init(type: Kind, principal: Double? = nil, aprPercent: Double? = nil, months: Double? = nil,
                    monthlyPrice: Double? = nil, promoPrice: Double? = nil, promoMonths: Double? = nil,
                    extraMonthly: [Double]? = nil, upfront: [Double]? = nil) {
            self.type = type
            self.principal = principal
            self.aprPercent = aprPercent
            self.months = months
            self.monthlyPrice = monthlyPrice
            self.promoPrice = promoPrice
            self.promoMonths = promoMonths
            self.extraMonthly = extraMonthly
            self.upfront = upfront
        }
    }

    /// What kind of page, in a few words: "phone plan agreement".
    public var kind: String
    public var title: String
    /// One plain sentence.
    public var summary: String
    public var facts: [Fact]
    public var catches: [Catch]
    public var model: ModelHint

    public init(kind: String, title: String, summary: String, facts: [Fact], catches: [Catch], model: ModelHint) {
        self.kind = kind
        self.title = title
        self.summary = summary
        self.facts = facts
        self.catches = catches
        self.model = model
    }

    public func fact(_ key: String?) -> Fact? {
        guard let key else { return nil }
        return facts.first { $0.key == key }
    }

    /// The fact a number was copied from, if it really is on the page. Months may come from a
    /// count of years, and a discount may be printed with or without its minus sign.
    public func source(of number: Double?) -> Fact? {
        guard let number else { return nil }
        return facts.first { fact in
            guard let value = fact.value else { return false }
            return abs(abs(value) - abs(number)) < 0.006 || (fact.unit == .years && abs(value * 12 - number) < 0.006)
        } ?? facts.first { fact in
            // Or written into a fact's words: "months 1 to 12" holds the 12.
            [fact.asPrinted, fact.quote, fact.label].contains { Self.contains(Self.plain(number), in: $0) }
        }
    }

    private static func contains(_ number: String, in text: String) -> Bool {
        var start = text.startIndex
        while let range = text.range(of: number, range: start..<text.endIndex) {
            let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : " "
            let after = range.upperBound < text.endIndex ? text[range.upperBound] : " "
            if !before.isNumber, before != ".", !after.isNumber { return true }
            start = range.upperBound
        }
        return false
    }

    /// A late fee or penalty only applies if something goes wrong, so it isn't a charge up front.
    func isPenalty(_ number: Double) -> Bool {
        guard let fact = source(of: number) else { return false }
        let words = (fact.key + " " + fact.label).lowercased()
        return ["late", "penalt", "termination", "returned", "overdraft"].contains { words.contains($0) }
    }

    /// Every length of time on the page, in months, for when the model leaves one out.
    var lengths: [Double] {
        facts.compactMap { fact in
            guard let value = fact.value, value > 0 else { return nil }
            switch fact.unit {
            case .months: return value
            case .years: return value * 12
            default: return nil
            }
        }
    }

    /// Keeps a number only if it's on the page.
    func checked(_ number: Double?) -> Double? {
        source(of: number) == nil ? nil : number
    }

    private static func plain(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(format: "%.2f", number)
    }
}

/// A monthly price over time: a phone plan, a lease, a subscription.
public struct RecurringCost: Equatable, Sendable {
    /// The regular monthly price.
    public var monthly: Double
    /// How many months to count: the dial.
    public var months: Int
    /// A cheaper price for the first months, if there is one.
    public var promoMonthly: Double?
    public var promoMonths: Int
    /// Other monthly lines added on top, such as a device payment, less any discount.
    public var extraMonthly: Double
    /// One-time charges.
    public var upfront: Double

    public init(monthly: Double, months: Int, promoMonthly: Double? = nil, promoMonths: Int = 0,
                extraMonthly: Double = 0, upfront: Double = 0) {
        self.monthly = monthly
        self.months = months
        self.promoMonthly = promoMonthly
        self.promoMonths = promoMonths
        self.extraMonthly = extraMonthly
        self.upfront = upfront
    }

    /// Months actually at the promo price, within the count.
    public var promoMonthsCounted: Int { promoMonthly == nil ? 0 : min(promoMonths, months) }

    public var total: Double {
        Double(promoMonthsCounted) * (promoMonthly ?? 0)
            + Double(months - promoMonthsCounted) * monthly
            + Double(months) * extraMonthly
            + upfront
    }

    /// The monthly bill once any promotion has ended.
    public var regularBill: Double { monthly + extraMonthly }

    public func with(months: Int) -> RecurringCost {
        var copy = self
        copy.months = months
        return copy
    }
}

/// The model a page's numbers support, worked out in Swift.
public enum PageModel: Equatable, Sendable {
    case loan(LoanTerms)
    case recurring(RecurringCost)
    case breakdown([PageReading.Fact])
    case none
}

extension PageReading {
    /// The model, built only from numbers that are really on the page; `.none` when they aren't there.
    public var resolvedModel: PageModel {
        switch model.type {
        case .installmentLoan:
            guard let principal = checked(model.principal), principal > 0,
                  let months = checked(model.months) ?? lengths.first, months > 0 else { return .none }
            let apr = checked(model.aprPercent) ?? 0
            return .loan(LoanTerms(principal: principal, apr: apr / 100, termMonths: Int(months.rounded())))
        case .recurringCost:
            guard let monthly = checked(model.monthlyPrice).map(abs), monthly > 0 else { return .none }
            let promoMonths = checked(model.promoMonths).map { Int($0.rounded()) } ?? 0
            return .recurring(RecurringCost(
                monthly: monthly,
                // The contract is the longest stretch on the page; a promotion is shorter.
                months: (checked(model.months) ?? lengths.max()).map { Int($0.rounded()) } ?? 12,
                promoMonthly: promoMonths > 0 ? checked(model.promoPrice).map(abs) : nil,
                promoMonths: promoMonths,
                extraMonthly: (model.extraMonthly ?? []).compactMap { checked($0) }.reduce(0, +),
                upfront: (model.upfront ?? []).filter { !isPenalty($0) }.compactMap { checked($0).map(abs) }.reduce(0, +)
            ))
        case .breakdown:
            let items = facts.filter { $0.unit == .dollars && $0.value != nil }
            return items.isEmpty ? .none : .breakdown(items)
        case .none:
            return .none
        }
    }
}
