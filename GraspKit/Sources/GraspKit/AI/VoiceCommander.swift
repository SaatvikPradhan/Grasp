import Foundation

/// Something said to Grasp, as an action.
public enum VoiceCommand: Equatable, Sendable {
    case setTerm(months: Int)
    case setRate(aprPercent: Double)
    case compare
    case switchChart
    case showTemperatures(Bool)
    case reset
    /// Say and show what to ask the dealer.
    case whatToSay
    /// Start or stop checking what the salesperson says (needs everyone's consent).
    case listenToPitch(Bool)
    /// Save the one-page decision summary.
    case summary
    /// Throw away the card in front.
    case removeCard
    /// Any question about the pages or numbers on the canvas.
    case ask(String)
    /// Remove every card.
    case clearCanvas
    /// "These are my notes on this paper": check the notes against the paper.
    case checkNotes
    /// Start or stop taking lab notes (camera, speech and probes).
    case labNotes(Bool)
    /// Save the lab notebook with its data and Methods.
    case saveNotebook
    /// "I'm starting the experiment": follow the protocol on the canvas, step by step.
    case startExperiment
    /// During a guided run: "done" or "next", "go back", "say that again".
    case protocolStep(StepMove)
    /// "We're done", "stop the experiment": stop and write the notebook.
    case finishExperiment
    /// "Map the method": the paper's method as a diagram.
    case mapMethod
    /// "Find related work", "has anyone done this?"
    case findRelatedWork
    /// "Write a dispute", "help me get my money back".
    case writeDispute
    /// Look up what the web says about the thing pointed at.
    case deepDive
    /// What to do about the page in focus: how it compares, and steps to fix it.
    case whatToDo
    /// Put the card in focus away into its group, like a thumbs up.
    case putAway
    /// Add a line to the notes beside the page in focus.
    case takeNote(String)

    public enum StepMove: String, Sendable {
        case next, back, again
    }
    /// A request for something not built yet (fit, export, explain), by name.
    case comingSoon(String)
    /// Speech that wasn't meant for Grasp: a salesperson talking, small talk, noise.
    case none
}

/// Turns what was heard into one `VoiceCommand` with a Gemini function call.
public struct VoiceCommander: Sendable {
    public var client: GeminiClient

    public init(client: GeminiClient) {
        self.client = client
    }

    /// `context` describes what's on the canvas, so "make it shorter" has something to refer to.
    public func interpret(_ transcript: String, context: String) async throws -> VoiceCommand {
        let prompt = """
        You control Grasp, a canvas of charts the user works with their hands and voice.
        On the canvas: \(context)
        The user said: "\(transcript)"
        Call the one function that does what they asked. Spoken numbers count: "four years" \
        is 48 months, "six point four percent" is 6.4. If the words were not meant for Grasp \
        (for example a car salesperson quoting a price or payment, small talk or noise), call \
        not_a_command: a sentence about a deal is not an instruction to Grasp.
        """
        return Self.command(from: try await client.call(Self.functions, prompt: prompt))
    }

    static func command(from call: FunctionCall) -> VoiceCommand {
        switch call.name {
        case "set_term":
            guard let months = call.number("months") else { return .none }
            return .setTerm(months: Int(months.rounded()))
        case "set_rate":
            guard let apr = call.number("apr_percent") else { return .none }
            return .setRate(aprPercent: apr)
        case "compare_loans": return .compare
        case "switch_chart": return .switchChart
        case "show_temperatures": return .showTemperatures(call.flag("visible") ?? true)
        case "reset_canvas": return .reset
        case "what_to_say": return .whatToSay
        case "listen_to_salesperson": return .listenToPitch(call.flag("on") ?? true)
        case "make_summary": return .summary
        case "remove_card": return .removeCard
        case "ask_question": return call.text("question").map { .ask($0) } ?? .none
        case "clear_canvas": return .clearCanvas
        case "check_notes": return .checkNotes
        case "lab_notes": return .labNotes(call.flag("on") ?? true)
        case "start_experiment": return .startExperiment
        case "protocol_step": return .protocolStep(VoiceCommand.StepMove(rawValue: call.text("move") ?? "next") ?? .next)
        case "finish_experiment": return .finishExperiment
        case "map_method": return .mapMethod
        case "find_related_work": return .findRelatedWork
        case "write_dispute": return .writeDispute
        case "deep_dive": return .deepDive
        case "what_to_do": return .whatToDo
        case "put_away": return .putAway
        case "take_note": return call.text("text").map { .takeNote($0) } ?? .none
        case "fit_model": return .comingSoon("fit it")
        case "export_notebook": return .saveNotebook
        case "explain": return .comingSoon("explain")
        default: return .none
        }
    }

    static let functions: [[String: Any]] = [
        function("set_term", "Set the loan length, for example 'make it 48 months', 'four years', 'shorter'.",
                 ["months": ["type": "INTEGER", "description": "Loan length in months"]]),
        function("set_rate", "Set the loan's interest rate (APR).",
                 ["apr_percent": ["type": "NUMBER", "description": "APR as a percent, for example 6.4"]]),
        function("compare_loans", "Put two loan offers side by side, for example dealer financing against a credit union quote."),
        function("switch_chart", "Change how the chart is drawn, between bars and lines."),
        function("show_temperatures", "Show or hide the live cup temperature chart.",
                 ["visible": ["type": "BOOLEAN", "description": "True to show, false to hide"]]),
        function("reset_canvas", "Start over with the demo cards."),
        function("remove_card", "Throw away or delete the card in front, for example 'trash that', 'get rid of this'."),
        function("clear_canvas", "Remove every card from the canvas."),
        function("listen_to_salesperson", "Only when the user explicitly tells Grasp to start or stop listening, for example 'listen to the salesman' or 'stop listening'.",
                 ["on": ["type": "BOOLEAN", "description": "True to start listening, false to stop"]]),
        function("make_summary", "Make the one-page decision summary to print or share."),
        function("fit_model", "Fit the model to the measured data, for example 'fit it'."),
        function("export_notebook", "Export or save the lab notebook, data and methods."),
        function("start_experiment", "The user is starting the experiment or wants to be guided through the protocol, for example 'I'm starting the experiment', 'let's begin', 'guide me through it'."),
        function("protocol_step", "During a guided experiment: the user finished a step or wants to move, for example 'done', 'next', 'okay poured', 'go back', 'say that again', 'repeat'.",
                 ["move": ["type": "STRING", "enum": ["next", "back", "again"], "description": "next when a step is done, back to go back, again to repeat it"]]),
        function("write_dispute", "Write a letter disputing the wrong charges on a bill, for example 'write a dispute', 'help me get my money back', 'complain about this bill'."),
        function("deep_dive", "Look up what sources on the web say about the thing pointed at or the card in focus, for example 'deep dive', 'look this up', 'what do other sources say?', 'is this normal?'."),
        function("what_to_do", "Work out what to do about the page: how it compares with the market and steps to fix its problems, for example 'what should I do about this bill', 'is this a good deal', 'am I overpaying', 'how do I fix this'."),
        function("put_away", "Put the card in focus away to the side, for example 'put it away', 'done with this', 'move this aside'."),
        function("take_note", "Write down a note about the page, for example 'take a note: ask about the late fee', 'note that the promo ends in June', 'write down call them Monday'.",
                 ["text": ["type": "STRING", "description": "The note itself, without 'take a note'"]]),
        function("find_related_work", "Find papers related to this one, or check whether anyone has already studied a direction, for example 'has anyone done this?'."),
        function("map_method", "Show how the paper's study was done: its method, variables, controls and what it didn't control."),
        function("finish_experiment", "Stop the experiment and write up the notes, for example 'we're done', 'stop the experiment', 'finish'."),
        function("lab_notes", "Start or stop taking lab notes of the experiment, for example 'start recording', 'take notes on this', 'stop recording'.",
                 ["on": ["type": "BOOLEAN", "description": "True to start, false to stop and write them up"]]),
        function("explain", "Explain what the chart means."),
        function("what_to_say", "Say what to ask the dealer, what to negotiate, or what to do next."),
        function("check_notes", "The user says these are their notes on a paper, or asks to check or link their notes against the paper."),
        function("ask_question", "Any question about the pages, numbers or charts on the canvas: what, how much, can I, what if, why, where does it say.",
                 ["question": ["type": "STRING", "description": "The question, as asked"]]),
        function("not_a_command", "The words were not meant for Grasp."),
    ]

    private static func function(_ name: String, _ description: String, _ properties: [String: Any]? = nil) -> [String: Any] {
        var declaration: [String: Any] = ["name": name, "description": description]
        if let properties {
            declaration["parameters"] = ["type": "OBJECT", "properties": properties, "required": Array(properties.keys)]
        }
        return declaration
    }
}
