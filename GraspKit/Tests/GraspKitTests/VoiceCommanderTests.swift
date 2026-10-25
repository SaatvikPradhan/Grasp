import Foundation
import Testing
@testable import GraspKit

struct VoiceCommandMappingTests {
    @Test func mapsFunctionCallsToCommands() {
        #expect(VoiceCommander.command(from: FunctionCall(name: "set_term", arguments: ["months": .number(48)])) == .setTerm(months: 48))
        #expect(VoiceCommander.command(from: FunctionCall(name: "set_rate", arguments: ["apr_percent": .number(6.4)])) == .setRate(aprPercent: 6.4))
        #expect(VoiceCommander.command(from: FunctionCall(name: "compare_loans")) == .compare)
        #expect(VoiceCommander.command(from: FunctionCall(name: "show_temperatures", arguments: ["visible": .flag(false)])) == .showTemperatures(false))
        #expect(VoiceCommander.command(from: FunctionCall(name: "fit_model")) == .comingSoon("fit it"))
        #expect(VoiceCommander.command(from: FunctionCall(name: "what_to_say")) == .whatToSay)
        #expect(VoiceCommander.command(from: FunctionCall(name: "listen_to_salesperson", arguments: ["on": .flag(false)])) == .listenToPitch(false))
        #expect(VoiceCommander.command(from: FunctionCall(name: "remove_card")) == .removeCard)
        #expect(VoiceCommander.command(from: FunctionCall(name: "not_a_command")) == .none)
        #expect(VoiceCommander.command(from: FunctionCall(name: "set_term")) == .none)   // missing argument
        #expect(VoiceCommander.command(from: FunctionCall(name: "deep_dive")) == .deepDive)
        #expect(VoiceCommander.command(from: FunctionCall(name: "put_away")) == .putAway)
        #expect(VoiceCommander.command(from: FunctionCall(name: "take_note", arguments: ["text": .text("ask about the fee")])) == .takeNote("ask about the fee"))
        #expect(VoiceCommander.command(from: FunctionCall(name: "take_note")) == .none)
    }
}

/// Calls the real API. Runs only with a key: `GEMINI_API_KEY=... swift test --filter LiveVoice`
struct LiveVoiceTests {
    static let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
    let context = "Dealer financing: $21,600 at 8.9% for 72 months. Cup temperatures."

    func heard(_ words: String) async throws -> VoiceCommand {
        try await VoiceCommander(client: GeminiClient(apiKey: Self.key!)).interpret(words, context: context)
    }

    @Test(.enabled(if: key != nil)) func understandsTheDemoLines() async throws {
        #expect(try await heard("make it forty eight months") == .setTerm(months: 48))
        #expect(try await heard("what about four years") == .setTerm(months: 48))
        #expect(try await heard("compare it with the credit union") == .compare)
        #expect(try await heard("switch to a line chart") == .switchChart)
        #expect(try await heard("hide the temperatures") == .showTemperatures(false))
        #expect(try await heard("grasp fit it") == .comingSoon("fit it"))
    }

    @Test(.enabled(if: key != nil)) func understandsMoneyMode() async throws {
        #expect(try await heard("what should I say to them") == .whatToSay)
        #expect(try await heard("trash that card") == .removeCard)
        #expect(try await heard("make me the summary") == .summary)
        #expect(try await heard("start listening to the salesman") == .listenToPitch(true))
    }

    @Test(.enabled(if: key != nil)) func questionsBecomeAsk() async throws {
        guard case .ask(let question) = try await heard("can I cancel this early") else {
            Issue.record("expected a question"); return
        }
        #expect(question.lowercased().contains("cancel"))
        guard case .ask = try await heard("what happens after the first year") else {
            Issue.record("expected a question"); return
        }
    }

    @Test(.enabled(if: key != nil)) func understandsNotesDivesAndPuttingAway() async throws {
        #expect(try await heard("look this up online") == .deepDive)
        #expect(try await heard("what do other sources say about this") == .deepDive)
        #expect(try await heard("put it away") == .putAway)
        guard case .takeNote(let note) = try await heard("take a note ask them about the late fee") else {
            Issue.record("expected a note"); return
        }
        #expect(note.lowercased().contains("late fee"))
        #expect(!note.lowercased().contains("take a note"))
    }

    @Test(.enabled(if: key != nil)) func ignoresTheSalesperson() async throws {
        #expect(try await heard("we can get you in at just three eighty eight a month") == .none)
    }
}
