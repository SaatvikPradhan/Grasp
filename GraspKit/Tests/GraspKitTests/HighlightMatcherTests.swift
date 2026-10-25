import Foundation
import Testing
@testable import GraspKit

struct HighlightMatcherTests {
    /// Lines as Vision reads the demo contract.
    let lines = [
        "RETAIL INSTALLMENT SALE CONTRACT",
        "8.90 %",
        "$6,356.16",
        "$21,600.00",
        "Your payment schedule will be: 72 monthly payments of $388.28, beginning December 1, 2026.",
        "Cash price of vehicle $19,900.00",
        "Paint and fabric protection $895.00",
        "Sales tax, title and registration $1,306.00",
        "Amount financed $21,600.00",
        "Total sale price $1,895.00",
    ]

    let reading = OfferReading(
        documentType: .loanContract, cashPrice: 19_900,
        fees: [
            .init(name: "Documentary fee", amount: 499, isAddon: false),
            .init(name: "Paint and fabric protection", amount: 895, isAddon: true),
        ],
        downPayment: 1_000, amountFinanced: 21_600, aprPercent: 8.9, termMonths: 72, monthlyPayment: 388.28
    )

    func found(_ kind: LinkHighlight.Kind) -> [String] {
        HighlightMatcher.matches(in: lines, for: reading)
            .filter { $0.kind == kind }
            .map { String(lines[$0.line][$0.range]) }
    }

    @Test func findsEveryTerm() {
        let terms = found(.term)
        #expect(terms.filter { $0 == "21,600.00" }.count == 2)
        #expect(terms.contains("8.90"))
        #expect(terms.contains("72 monthly"))
        #expect(terms.contains("388.28"))
    }

    @Test func findsAddOnsInRed() {
        let addons = found(.addon)
        #expect(addons.contains("Paint and fabric protection"))
        #expect(addons.contains("895.00"))
    }

    @Test func ignoresNumbersInsideLongerNumbers() {
        // "$1,895.00" contains "895.00" but is not the add-on.
        let matches = HighlightMatcher.matches(in: lines, for: reading).filter { $0.line == 9 }
        #expect(matches.isEmpty)
    }

    @Test func doesNotHighlightRequiredFees() {
        #expect(!found(.addon).contains("Documentary fee"))
    }

    @Test func moneyForms() {
        #expect(Set(HighlightMatcher.money(21_600)) == ["21,600.00", "21600.00", "21,600", "21600"])
        #expect(Set(HighlightMatcher.money(388.28)) == ["388.28"])
    }
}
