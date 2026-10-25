import Foundation
import Testing
@testable import GraspKit

struct DeepDiveTests {
    let grounded = Grounded(
        text: """
        - Late fees on phone bills are set by the carrier's terms and are typically $5 to $10.
        - If your payment arrived by the due date, the carrier should reverse a late fee on request.
        - Some advice with no source behind it at all.
        Bottom line: Ask for the $7 fee back, since you paid on time.
        """,
        searches: ["phone bill late fee paid on time"],
        pages: [.init(title: "fcc.gov", url: "https://example.com/a"), .init(title: "consumerfinance.gov", url: "https://example.com/b")],
        supports: [
            .init(text: "Late fees on phone bills are set by the carrier's terms and are typically $5 to $10.", pages: [1]),
            .init(text: "the carrier should reverse a late fee on request", pages: [0, 1]),
        ]
    )

    @Test func keepsOnlyFindingsWithAPageBehindThem() {
        let dive = DeepDiveFinder.checked(grounded)
        #expect(dive.findings.count == 2)
        #expect(dive.findings.allSatisfy { !$0.sources.isEmpty })
        #expect(dive.bottomLine == "Ask for the $7 fee back, since you paid on time.")
        #expect(dive.searches == ["phone bill late fee paid on time"])
    }

    @Test func numbersSourcesInTheOrderTheyAreFirstCited() {
        let dive = DeepDiveFinder.checked(grounded)
        #expect(dive.sources.map(\.site) == ["consumerfinance.gov", "fcc.gov"])
        #expect(dive.findings[0].sources == [0])
        #expect(dive.findings[1].sources == [1, 0])
    }

    @Test func givesEachSiteOneNumber() {
        let dive = DeepDiveFinder.checked(Grounded(
            text: "- First finding from one government page.\n- Second finding from another page on the same site.",
            pages: [.init(title: "fcc.gov", url: "https://example.com/a"), .init(title: "fcc.gov", url: "https://example.com/b")],
            supports: [.init(text: "First finding from one government page.", pages: [0]),
                       .init(text: "Second finding from another page on the same site.", pages: [1])]))
        #expect(dive.sources.map(\.site) == ["fcc.gov"])
        #expect(dive.findings.map(\.sources) == [[0], [0]])
    }

    @Test func keepsEverythingUnsourcedWhenNothingIsGrounded() {
        let dive = DeepDiveFinder.checked(Grounded(text: "- One finding long enough to keep.\n- Another finding long enough."))
        #expect(dive.findings.count == 2)
        #expect(dive.sources.isEmpty)
    }

    @Test func promptCarriesTheWordsOnThePage() {
        let prompt = DeepDiveFinder.prompt(DeepDiveSubject(topic: "Late payment fee: $7.00", quote: "Late payment fee $7.00",
                                                           source: "Northway Mobile Statement (phone bill)"))
        #expect(prompt.contains("Late payment fee $7.00"))
        #expect(prompt.contains("Northway Mobile Statement"))
    }
}

struct LiveDeepDiveTests {
    @Test(.enabled(if: TestDocumentTests.key != nil)) func divesIntoALateFee() async throws {
        let started = Date()
        let dive = try await DeepDiveFinder(client: GeminiClient(apiKey: TestDocumentTests.key!)).dive(DeepDiveSubject(
            topic: "Late payment fee: $7.00", quote: "Late payment fee $7.00",
            source: "Northway Mobile Statement (phone bill)",
            context: "A $7.00 late fee was charged, but the payment was received before the due date."))
        print("DIVE \(String(format: "%.1f", Date().timeIntervalSince(started))) s, searched \(dive.searches)")
        for finding in dive.findings { print("  - \(finding.text) \(finding.sources.map { "[\($0 + 1)]" }.joined())") }
        print("  bottom line: \(dive.bottomLine ?? "-")")
        for (index, source) in dive.sources.enumerated() { print("  [\(index + 1)] \(source.site)") }
        #expect(dive.findings.count >= 2)
        #expect(!dive.sources.isEmpty)
    }
}
