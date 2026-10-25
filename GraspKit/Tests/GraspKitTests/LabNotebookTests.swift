import Foundation
import Testing
@testable import GraspKit

struct TranscriptBuilderTests {
    @Test func wordsKeepTheTimeTheyWereFirstHeardAndLinesBreakAtPauses() {
        var builder = TranscriptBuilder()
        builder.heard("Pouring the", at: 9)
        builder.heard("Pouring the hot water", at: 9.6)
        builder.heard("Pouring the hot water into cup A now", at: 10.2)
        builder.heard("Pouring the hot water into cup A now putting", at: 57)
        builder.heard("Pouring the hot water into cup A now putting the lid on B", at: 57.5)
        // The recognizer starts a new session.
        builder.heard("Whoa", at: 101)
        builder.heard("Whoa C dropped fast", at: 101.4)
        #expect(builder.lines() == [
            .init(seconds: 9, text: "Pouring the hot water into cup A now"),
            .init(seconds: 57, text: "putting the lid on B"),
            .init(seconds: 101, text: "Whoa C dropped fast"),
        ])
    }
}

struct SensorTraceTests {
    @Test func findsThePourTheLidAndTheIce() {
        let trace = SensorTrace(readings: LabRehearsal.recording().readings)
        let found = trace.events.map { "\($0.cup.rawValue) \($0.kind.rawValue) \(Int($0.seconds))" }
        #expect(trace.events.count == 3, "\(found)")
        let pour = trace.events.first { $0.cup == .a }
        #expect(pour?.kind == .rose && abs((pour?.seconds ?? 0) - 9) <= 2)
        let lid = trace.events.first { $0.cup == .b }
        #expect(lid?.kind == .slowed && abs((lid?.seconds ?? 0) - 58) <= 4)
        let ice = trace.events.first { $0.cup == .c }
        #expect(ice?.kind == .dropped && abs((ice?.seconds ?? 0) - 87) <= 2)
        #expect(abs((trace.celsius(.a, at: 20) ?? 0) - 86) < 1.5)
    }

    @Test func plainCoolingHasNoEvents() {
        let readings = (0...120).map { Reading(cup: .a, celsius: NewtonCooling.temperature(start: 85, ambient: 22, tau: 300, after: Double($0)), time: Double($0)) }
        #expect(SensorTrace(readings: readings).events.isEmpty)
    }
}

struct NotebookCheckTests {
    @Test func quotesMustBeSaidAndReadingsComeFromTheProbes() {
        let recording = LabRehearsal.recording()
        let raw = LabNotebookWriter.Raw(title: "Cooling", summary: "", steps: [
            .init(seconds: 57, did: "Put the lid on cup B", said: "Putting the lid on B", cup: "B"),
            .init(seconds: 88, did: "Added ice to cup C", said: "three ice cubes into C", cup: "c"),
        ], observations: [
            .init(text: "B cooled more slowly after the lid went on at 0:57.", seconds: [57]),
            .init(text: "C fell by 35 degrees.", seconds: [88]),
        ], next: [])
        let notebook = LabNotebookWriter.checked(raw, recording: recording, trace: SensorTrace(readings: recording.readings))
        #expect(notebook.steps[0].said == "Putting the lid on B")
        #expect(notebook.steps[0].event?.kind == .slowed)
        #expect(notebook.steps[0].celsius != nil)
        #expect(notebook.steps[1].said == nil)
        #expect(notebook.steps[1].cup == .c && notebook.steps[1].event?.kind == .dropped)
        #expect(notebook.observations.map(\.numbersChecked) == [true, false])
    }
}

struct NotebookExportTests {
    @Test func theExportHasMethodsATimelineAndTheData() {
        let recording = LabRehearsal.recording()
        let raw = LabNotebookWriter.Raw(title: "Lids and ice", summary: "Three cups.", steps: [
            .init(seconds: 57, did: "Put the lid on cup B", said: "Putting the lid on B", cup: "B"),
        ], observations: [.init(text: "B slowed after the lid.", seconds: [57])], next: ["Lid all three cups."])
        let notebook = LabNotebookWriter.checked(raw, recording: recording, trace: SensorTrace(readings: recording.readings))
        let markdown = notebook.markdown(date: Date(timeIntervalSince1970: 0), frames: 0, rehearsal: true)
        #expect(markdown.hasPrefix("# Lids and ice"))
        #expect(markdown.contains("## Methods"))
        #expect(markdown.contains("Recorded for 2:30 with temperature probes in cups A, B, C"))
        #expect(markdown.contains("| 0:57 | Put the lid on cup B | “Putting the lid on B” | B "))
        #expect(markdown.contains("cooling slowed"))
        let csv = LabNotebook.csv(recording.readings).split(separator: "\n")
        #expect(csv.first == "seconds,cup,celsius")
        #expect(csv.count == recording.readings.count + 1)
    }
}

struct LiveLabNotebookTests {
    @Test(.enabled(if: TestDocumentTests.key != nil)) func writesUpTheRehearsal() async throws {
        let started = Date()
        let notebook = try await LabNotebookWriter(client: GeminiClient(apiKey: TestDocumentTests.key!)).write(LabRehearsal.recording())
        print("NOTEBOOK \(String(format: "%.1f", Date().timeIntervalSince(started))) s: \(notebook.title)\n  \(notebook.summary)")
        for step in notebook.steps {
            print("  \(clockTime(step.seconds)) \(step.did) · said: \(step.said ?? "-") · \(step.cup?.rawValue ?? "-") \(step.celsius.map { String(format: "%.1f", $0) } ?? "") · \(step.event?.description ?? "")")
        }
        for observation in notebook.observations { print("  obs\(observation.numbersChecked ? "" : " (UNCHECKED)"): \(observation.text)") }
        for next in notebook.next { print("  next: \(next)") }
        let lid = notebook.steps.first { $0.cup == .b && $0.event?.kind == .slowed }
        #expect(lid != nil)
        let iced = notebook.steps.contains { $0.cup == .c && $0.event?.kind == .dropped }
        #expect(iced)
        #expect(notebook.steps.filter { $0.said != nil }.count >= 3)
        #expect(notebook.observations.count >= 2)
        let checked = notebook.observations.allSatisfy(\.numbersChecked)
        #expect(checked)
    }
}

struct NotebookEventTests {
    @Test func eachProbeEventGoesToItsNearestStepAndShowsWhereTheJumpEnded() {
        let recording = LabRehearsal.recording()
        let raw = LabNotebookWriter.Raw(title: "", summary: "", steps: [
            .init(seconds: 80, did: "Waited for C to cool", said: nil, cup: "C"),
            .init(seconds: 87, did: "Added ice to cup C", said: nil, cup: "C"),
            .init(seconds: 9, did: "Poured into A", said: nil, cup: "A"),
        ], observations: [], next: [])
        let notebook = LabNotebookWriter.checked(raw, recording: recording, trace: SensorTrace(readings: recording.readings))
        #expect(notebook.steps.map(\.did) == ["Poured into A", "Waited for C to cool", "Added ice to cup C"])
        #expect(notebook.steps[1].event == nil)
        #expect(notebook.steps[2].event?.kind == .dropped)
        #expect(abs((notebook.steps[0].celsius ?? 0) - 86.5) < 2)
    }
}
