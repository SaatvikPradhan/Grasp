import Foundation
import Testing
@testable import GraspKit

struct CameraStepTests {
    let room: [Cup: Double] = [.a: 21.5, .b: 21.5, .c: 21.5]

    @Test func cameraFinishesAStepTheProbesCantCheck() {
        var run = ProtocolRun(ProtocolRunTests.lab, at: 0, celsius: room)
        let done = run.cameraSaw("three cups on the mat with probes in", stepDone: true, differs: nil, at: 6, celsius: room)
        #expect(done?.how == .camera("three cups on the mat with probes in"))
        #expect(run.current == 1)
        #expect(ProtocolRecord(run).steps[0].how == "camera saw: three cups on the mat with probes in")
    }

    @Test func probeStepsWaitForTheirProbe() {
        var run = ProtocolRun(ProtocolRunTests.lab, at: 0, celsius: room)
        _ = run.sayDone(at: 3, celsius: room)
        // Step 2 is a pour into A: only probe A finishes it, whatever the camera thinks.
        #expect(run.cameraSaw("pouring into cup A", stepDone: true, differs: nil, at: 8, celsius: room) == nil)
        #expect(run.current == 1)
    }

    @Test func aCupWithNoProbeFinishesByCameraOrWord() {
        // The two-cup bench: probes in A and B only. Step 5 drops ice into A in the test protocol;
        // here A has no probe, so the camera (or "done") moves it on, with nothing noted.
        let twoCups: [Cup: Double] = [.b: 21.5, .c: 21.5]
        var run = ProtocolRun(LabProtocol(title: "", steps: [ProtocolRunTests.lab.steps[4], ProtocolRunTests.lab.steps[0]]),
                              at: 0, celsius: twoCups)
        #expect(run.waiting(twoCups, at: 1).text.hasPrefix("No probe in cup A"))
        #expect(run.update(twoCups, at: 2) == nil)
        #expect(run.cameraSaw("ice in cup A", stepDone: true, differs: nil, at: 5, celsius: twoCups)?.how == .camera("ice in cup A"))
        #expect(run.sayDone(at: 9, celsius: twoCups)?.how == .said)
        #expect(run.deviations.isEmpty)
    }

    @Test func somethingDoneDifferentlyIsNotedOnce() {
        var run = ProtocolRun(ProtocolRunTests.lab, at: 0, celsius: room)
        _ = run.cameraSaw("pouring", stepDone: false, differs: "the lid is on cup A, not B", at: 5, celsius: room)
        _ = run.cameraSaw("pouring", stepDone: false, differs: "the lid is on cup A, not B", at: 9, celsius: room)
        #expect(run.deviations.map(\.text) == ["Step 1: the camera saw the lid is on cup A, not B"])
    }
}

struct LiveBenchWatcherTests {
    static let bench = TestDocumentTests.photo("bench-ice-in-c")
    let ice = LabProtocol.Step(number: 6, instruction: "Drop two ice cubes into cup C", cited: Cited(quote: "", location: nil), check: .sayDone)
    let lidOnA = LabProtocol.Step(number: 3, instruction: "Put the lid on cup A", cited: Cited(quote: "", location: nil), check: .sayDone)

    @Test(.enabled(if: TestDocumentTests.key != nil)) func seesTheIceInCupC() async throws {
        let look = try await BenchWatcher(client: GeminiClient(apiKey: TestDocumentTests.key!))
            .look(at: try Data(contentsOf: Self.bench), step: ice, next: nil)
        print("BENCH ice: \(look)")
        #expect(look.stepDone)
    }

    @Test(.enabled(if: TestDocumentTests.key != nil)) func doesNotSeeALidOnCupA() async throws {
        let look = try await BenchWatcher(client: GeminiClient(apiKey: TestDocumentTests.key!))
            .look(at: try Data(contentsOf: Self.bench), step: lidOnA, next: nil)
        print("BENCH lid on A: \(look)")
        #expect(!look.stepDone)
    }
}
