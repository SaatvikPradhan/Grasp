import Foundation
import Testing
@testable import GraspKit

struct SourceLocatorTests {
    /// Lines as Vision reads the phone plan.
    let lines = [
        "Unlimited Plus plan (months 1 to 12,",
        "promotional)",
        "$60.00",
        "Unlimited Plus plan (from month 13)",
        "$85.00",
        "Activation fee $35.00",
        "Total sale price $1,895.00",
        "Paint and fabric protection $895.00",
        "Early termination. If you cancel service or port your number before the device",
        "installment plan is paid off, the remaining device balance becomes due immediately",
    ]

    func text(_ location: SourceLocator.Location?) -> String? {
        location.map { String(lines[$0.line][$0.range]) }
    }

    @Test func findsThePrintedNumber() {
        let found = SourceLocator.locate(printed: "$35.00", quote: "Activation fee", in: lines)
        #expect(text(found) == "$35.00")
        #expect(found?.line == 5)
    }

    @Test func picksTheLineThatMatchesTheQuote() {
        // $895.00 is on line 7; line 6 has $1,895.00, which doesn't count.
        let found = SourceLocator.locate(printed: "$895.00", quote: "Paint and fabric protection", in: lines)
        #expect(found?.line == 7)
    }

    @Test func findsAQuoteByItsWords() {
        let found = SourceLocator.locate(printed: nil, quote: "Unlimited Plus plan (from month 13)", in: lines)
        #expect(found?.line == 3)
    }

    @Test func findsAQuoteThatWrapsOntoTheNextLine() {
        let found = SourceLocator.locate(
            printed: nil,
            quote: "before the device installment plan is paid off, the remaining device balance becomes due immediately",
            in: lines
        )
        #expect(found?.line == 8 || found?.line == 9)
    }

    @Test func returnsNothingForWordsThatArentThere() {
        #expect(SourceLocator.locate(printed: "$12.34", quote: "Mystery fee", in: lines) == nil)
    }
}
