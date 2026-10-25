import Foundation

/// Reads a protocol page into steps Grasp can follow, deciding for each how Grasp will know
/// it's done. Every temperature and time must be printed on the page; a check that relies on a
/// number that isn't there becomes "say done".
public struct ProtocolReader: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
    }

    public func read(page lines: [String], title: String) async throws -> LabProtocol? {
        let raw = try await client.generate(Raw.self, prompt: Self.prompt(lines), schema: Self.schema)
        return Self.checked(raw, lines: lines, fallbackTitle: title)
    }

    struct Raw: Decodable {
        struct Action: Decodable {
            var kind: String
            var cup: String
        }

        struct Step: Decodable {
            var instruction: String
            var quote: String
            var check: String
            var cup: String?
            var celsius: Double?
            var seconds: Double?
            var actions: [Action]?
        }

        var title: String?
        var steps: [Step]
    }

    static func checked(_ raw: Raw, lines: [String], fallbackTitle: String) -> LabProtocol? {
        let steps = raw.steps.enumerated().map { index, item -> LabProtocol.Step in
            let cup = item.cup.flatMap { Cup(rawValue: $0.uppercased()) }
            let printed = { (value: Double) in PrintedNumber.line(of: value, in: lines) != nil }
            let check: LabProtocol.Step.Check
            switch (item.check, cup) {
            case ("rises", let cup?): check = .rises(cup)
            case ("drops", let cup?): check = .drops(cup)
            case ("below", let cup?) where item.celsius.map(printed) == true: check = .below(cup, item.celsius!)
            case ("above", let cup?) where item.celsius.map(printed) == true: check = .above(cup, item.celsius!)
            case ("wait", _) where item.seconds.map { printed($0) || printed($0 / 60) } == true: check = .wait(item.seconds!)
            default: check = .sayDone
            }
            let actions = (item.actions ?? []).compactMap { action -> LabProtocol.Step.Action? in
                guard let cup = Cup(rawValue: action.cup.uppercased()) else { return nil }
                switch action.kind {
                case "pour": return .pour(cup)
                case "lid": return .lid(cup)
                case "ice": return .ice(cup)
                default: return nil
                }
            }
            return LabProtocol.Step(number: index + 1, instruction: item.instruction,
                                    cited: Cited(quote: item.quote, location: SourceLocator.locate(printed: nil, quote: item.quote, in: lines)),
                                    check: check, actions: actions)
        }
        guard !steps.isEmpty else { return nil }
        return LabProtocol(title: raw.title ?? fallbackTitle, steps: steps)
    }

    static func prompt(_ lines: [String]) -> String {
        """
        This page is a lab protocol, read line by line. Turn its procedure into steps Grasp can guide someone \
        through at a bench with three cups, A, B and C, each with a temperature probe.
        title: the protocol's name. steps: each step of the procedure, in order. instruction is the step in a \
        few plain words, said aloud to the person doing it. quote is the step copied exactly from the page.
        check is how Grasp will know the step is done: rises if hot liquid is poured into a cup (that cup's probe \
        jumps up), drops if ice or something cold goes in (it jumps down), below or above if the step waits for a \
        cup to pass a temperature (celsius as printed), wait if it says to wait a length of time (seconds), \
        otherwise say_done. cup is the cup the check watches.
        actions lists what the step does to the cups: pour, lid (a lid goes on) or ice, each with its cup.

        \(lines.joined(separator: "\n").prefix(6_000))
        """
    }

    static let schema: [String: Any] = [
        "type": "OBJECT",
        "properties": [
            "title": ["type": "STRING"],
            "steps": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "instruction": ["type": "STRING"],
                        "quote": ["type": "STRING"],
                        "check": ["type": "STRING", "enum": ["say_done", "rises", "drops", "below", "above", "wait"]],
                        "cup": ["type": "STRING", "enum": ["A", "B", "C"], "nullable": true],
                        "celsius": ["type": "NUMBER", "nullable": true],
                        "seconds": ["type": "NUMBER", "nullable": true],
                        "actions": [
                            "type": "ARRAY",
                            "items": [
                                "type": "OBJECT",
                                "properties": [
                                    "kind": ["type": "STRING", "enum": ["pour", "lid", "ice"]],
                                    "cup": ["type": "STRING", "enum": ["A", "B", "C"]],
                                ],
                                "required": ["kind", "cup"],
                            ],
                        ],
                    ],
                    "required": ["instruction", "quote", "check", "cup", "celsius", "seconds", "actions"],
                ],
            ],
        ],
        "required": ["title", "steps"],
    ]
}
