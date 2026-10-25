import Foundation
import Testing
@testable import GraspKit

struct RelatedWorkCheckTests {
    let work = Work(id: "W1", title: "Thermal behavior of a ceramic cup", year: 2020, citations: 1, doi: nil, firstAuthor: "Pitta Krishna Reddy", abstract: "")

    @Test func abstractsComeBackInOrder() {
        #expect(OpenAlexClient.abstract(["cools": [1], "coffee": [0], "slowly": [2]]) == "coffee cools slowly")
        #expect(work.shortName == "Reddy 2020")
    }

    @Test func onlyReturnedPapersSurviveAndStudiedNeedsOne() {
        let judged = RelatedWorkFinder.Judged(
            related: [.init(id: "W1", why: "Same cups."), .init(id: "W999", why: "Made up.")],
            directions: [.init(title: "Measure evaporation", verdict: "studied", ids: ["W999"], note: "Someone did."),
                         .init(title: "Double-walled cups", verdict: "partly", ids: ["W1"], note: "Reddy modelled cup walls.")])
        let directions = [RelatedWorkFinder.Planned(title: "Measure evaporation", why: "", cited: nil, query: ""),
                          RelatedWorkFinder.Planned(title: "Double-walled cups", why: "", cited: nil, query: "")]
        let result = RelatedWorkFinder.checked(judged, candidates: ["W1": work], directions: directions)
        #expect(result.related.map(\.work.id) == ["W1"])
        #expect(result.directions.map(\.verdict) == [.open, .partly])
        #expect(result.directions[1].evidence.map(\.id) == ["W1"])
    }
}

struct LiveRelatedWorkTests {
    @Test(.enabled(if: TestDocumentTests.key != nil)) func findsRealPapersAndChecksTheDirections() async throws {
        let lines = try TestDocumentTests.lines(Data(contentsOf: TestDocumentTests.photo("research-paper")))
        let started = Date()
        let result = try await RelatedWorkFinder(client: GeminiClient(apiKey: TestDocumentTests.key!))
            .find(paper: lines, title: "Lids, Sleeves and the Cooling of Hot Drinks")
        print("RELATED \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        for found in result.related { print("  \(found.work.shortName) · \(found.work.citations) cites · \(found.work.title.prefix(70)) — \(found.why)") }
        for direction in result.directions {
            print("  → \(direction.title): \(direction.verdict.rawValue) \(direction.evidence.map(\.shortName)) — \(direction.note)")
        }
        #expect(!result.related.isEmpty)
        #expect(result.directions.count >= 2)
        let grounded = result.directions.allSatisfy { $0.cited != nil }
        #expect(grounded)
    }
}
