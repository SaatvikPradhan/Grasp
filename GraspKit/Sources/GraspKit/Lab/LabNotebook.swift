import Foundation

/// A session written up: what was done, step by step, with what was said and what the probes
/// read at that moment; how the actions and the readings connect; and what to try next.
/// Gemini watches the frames and reads the transcript; every reading and quote comes from the
/// recording, checked in Swift.
public struct LabNotebook: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public var seconds: Double
        public var did: String
        /// Words someone said then, exactly as transcribed.
        public var said: String?
        public var cup: Cup?
        /// The cup's temperature at that moment, from the probe.
        public var celsius: Double?
        /// What the cup's probe did around then, if anything.
        public var event: SensorTrace.Event?
    }

    /// How something done connects to something a probe did.
    public struct Observation: Equatable, Sendable {
        public var text: String
        public var seconds: [Double]
        /// False when it uses a number that isn't in the readings, the transcript or the times.
        public var numbersChecked: Bool
    }

    public var title: String
    public var summary: String
    public var steps: [Step]
    public var observations: [Observation]
    public var next: [String]
    public var trace: SensorTrace
    public var duration: Double
    /// The protocol followed, step by step, when the run was guided.
    public var protocolRecord: ProtocolRecord?
}

public struct LabNotebookWriter: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
        self.client.thinkingLevel = "low"
    }

    /// At most this many frames go to Gemini, spread over the session.
    static let maxFrames = 16

    public func write(_ recording: LabRecording) async throws -> LabNotebook {
        let trace = SensorTrace(readings: recording.readings)
        let frames = Self.spread(recording.frames, count: Self.maxFrames)
        let raw = try await client.generate(
            Raw.self,
            prompt: Self.prompt(recording, trace: trace, hasFrames: !frames.isEmpty),
            images: frames.map { (caption: "Camera frame at \(clockTime($0.seconds)):", jpeg: $0.jpeg) },
            schema: Self.schema
        )
        return Self.checked(raw, recording: recording, trace: trace)
    }

    // MARK: Checking

    struct Raw: Decodable {
        struct Step: Decodable {
            var seconds: Double
            var did: String
            var said: String?
            var cup: String?
        }

        struct Observation: Decodable {
            var text: String
            var seconds: [Double]?
        }

        var title: String
        var summary: String
        var steps: [Step]
        var observations: [Observation]
        var next: [String]
    }

    static func checked(_ raw: Raw, recording: LabRecording, trace: SensorTrace) -> LabNotebook {
        let spoken = normalized(recording.speech.map(\.text).joined(separator: " "))
        var steps = raw.steps.map { item -> LabNotebook.Step in
            let seconds = min(max(item.seconds, 0), recording.duration)
            let cup = item.cup.flatMap { Cup(rawValue: $0.uppercased()) }
            // A quote must really be in the transcript, and long enough to mean something.
            let said = item.said.flatMap { said in
                let words = normalized(said)
                return words.split(separator: " ").count < 3 || !spoken.contains(words) ? nil : said
            }
            return LabNotebook.Step(seconds: seconds, did: item.did, said: said, cup: cup,
                                    celsius: cup.flatMap { trace.celsius($0, at: seconds) }, event: nil)
        }.sorted { $0.seconds < $1.seconds }
        // Each thing a probe did goes to the one step on that cup nearest to it (within 15 s), and
        // a step with a jump shows where the jump ended rather than a reading halfway through it.
        for event in trace.events {
            let candidates = steps.indices.filter { steps[$0].cup == event.cup && abs(steps[$0].seconds - event.seconds) <= 15 }
            guard let nearest = candidates.min(by: { abs(steps[$0].seconds - event.seconds) < abs(steps[$1].seconds - event.seconds) }),
                  steps[nearest].event == nil else { continue }
            steps[nearest].event = event
            if event.kind == .rose || event.kind == .dropped { steps[nearest].celsius = event.to }
        }

        let known = Set(MoneyFacts.numbers(in: trace.text + " " + recording.speech.map(\.text).joined(separator: " ")
            + " " + (recording.protocolRecord?.text ?? ""))
            + steps.flatMap { MoneyFacts.numbers(in: clockTime($0.seconds)) })
        let observations = raw.observations.prefix(4).map { item in
            LabNotebook.Observation(text: item.text, seconds: item.seconds ?? [],
                                    numbersChecked: Set(MoneyFacts.numbers(in: item.text)).isSubset(of: known))
        }
        return LabNotebook(title: raw.title, summary: raw.summary, steps: steps, observations: Array(observations),
                           next: Array(raw.next.prefix(3)), trace: trace, duration: recording.duration, protocolRecord: recording.protocolRecord)
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            .map(String.init).joined().split(separator: " ").joined(separator: " ")
    }

    /// Up to `count` frames, evenly spread.
    static func spread(_ frames: [LabRecording.Frame], count: Int) -> [LabRecording.Frame] {
        guard frames.count > count else { return frames }
        return (0..<count).map { frames[$0 * (frames.count - 1) / (count - 1)] }
    }

    // MARK: Prompt

    static func prompt(_ recording: LabRecording, trace: SensorTrace, hasFrames: Bool) -> String {
        let speech = recording.speech.isEmpty ? "Nobody spoke."
            : recording.speech.map { "\(clockTime($0.seconds)) \($0.text)" }.joined(separator: "\n")
        return """
        Keep the lab notebook for this \(clockTime(recording.duration)) session at a bench with three cups (A, B, C), \
        each with a temperature probe. \(hasFrames ? "You have camera frames, each labelled with its time, " : "There are no camera frames, so go by ")\
        what people said (timed) and what the probes did, worked out by Swift.
        title: a short name for the experiment.
        summary: two or three plain sentences: what was done and what the probes showed.
        steps: what people did, in order. seconds is when; did is one short sentence with no numbers; said is \
        words copied exactly from the transcript around then that are about that step (empty if nothing said was \
        about it: the transcript also catches the room); cup is the cup it was done to (A, B or C), or empty.
        observations: up to 4, each linking something done to something a probe did, such as a lid going on \
        and that cup's cooling slowing. text is one plain sentence using only numbers from the probe summary; \
        seconds lists the moments it refers to.
        next: up to 3 things to try next, one sentence each.

        What people said:
        \(speech)

        The probes (Swift):
        \(trace.text)
        \(recording.protocolRecord.map { "\nThe protocol they followed, as Grasp logged it (use these times for the steps):\n\($0.text)" } ?? "")
        """
    }

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "title": ["type": "STRING"],
            "summary": ["type": "STRING"],
            "steps": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "seconds": ["type": "NUMBER"],
                        "did": ["type": "STRING"],
                        "said": ["type": "STRING", "nullable": true],
                        "cup": ["type": "STRING", "nullable": true],
                    ],
                    "required": ["seconds", "did"],
                ],
            ],
            "observations": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "text": ["type": "STRING"],
                        "seconds": ["type": "ARRAY", "items": ["type": "NUMBER"]],
                    ],
                    "required": ["text"],
                ],
            ],
            "next": ["type": "ARRAY", "items": ["type": "STRING"]],
        ],
        "required": ["title", "summary", "steps", "observations", "next"],
    ]
}

// MARK: - Export

extension LabNotebook {
    /// The notebook as Markdown, with a Methods section written from what was recorded.
    public func markdown(date: Date, frames: Int, rehearsal: Bool) -> String {
        var lines = ["# \(title)", "", date.formatted(date: .long, time: .shortened) + (rehearsal ? " · rehearsal with simulated probes" : ""), "", summary, ""]
        lines += ["## Methods", ""]
        let probes = trace.cups.map(\.cup.rawValue).joined(separator: ", ")
        lines.append((protocolRecord.map { "Followed the protocol \u{201C}\($0.title)\u{201D}, guided step by step. " } ?? "")
            + "Recorded for \(clockTime(duration)) with temperature probes in cups \(probes.isEmpty ? "none" : probes), "
            + "read once a second. \(frames) camera frames were kept, and speech was transcribed on the Mac. "
            + "Grasp found the jumps and changes of cooling pace in the readings; the steps below were written "
            + "by Gemini from the frames and the transcript, and every reading and quote was checked against the recording.")
        lines += ["", "## What was done", "", "| Time | What happened | Said | Probe |", "|---|---|---|---|"]
        for step in steps {
            let probe = [step.cup.map { cup in step.celsius.map { "\(cup.rawValue) \(String(format: "%.1f", $0)) °C" } ?? cup.rawValue },
                         step.event?.description].compactMap { $0 }.joined(separator: "; ")
            lines.append("| \(clockTime(step.seconds)) | \(step.did) | \(step.said.map { "“\($0)”" } ?? "") | \(probe) |")
        }
        if let record = protocolRecord {
            lines += ["", "## Protocol: \(record.title)", "", "| Step | What it said | Done at | How Grasp knew |", "|---|---|---|---|"]
            lines += record.steps.map { "| \($0.number) | \($0.instruction) | \($0.finished.map(clockTime) ?? "not reached") | \($0.how ?? "") |" }
            if !record.deviations.isEmpty {
                lines += ["", "Differences from the protocol:", ""] + record.deviations.map { "- \(clockTime($0.seconds)): \($0.text)" }
            }
        }
        lines += ["", "## What the probes showed", ""]
        lines += trace.cups.map { "- Cup \($0.cup.rawValue): \(String(format: "%.1f", $0.start)) °C to \(String(format: "%.1f", $0.end)) °C (lowest \(String(format: "%.1f", $0.low)), highest \(String(format: "%.1f", $0.high)))" }
        lines += trace.events.map { "- \($0.description)" }
        lines += ["", "## Observations", ""]
        lines += observations.map { "- \($0.text)" + ($0.numbersChecked ? "" : " (check: uses a number not in the readings)") }
        lines += ["", "## Next", ""]
        lines += next.map { "- \($0)" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Every reading, for a spreadsheet.
    public static func csv(_ readings: [Reading]) -> String {
        (["seconds,cup,celsius"] + readings.sorted { $0.time < $1.time }.map {
            String(format: "%.1f,%@,%.2f", $0.time, $0.cup.rawValue, $0.celsius)
        }).joined(separator: "\n") + "\n"
    }
}
