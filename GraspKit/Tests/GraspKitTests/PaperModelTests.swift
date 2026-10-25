import Foundation
import Testing
@testable import GraspKit

struct PaperModelTests {
    func number(_ value: Double) -> PaperModel.Number {
        PaperModel.Number(value: value, cited: Cited(quote: "", location: nil))
    }

    func cooling(_ rows: [(String, Double, Double)]) -> PaperModel {
        PaperModel(kind: .newtonCooling, equation: Cited(quote: "", location: nil), timeUnit: "min",
                   start: number(90), room: number(21), conditions: rows.map { name, k, minutes in
            PaperModel.Condition(name: name, k: number(k), spread: 0.002,
                                 reported: [.init(kind: .timeTo, at: 60, value: number(minutes))])
        })
    }

    @Test func reproducesTheTableAndCatchesThePlantedRow() {
        let model = cooling([("Paper, no lid", 0.031, 18.4), ("Paper, lid", 0.019, 30.0), ("Ceramic, lid", 0.017, 25.9)])
        #expect(model.checks.map(\.matches) == [true, true, false])
        let planted = model.mismatches[0]
        #expect(planted.condition == "Ceramic, lid")
        #expect(abs(planted.expected - 33.56) < 0.01)
    }

    @Test func runsTheCurve() {
        let model = cooling([("Paper, no lid", 0.031, 18.4)])
        #expect(abs(model.value(after: 0, k: 0.031) - 90) < 1e-9)
        #expect(abs(model.value(after: 18.405, k: 0.031) - 60) < 0.01)
        #expect(model.time(to: 15, k: 0.031) == nil)
    }

    @Test func fitsARateFromReadings() {
        // A cup poured at 0:10, then cooling with k = 0.031 per minute in a 21 °C room.
        var readings = (0..<10).map { Reading(cup: .a, celsius: 21.5, time: Double($0)) }
        readings += (10...190).map { second in
            let minutes = Double(second - 10) / 60
            return Reading(cup: .a, celsius: 21 + 67 * exp(-0.031 * minutes) + (second % 2 == 0 ? 0.02 : -0.02), time: Double(second))
        }
        let fit = FittedRate.cooling(readings, room: 21)
        #expect(fit != nil)
        #expect(abs((fit?.k ?? 0) - 0.031) < 0.002)
        #expect(fit?.isConsistent(with: 0.031, spread: 0.002) == true)
        #expect(fit?.isConsistent(with: 0.019, spread: 0.002) == false)
    }
}

struct LiveModelReaderTests {
    @Test(.enabled(if: TestDocumentTests.key != nil)) func readsThePapersModel() async throws {
        let lines = try TestDocumentTests.lines(Data(contentsOf: TestDocumentTests.photo("research-paper")))
        let started = Date()
        let model = try #require(try await ModelReader(client: GeminiClient(apiKey: TestDocumentTests.key!)).read(paper: lines))
        print("MODEL \(String(format: "%.1f", Date().timeIntervalSince(started))) s: \(model.kind) start \(model.start.value) room \(model.room?.value ?? -1) eq: \(model.equation.quote)")
        for check in model.checks {
            print("  \(check.condition): \(check.reported.kind.rawValue) \(check.reported.at) printed \(check.reported.value.value) expected \(String(format: "%.1f", check.expected)) \(check.matches ? "ok" : "MISMATCH")")
        }
        #expect(model.kind == .newtonCooling)
        #expect(model.conditions.count == 6)
        #expect(model.mismatches.map(\.condition) == ["Ceramic, lid"])
    }
}
