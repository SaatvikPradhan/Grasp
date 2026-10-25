import Foundation

/// Something the salesperson said, checked against the paper.
public struct PitchCheck: Equatable, Sendable, Identifiable {
    public enum Verdict: Equatable, Sendable {
        /// Matches the paper.
        case holds
        /// True, or close, but misleading, or simply not what the paper says.
        case `catch`
        /// A pressure line ("this price ends today").
        case pressure
    }

    /// The words as heard, for example "$388 a month".
    public var heard: String
    public var verdict: Verdict
    /// What the paper says about it, in one sentence.
    public var note: String

    public var id: String { heard.lowercased() }
}

/// Listens for numbers and pressure in what the salesperson says, and checks each against
/// the dealer's offer. Plain pattern matching on the transcript: fast, offline, and it never
/// makes up a number.
public enum PitchChecker {
    public static func checks(in transcript: String, against offer: LoanTerms) -> [PitchCheck] {
        let text = transcript.lowercased()
        var found: [PitchCheck] = []

        // "$388 a month", "388 dollars per month", "388 bucks a month", "$388/mo"
        for match in text.matches(of: #/\$?\s?(\d{2,4}(?:\.\d{1,2})?)(?:\s*(?:dollars|bucks))?\s*(?:a|per|each|every|/)\s*mo(?:nth)?\b/#) {
            guard let amount = Double(match.output.1) else { continue }
            found.append(checkMonthly(amount, heard: "\(money(amount, cents: amount != amount.rounded())) a month", offer: offer))
        }

        // "8.9%", "8.9 percent", "six point four percent" arrives as digits from the recognizer
        for match in text.matches(of: #/(\d{1,2}(?:\.\d{1,2})?)\s*(?:%|percent)/#) {
            guard let rate = Double(match.output.1), rate > 0, rate < 40 else { continue }
            let onPaper = offer.apr * 100
            let heard = "\(rate.formatted())%"
            found.append(abs(rate - onPaper) < 0.05
                ? PitchCheck(heard: heard, verdict: .holds, note: "That matches the contract.")
                : PitchCheck(heard: heard, verdict: .catch, note: "The contract says \(onPaper.formatted(.number.precision(.fractionLength(1))))%."))
        }

        // "72 months", "six years"
        var terms: [Int] = text.matches(of: #/\b(\d{2})\s*months?\b/#).compactMap { Int($0.output.1) }
        let years = ["two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7]
        terms += text.matches(of: #/\b(\w+)\s*years?\b/#).compactMap { years[String($0.output.1)].map { $0 * 12 } }
        for months in terms where months >= 12 && months <= 96 {
            let heard = "\(months) months"
            found.append(months == offer.termMonths
                ? PitchCheck(heard: heard, verdict: .holds, note: "That matches the contract: \(money(offer.totalPaid)) in total.")
                : PitchCheck(heard: heard, verdict: .catch, note: "The contract says \(offer.termMonths) months."))
        }

        for phrase in pressurePhrases where text.contains(phrase) {
            found.append(PitchCheck(heard: "\"\(phrase)\"", verdict: .pressure,
                                    note: "That's a pressure line. A good offer is still good tomorrow; take your time."))
        }

        // Once each, in the order heard.
        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }
    }

    static let pressurePhrases = [
        "only today", "today only", "ends today", "end of the day", "won't last", "wont last",
        "someone else is looking", "another buyer", "sign today", "price goes up", "limited time",
        "last one", "manager won't", "manager wont",
    ]

    /// A monthly figure is checked by finding the term that produces it at the paper's rate.
    private static func checkMonthly(_ amount: Double, heard: String, offer: LoanTerms) -> PitchCheck {
        let term = stride(from: 12, through: 96, by: 6).first { months in
            abs(offer.with(termMonths: months).monthlyPayment - amount) <= 2
        }
        guard let term else {
            return PitchCheck(heard: heard, verdict: .catch,
                              note: "That doesn't match the paper: \(money(offer.monthlyPayment, cents: true)) a month for \(offer.termMonths) months.")
        }
        let atTerm = offer.with(termMonths: term)
        let shorter = offer.with(termMonths: 48)
        guard term > 48 else {
            return PitchCheck(heard: heard, verdict: .holds, note: "That's the payment for \(term) months, \(money(atTerm.totalPaid)) in total.")
        }
        return PitchCheck(heard: heard, verdict: .catch,
                          note: "That only works over \(term) months: \(money(atTerm.totalPaid)) in total, \(money(atTerm.totalInterest)) of it interest. At 48 months it's \(money(shorter.monthlyPayment)) a month.")
    }

    private static func money(_ value: Double, cents: Bool = false) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(cents ? 2 : 0)))
    }
}
