import Foundation
import Testing
@testable import GraspKit

/// What Grasp sends to the voice: every number in words, so it's said right.
struct SpokenTextTests {
    @Test func money() {
        #expect(SpokenText.words("That's $27,956 in total, with $6,356 of interest.")
                == "That's twenty-seven thousand nine hundred fifty-six dollars in total, with six thousand three hundred fifty-six dollars of interest.")
        #expect(SpokenText.words("$388.28 a month") == "three hundred eighty-eight dollars and twenty-eight cents a month")
        #expect(SpokenText.words("a $7.00 late fee") == "a seven dollars late fee")
        #expect(SpokenText.words("-$10.00 AutoPay") == "minus ten dollars AutoPay")
        #expect(SpokenText.words("$1 off") == "one dollar off")
        #expect(SpokenText.words("$0.50") == "fifty cents")
        #expect(SpokenText.words("$2 million") == "two million dollars")
    }

    @Test func percentsAndDecimals() {
        #expect(SpokenText.words("8.9% for 72 months") == "eight point nine percent for seventy-two months")
        #expect(SpokenText.words("k is 0.031 per minute") == "k is zero point zero three one per minute")
        #expect(SpokenText.words("k 0.019 ± 0.002") == "k zero point zero one nine plus or minus zero point zero zero two")
        #expect(SpokenText.words("Cup A: 71.5 °C") == "Cup A: seventy-one point five degrees Celsius")
    }

    @Test func timesYearsAndOrdinals() {
        #expect(SpokenText.words("At 0:36 the lid goes on") == "At thirty-six seconds the lid goes on")
        #expect(SpokenText.words("jump to 1:05") == "jump to one minute five seconds")
        #expect(SpokenText.words("due by 5:30 PM") == "due by five thirty P M")
        #expect(SpokenText.words("a 2021 Honda Civic") == "a twenty twenty-one Honda Civic")
        #expect(SpokenText.words("the 3rd bill") == "the third bill")
        #expect(SpokenText.words("on the 21st and the 40th") == "on the twenty-first and the fortieth")
        #expect(SpokenText.words("5–10 dollars") == "five to ten dollars")
    }

    @Test func leavesWordsAlone() {
        #expect(SpokenText.words("Ask for the out-the-door price.") == "Ask for the out-the-door price.")
        #expect(SpokenText.words("model v2 and A1") == "model v2 and A1")
    }
}

/// Says numbers with ElevenLabs, then has Gemini write down what it heard. Needs both keys;
/// costs about 200 characters: `swift test --filter LiveSpokenNumbers`.
struct LiveSpokenNumbersTests {
    static let keys = (ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"], TestDocumentTests.key)

    struct Heard: Decodable { var transcript: String }

    @Test(.enabled(if: keys.0 != nil && keys.1 != nil)) func numbersAreSaidRight() async throws {
        let line = "That's $27,956 in total at 8.9% for 72 months, or $388.28 a month. k is 0.031 per minute, and at 0:36 the lid goes on."
        let audio = try await ElevenLabsClient(apiKey: Self.keys.0!).speech(for: line)
        let heard = try await GeminiClient(apiKey: Self.keys.1!).generate(
            Heard.self, prompt: "Write down exactly what is said, with numbers as digits.", media: [.inline(audio, mimeType: "audio/mpeg")],
            schema: ["type": "OBJECT", "properties": ["transcript": ["type": "STRING"]], "required": ["transcript"]])
        print("HEARD \(heard.transcript)")
        let digits = heard.transcript.replacingOccurrences(of: ",", with: "")
        for number in ["27956", "8.9", "72", "388", "0.031", "36"] {
            #expect(digits.contains(number), "didn't hear \(number)")
        }
    }
}
