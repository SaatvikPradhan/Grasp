import Foundation

/// What the bench camera shows during a guided run: what's happening, whether the current step
/// looks done, and anything done differently from it.
public struct BenchLook: Equatable, Sendable {
    /// A few words: "pouring water into cup B".
    public var seeing: String
    public var stepDone: Bool
    /// Something done differently from the step, in a short sentence, or nil.
    public var differs: String?
}

/// Looks at a frame of the bench against the step being followed. It only says a step is done when
/// the frame clearly shows it, so a wrong guess never skips a step.
public struct BenchWatcher: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
        // Whether a step is done is a judgment, so it thinks a little first.
        self.client.thinkingLevel = "low"
    }

    public func look(at jpeg: Data, step: LabProtocol.Step, next: LabProtocol.Step?) async throws -> BenchLook {
        let raw = try await client.generate(Raw.self, prompt: Self.prompt(step: step, next: next), jpeg: jpeg, schema: Self.schema)
        let differs = raw.differs?.trimmingCharacters(in: .whitespacesAndNewlines)
        return BenchLook(seeing: raw.seeing, stepDone: raw.stepDone && raw.sure, differs: differs?.isEmpty == false && raw.sure ? differs : nil)
    }

    struct Raw: Decodable {
        var seeing: String
        var cups: String
        var evidence: String
        var stepDone: Bool
        var differs: String?
        var sure: Bool
    }

    static func prompt(step: LabProtocol.Step, next: LabProtocol.Step?) -> String {
        """
        This is a lab bench right now, seen from a camera. Someone is following a protocol.
        Current step \(step.number): \(step.instruction)
        \(next.map { "Next step \($0.number): \($0.instruction)" } ?? "This is the last step.")
        seeing: what is happening at the bench, in a few words ("pouring water into cup B", "nobody at the bench").
        cups: for each labelled cup, what it has: water or not, a lid or not, ice or not, a probe or not.
        evidence: what in the photo shows the current step is finished, or what is missing; check it against cups, \
        and the cup the step names.
        step_done: true only if the evidence shows the current step finished, for the cup it names.
        differs: only if they did something that goes against the step (the wrong cup, a lid on the wrong cup, \
        too much or too little), say what in one short sentence. A step that simply isn't done yet is null.
        sure: false if the photo is unclear, the bench isn't in view, or you'd be guessing.
        """
    }

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "seeing": ["type": "STRING"],
            "cups": ["type": "STRING"],
            "evidence": ["type": "STRING"],
            "step_done": ["type": "BOOLEAN"],
            "differs": ["type": "STRING", "nullable": true],
            "sure": ["type": "BOOLEAN"],
        ],
        "required": ["seeing", "cups", "evidence", "step_done", "differs", "sure"],
        "propertyOrdering": ["seeing", "cups", "evidence", "step_done", "differs", "sure"],
    ]
}
