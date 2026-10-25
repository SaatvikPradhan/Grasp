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
        /// The number as printed, when the catch is about one number: finds it on the page.
        public var printed: String?

        public var id: String { title }

        public init(title: String, explanation: String, quote: String, severity: Severity, cost: Double? = nil, printed: String? = nil) {
            self.title = title
            self.explanation = explanation
            self.quote = quote
            self.severity = severity
            self.cost = cost
            self.printed = printed
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
    /// Printed numbers that should follow from other printed numbers (a total, hours × rate, a
    /// percentage). Gemini says which numbers go together; Swift does the arithmetic.
    public var relations: [Relation]?
    /// Every line of text on the page, read separately by Vision after Gemini. A number counts as
    /// printed if it's one of the facts or on one of these lines.
    public var lines: [String]?

    /// A printed result and the printed numbers it should come from.
    public struct Relation: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable {
            case sum, product
            /// inputs are [percent, base]: 6.2% of 425.25.
            case percentOf = "percent_of"
        }

        /// One printed number, with the line it's on.
        public struct Input: Codable, Sendable, Equatable {
            public var label: String
            public var value: Double

            public init(label: String, value: Double) {
                self.label = label
                self.value = value
            }
        }

        public var label: String
        public var kind: Kind
        public var stated: Double
        public var inputs: [Input]

        public var values: [Double] { inputs.map(\.value) }

        public init(label: String, kind: Kind, stated: Double, inputs: [Input]) {
            self.label = label
            self.kind = kind
            self.stated = stated
            self.inputs = inputs
        }
    }

    public init(kind: String, title: String, summary: String, facts: [Fact], catches: [Catch], model: ModelHint,
                relations: [Relation]? = nil) {
        self.kind = kind
        self.title = title
        self.summary = summary
        self.facts = facts
        self.catches = catches
        self.model = model
        self.relations = relations
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
        PrintedNumber.contains(number, in: text)
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

/// A page's itemized total, added up again in Swift.
public struct Breakdown: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var label: String
        public var value: Double
        /// The words on the page it's printed with, when found.
        public var quote: String?
    }

    /// The total's name on the page: "Total new charges".
    public var label: String
    public var lines: [Line]
    /// The total as printed.
    public var printed: Double

    /// Swift's sum of the lines, to the cent.
    public var total: Double { (lines.map(\.value).reduce(0, +) * 100).rounded() / 100 }
    public var matchesPage: Bool { abs(total - printed) < 0.011 || (printed == printed.rounded() && abs(total - printed) < 0.51) }
}

/// The model a page's numbers support, worked out in Swift.
public enum PageModel: Equatable, Sendable {
    case loan(LoanTerms)
    case recurring(RecurringCost)
    case breakdown(Breakdown)
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
                // A late fee on this month's bill isn't a monthly cost.
                extraMonthly: (model.extraMonthly ?? []).filter { !isPenalty($0) }.compactMap { checked($0) }.reduce(0, +),
                upfront: (model.upfront ?? []).filter { !isPenalty($0) }.compactMap { checked($0).map(abs) }.reduce(0, +)
            ))
        case .breakdown:
            return mainBreakdown.map(PageModel.breakdown) ?? .none
        case .none:
            return .none
        }
    }
}

// MARK: - Does it add up?

extension PageReading {
    /// The page's main itemized total: the sum with the most lines, every one of them on the page.
    /// (Adding up every dollar figure would mix in subtotals, net pay and balances.)
    public var mainBreakdown: Breakdown? {
        let sums = (relations ?? []).filter { $0.kind == .sum && $0.inputs.count >= 2 && spot(of: $0.stated) != nil }
        for relation in sums.sorted(by: { $0.inputs.count > $1.inputs.count }) {
            let values = relation.inputs.compactMap(printedValue)
            guard values.count == relation.inputs.count else { continue }
            let lines = zip(relation.inputs, values).map { input, value in
                Breakdown.Line(label: input.label, value: value, quote: spot(of: value)?.quote)
            }
            return Breakdown(label: relation.label, lines: lines, printed: relation.stated)
        }
        return nil
    }
}

extension PageReading {
    /// A printed result that doesn't match the printed numbers it comes from.
    public struct Mismatch: Equatable, Sendable {
        public var relation: Relation
        /// What the numbers actually give.
        public var expected: Double
        /// Printed minus expected: positive means the page says too much.
        public var difference: Double { relation.stated - expected }
    }

    /// Every relation that doesn't hold, worked out in Swift. Only numbers that are really on
    /// the page take part, so a misread can't invent a mistake.
    public var mismatches: [Mismatch] {
        let outcomes = (relations ?? []).map { (relation: $0, outcome: check($0)) }
        // The same total can be listed twice (two looks at the page). If any listing of it adds
        // up, trust that one: a missed mistake is better than a false alarm.
        func holds(_ relation: Relation) -> Bool {
            outcomes.contains { item in
                if case .holds = item.outcome { return item.relation.kind == relation.kind && abs(item.relation.stated - relation.stated) < 0.006 }
                return false
            }
        }
        var seen: Set<String> = []
        return outcomes.compactMap { item in
            guard case .wrong(let mismatch) = item.outcome, !holds(item.relation),
                  seen.insert("\(item.relation.kind.rawValue) \(String(format: "%.2f", item.relation.stated))").inserted else { return nil }
            return mismatch
        }
    }

    private enum Outcome {
        case holds, wrong(Mismatch)
        /// A number isn't on the page, so Swift can't say.
        case unchecked
    }

    private func check(_ relation: Relation) -> Outcome {
        let values = relation.inputs.compactMap(printedValue)
        guard spot(of: relation.stated) != nil, values.count == relation.inputs.count else { return .unchecked }
        let expected: Double
        switch relation.kind {
        case .sum:
            guard values.count >= 2 else { return .unchecked }
            expected = values.reduce(0, +)
        case .product:
            guard values.count == 2 else { return .unchecked }
            expected = values[0] * values[1]
        case .percentOf:
            guard values.count == 2 else { return .unchecked }
            expected = values[0] / 100 * values[1]
        }
        // Printed amounts are rounded to the cent (or to the dollar on some pages).
        let rounded = (expected * 100).rounded() / 100
        var tolerance = relation.stated == relation.stated.rounded() && abs(relation.stated) >= 100 ? 0.51 : 0.011
        // 36 payments of a rounded $25 can come to $899.99.
        if relation.kind == .product { tolerance += 0.005 * min(abs(values[0]), abs(values[1])) }
        guard abs(rounded - relation.stated) > tolerance else { return .holds }
        var checked = relation
        for index in checked.inputs.indices { checked.inputs[index].value = values[index] }
        return .wrong(Mismatch(relation: checked, expected: rounded))
    }

    /// The catches, with anything that doesn't add up first.
    public var allCatches: [Catch] {
        let found = mismatches.map { mismatch in
            let stated = spot(of: mismatch.relation.stated)
            let direction = mismatch.difference > 0 ? "too high" : "too low"
            return Catch(
                title: "Doesn't add up: \(mismatch.relation.label)",
                explanation: "The page says \(Self.money(mismatch.relation.stated)), but the numbers give \(Self.money(mismatch.expected)): \(Self.money(abs(mismatch.difference))) \(direction).",
                quote: stated?.quote ?? Self.money(mismatch.relation.stated),
                severity: .high,
                cost: abs(mismatch.difference),
                printed: stated?.printed
            )
        }
        // The reader may have noticed the same number; Swift's version has the math.
        let quotes = Set(found.map(\.quote))
        return found + catches.filter { !quotes.contains($0.quote) }
    }

    /// An input's number as printed: Gemini's number if it's on the page, or else the number on the
    /// line its label names. (Asked for a total that's wrong, a model will sometimes quietly "fix" an
    /// input so it adds up: 1,200 × 12 for a $1,150 rent.)
    func printedValue(of input: Relation.Input) -> Double? {
        if spot(of: input.value) != nil { return input.value }
        let label = input.label.lowercased().trimmingCharacters(in: .whitespaces)
        guard label.count >= 4 else { return nil }
        let named = facts.filter { $0.value != nil && $0.label.lowercased() == label }
        let quoted = facts.filter { $0.value != nil && $0.quote.lowercased().contains(label) }
        guard let fact = named.count == 1 ? named[0] : quoted.count == 1 ? quoted[0] : nil, let value = fact.value else { return nil }
        return input.value < 0 ? -abs(value) : abs(value)
    }

    /// Where a number is printed: the fact it was read as, or else the line of the page it's on.
    func spot(of number: Double) -> (quote: String, printed: String?)? {
        if let fact = source(of: number) { return (fact.quote, fact.asPrinted) }
        let lines = lines ?? []
        return PrintedNumber.line(of: number, in: lines).map { (lines[$0], nil) }
    }

    private static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }
}
