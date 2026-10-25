import Foundation
import Testing
@testable import GraspKit

struct ProtocolRunTests {
    static let lab = LabProtocol(title: "Lid test", steps: [
        .init(number: 1, instruction: "Set up the cups", cited: Cited(quote: "", location: nil), check: .sayDone),
        .init(number: 2, instruction: "Pour into A", cited: Cited(quote: "", location: nil), check: .rises(.a), actions: [.pour(.a)]),
        .init(number: 3, instruction: "Pour into B, lid on", cited: Cited(quote: "", location: nil), check: .rises(.b), actions: [.pour(.b), .lid(.b)]),
        .init(number: 4, instruction: "Wait until A is below 85", cited: Cited(quote: "", location: nil), check: .below(.a, 85)),
        .init(number: 5, instruction: "Ice into A", cited: Cited(quote: "", location: nil), check: .drops(.a)),
        .init(number: 6, instruction: "Wait 2 minutes", cited: Cited(quote: "", location: nil), check: .wait(120)),
    ])

    let room: [Cup: Double] = [.a: 21.5, .b: 21.5, .c: 21.5]

    @Test func followsTheProbesThroughTheSteps() {
        var run = ProtocolRun(Self.lab, at: 0, celsius: room)
        #expect(run.update(room, at: 1) == nil)
        #expect(run.sayDone(at: 4, celsius: room)?.how == .said)
        #expect(run.update(room, at: 5) == nil)
        let poured = run.update([.a: 88, .b: 21.5, .c: 21.5], at: 9)
        #expect(poured?.how == .probe("probe A rose from 21.5 to 88.0 °C"))
        #expect(run.update([.a: 87.8, .b: 88, .c: 21.5], at: 15)?.step == 2)
        #expect(run.update([.a: 85.4, .b: 87.9, .c: 21.5], at: 60) == nil)
        #expect(run.waiting([.a: 85.4, .b: 87.9, .c: 21.5], at: 60).text == "Cup A at 85.4 °C, waiting for 85.0")
        #expect(run.update([.a: 84.9, .b: 87.8, .c: 21.5], at: 80)?.how == .probe("probe A read 84.9 °C, below 85.0"))
        #expect(run.update([.a: 66.9, .b: 87.7, .c: 21.5], at: 90)?.step == 4)
        #expect(run.update([.a: 66, .b: 87, .c: 21.5], at: 150) == nil)
        #expect(run.update([.a: 65, .b: 86, .c: 21.5], at: 211)?.how == .timer)
        #expect(run.isFinished)
        #expect(run.deviations.isEmpty)
    }

    @Test func notesAStepDoneEarlyAndOneSaidDoneWithoutTheProbe() {
        var run = ProtocolRun(Self.lab, at: 0, celsius: room)
        _ = run.sayDone(at: 2, celsius: room)
        // B is poured while step 2 (pour into A) is still open.
        #expect(run.update([.a: 21.5, .b: 88, .c: 21.5], at: 6) == nil)
        #expect(run.deviations.first?.text == "Step 3 happened early: probe B rose from 21.5 to 88.0 °C while step 2 was still open")
        // Saying done on the pour into A without the probe seeing it.
        _ = run.sayDone(at: 10, celsius: [.a: 21.5, .b: 87.9, .c: 21.5])
        #expect(run.deviations.last?.text == "Step 2: you said done, but probe A didn't see it")
        // Step 3 already happened: it finishes at once, timed when it happened.
        let early = run.update([.a: 21.5, .b: 87.8, .c: 21.5], at: 11)
        #expect(early?.step == 2 && early?.finished == 6)
    }

    @Test func aWaitCutShortIsNoted() {
        var run = ProtocolRun(LabProtocol(title: "", steps: [Self.lab.steps[5]]), at: 0, celsius: room)
        #expect(run.waiting(room, at: 30).text == "1:30 left")
        _ = run.sayDone(at: 45, celsius: room)
        #expect(run.deviations.first?.text == "Step 6: the 2:00 wait ended after 0:45")
    }
}

struct LiveProtocolReaderTests {
    @Test(.enabled(if: TestDocumentTests.key != nil)) func readsTheSampleProtocol() async throws {
        let lines = try TestDocumentTests.lines(Data(contentsOf: TestDocumentTests.photo("protocol")))
        let started = Date()
        let lab = try #require(try await ProtocolReader(client: GeminiClient(apiKey: TestDocumentTests.key!)).read(page: lines, title: "Protocol"))
        print("PROTOCOL \(String(format: "%.1f", Date().timeIntervalSince(started))) s: \(lab.title)")
        for step in lab.steps { print("  \(step.number). \(step.instruction) · \(step.check) · \(step.actions) · found \(step.cited.location != nil)") }
        #expect(lab.steps.count == 8)
        #expect(lab.steps.map(\.check) == [.sayDone, .rises(.a), .rises(.b), .rises(.c), .below(.c, 85), .drops(.c), .wait(120), .sayDone])
        #expect(lab.steps[2].actions.contains(.lid(.b)))
        let found = lab.steps.allSatisfy { $0.cited.location != nil }
        #expect(found)
    }
}
