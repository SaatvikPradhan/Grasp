import Foundation
import Testing
@testable import GraspKit

struct MethodCheckTests {
    let lines = [
        "Each condition was repeated in 12 trials, in random order.",
        "The room was kept at 21 °C, within 1 °C, and the water was not stirred.",
    ]

    @Test func boxesNeedTheirWordsAndTrialsTheirNumber() {
        let raw = MethodReader.Raw(
            question: .init(name: "Do lids slow cooling?", detail: nil, quote: "a quote that isn't there"),
            varied: [], measured: [],
            controlled: [.init(name: "Room temperature", detail: "21 °C", quote: "The room was kept at 21 °C")],
            notControlled: [.init(name: "Humidity", detail: "changes evaporation", quote: nil)],
            analysis: nil,
            trials: .init(name: "20 trials per condition", detail: nil, quote: "Each condition was repeated in 12 trials"))
        let map = MethodReader.checked(raw, lines: lines)
        #expect(map.question == nil)
        #expect(map.controlled.first?.cited?.location?.line == 1)
        #expect(map.notControlled.first?.cited == nil)
        #expect(map.trials == nil)   // 20 isn't printed
    }
}

struct LiveMethodReaderTests {
    @Test(.enabled(if: TestDocumentTests.key != nil)) func mapsThePapersMethod() async throws {
        let lines = try TestDocumentTests.lines(Data(contentsOf: TestDocumentTests.photo("research-paper")))
        let started = Date()
        let map = try await MethodReader(client: GeminiClient(apiKey: TestDocumentTests.key!)).read(paper: lines)
        print("METHOD \(String(format: "%.1f", Date().timeIntervalSince(started))) s · \(map.question?.name ?? "-")")
        for (label, items) in [("varied", map.varied), ("measured", map.measured), ("controlled", map.controlled), ("not controlled", map.notControlled)] {
            print("  \(label): " + items.map { "\($0.name) [\($0.detail ?? "")]\($0.cited == nil ? " (not in paper)" : "")" }.joined(separator: "; "))
        }
        print("  analysis: \(map.analysis?.name ?? "-") · trials: \(map.trials?.name ?? "-")")
        #expect(map.varied.count >= 2)
        #expect(map.measured.count >= 1)
        #expect(map.controlled.count >= 1)
        #expect(map.notControlled.count >= 2)
        #expect(map.trials?.name.contains("12") == true)
        let evaporation = map.notControlled.contains { $0.name.lowercased().contains("evapor") }
        #expect(evaporation)
    }
}
